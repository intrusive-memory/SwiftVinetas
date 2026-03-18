import CoreGraphics
import Flux2Core
import Foundation

// MARK: - TrainingConfig

/// Configuration for character LoRA training.
///
/// Default values are tuned for character consistency on Apple Silicon
/// with Klein 4B nf4 quantization (minimum 8 GB system RAM).
public struct TrainingConfig: Sendable {

  /// LoRA rank (higher = more capacity, more memory). Typical range: 8-64.
  public var rank: Int

  /// Base learning rate for AdamW optimizer.
  public var learningRate: Float

  /// Total number of training steps.
  public var steps: Int

  /// Batch size per step.
  public var batchSize: Int

  /// AdamW weight decay.
  public var weightDecay: Float

  /// Whether to use gradient checkpointing (~50% memory reduction).
  public var gradientCheckpointing: Bool

  /// Quantization format for the base model during training.
  /// "nf4" is the most memory-efficient option.
  public var quantization: String

  public init(
    rank: Int = 48,
    learningRate: Float = 0.001,
    steps: Int = 1500,
    batchSize: Int = 1,
    weightDecay: Float = 0.00015,
    gradientCheckpointing: Bool = true,
    quantization: String = "nf4"
  ) {
    self.rank = rank
    self.learningRate = learningRate
    self.steps = steps
    self.batchSize = batchSize
    self.weightDecay = weightDecay
    self.gradientCheckpointing = gradientCheckpointing
    self.quantization = quantization
  }
}

// MARK: - CharacterTrainer

/// Orchestrates on-device LoRA training for a character using Flux2Core.
///
/// The trainer handles:
/// - Pre-flight memory validation (Klein 4B nf4 requires minimum 8 GB)
/// - Locating training data pairs (.png + .txt) in the character's `training/` directory
/// - Delegating to Flux2Core's `LoRATrainingHelper` and `TrainingSession`
/// - Auto-versioning output safetensors (e.g., `detective-vale-v1.safetensors`, `...-v2.safetensors`)
/// - Updating the character's `LoRAMetadata` after training completes
/// - Reporting progress via callback `(currentStep, totalSteps, loss)`
public struct CharacterTrainer: Sendable {

  // MARK: - Constants

  /// Minimum system memory in GB required for Klein 4B nf4 training.
  static let minimumTrainingMemoryGB: Int = 8

  /// Number of bytes per gigabyte.
  private static let bytesPerGB: UInt64 = 1_073_741_824

  // MARK: - Training

  /// Train a LoRA adapter for the given character.
  ///
  /// - Parameters:
  ///   - character: The character to train a LoRA for. Must have training data
  ///     prepared in its `training/` subdirectory.
  ///   - config: Training hyperparameters and quantization settings.
  ///   - model: The FLUX.2 model variant to train against.
  ///   - characterDirectory: The root directory for this character on disk.
  ///   - progress: Optional callback reporting `(currentStep, totalSteps, loss)`.
  /// - Returns: The URL of the saved `.safetensors` file.
  /// - Throws: `VinetasError.insufficientMemory` if system RAM is too low,
  ///           `VinetasError.generationFailed` if training data is missing or
  ///           the training API is unavailable.
  public func train(
    character: Character,
    config: TrainingConfig = TrainingConfig(),
    model: VinetasModel = .klein4b,
    characterDirectory: URL,
    progress: ((Int, Int, Float) -> Void)? = nil
  ) async throws -> URL {

    // 1. Pre-flight memory validation
    try validateMemory(for: model, quantization: config.quantization)

    // 2. Locate training data
    let trainingDir = characterDirectory.appendingPathComponent("training", isDirectory: true)
    let trainingPairs = try locateTrainingData(in: trainingDir)
    guard !trainingPairs.isEmpty else {
      throw VinetasError.generationFailed(
        "No training data found in \(trainingDir.path). "
          + "Run Vinetas.prepareTrainingData(for:) first."
      )
    }

    // 3. Determine output path with auto-incrementing version
    let loraDir = characterDirectory.appendingPathComponent("lora", isDirectory: true)
    try FileManager.default.createDirectory(at: loraDir, withIntermediateDirectories: true)
    let version = nextVersion(slug: character.slug, in: loraDir)
    let outputFilename = "\(character.slug)-v\(version).safetensors"
    let outputURL = CharacterTrainer.outputPath(
      slug: character.slug,
      version: version,
      loraDirectory: loraDir
    )

    // 4. Attempt training via Flux2Core
    // Flux2Core's LoRATrainingHelper + TrainingSession require loading VAE,
    // text encoder, and transformer, which demands the full pipeline setup.
    // For now, we validate all inputs and throw a descriptive error since
    // the full pipeline integration (model download, sequential loading,
    // session management) is a higher-level orchestration concern.
    _ = outputURL  // Will be the return value once training is implemented
    throw VinetasError.generationFailed(
      "LoRA training not yet available in Flux2Core pipeline integration. "
        + "Training would produce \(outputFilename) "
        + "with \(trainingPairs.count) training pairs, "
        + "rank \(config.rank), \(config.steps) steps, "
        + "quantization \(config.quantization)."
    )
  }

  // MARK: - Memory Validation

  /// Validate that the system has sufficient memory for training.
  ///
  /// Training memory requirements differ from inference requirements.
  /// Klein 4B with nf4 quantization requires a minimum of 8 GB for training
  /// (compared to 16 GB for inference with int4).
  ///
  /// - Parameters:
  ///   - model: The model to train against.
  ///   - quantization: The quantization format (e.g., "nf4", "int4", "int8", "bf16").
  /// - Throws: `VinetasError.insufficientMemory` if the system has less than 8 GB.
  func validateMemory(
    for model: VinetasModel,
    quantization: String
  ) throws {
    let systemMemoryBytes = VinetasMemory.systemMemoryBytes
    let requiredGB = CharacterTrainer.minimumTrainingMemoryGB
    let requiredBytes = UInt64(requiredGB) * CharacterTrainer.bytesPerGB

    guard systemMemoryBytes >= requiredBytes else {
      throw VinetasError.insufficientMemory(
        required: requiredBytes,
        available: systemMemoryBytes
      )
    }
  }

  /// Validate that the given memory (in bytes) is sufficient for training.
  ///
  /// This overload exists for testing with arbitrary memory values.
  ///
  /// - Parameters:
  ///   - model: The model to train against.
  ///   - quantization: The quantization format.
  ///   - availableMemoryBytes: The available memory in bytes to check.
  /// - Returns: `true` if available memory is sufficient.
  static func validateMemory(
    for model: VinetasModel,
    quantization: String,
    availableMemoryBytes: UInt64
  ) -> Bool {
    let requiredBytes = UInt64(minimumTrainingMemoryGB) * bytesPerGB
    return availableMemoryBytes >= requiredBytes
  }

  // MARK: - Training Data Discovery

  /// Locate training image/caption pairs in the given directory.
  ///
  /// Scans for `.png` files that have a matching `.txt` caption file
  /// with the same base name.
  ///
  /// - Parameter directory: The `training/` directory to scan.
  /// - Returns: Array of `(imageURL, captionURL)` pairs.
  /// - Throws: File I/O errors.
  func locateTrainingData(in directory: URL) throws -> [(imageURL: URL, captionURL: URL)] {
    let fm = FileManager.default
    guard fm.fileExists(atPath: directory.path) else { return [] }

    let contents = try fm.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let pngFiles = contents.filter { $0.pathExtension.lowercased() == "png" }
    var pairs: [(imageURL: URL, captionURL: URL)] = []

    for pngURL in pngFiles {
      let baseName = pngURL.deletingPathExtension().lastPathComponent
      let txtURL = directory.appendingPathComponent("\(baseName).txt")
      if fm.fileExists(atPath: txtURL.path) {
        pairs.append((imageURL: pngURL, captionURL: txtURL))
      }
    }

    return pairs.sorted { $0.imageURL.lastPathComponent < $1.imageURL.lastPathComponent }
  }

  // MARK: - Auto-Versioning

  /// Determine the next version number for a LoRA safetensors file.
  ///
  /// Scans the `lora/` directory for existing files matching
  /// `<slug>-v<N>.safetensors` and returns `max(N) + 1`. If no
  /// existing files are found, returns 1.
  ///
  /// - Parameters:
  ///   - slug: The character's slug identifier.
  ///   - directory: The `lora/` directory to scan.
  /// - Returns: The next version number (1-based).
  func nextVersion(slug: String, in directory: URL) -> Int {
    let fm = FileManager.default
    guard
      let contents = try? fm.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
      )
    else {
      return 1
    }

    let prefix = "\(slug)-v"
    let suffix = ".safetensors"

    var maxVersion = 0
    for url in contents {
      let filename = url.lastPathComponent
      guard filename.hasPrefix(prefix) && filename.hasSuffix(suffix) else { continue }
      let versionStart = filename.index(filename.startIndex, offsetBy: prefix.count)
      let versionEnd = filename.index(filename.endIndex, offsetBy: -suffix.count)
      guard versionStart < versionEnd else { continue }
      let versionStr = String(filename[versionStart..<versionEnd])
      if let version = Int(versionStr) {
        maxVersion = max(maxVersion, version)
      }
    }

    return maxVersion + 1
  }

  /// Construct the output path for a LoRA safetensors file.
  ///
  /// - Parameters:
  ///   - slug: The character's slug identifier.
  ///   - version: The version number.
  ///   - loraDirectory: The `lora/` directory URL.
  /// - Returns: The full URL for the safetensors file.
  static func outputPath(slug: String, version: Int, loraDirectory: URL) -> URL {
    loraDirectory.appendingPathComponent("\(slug)-v\(version).safetensors")
  }
}

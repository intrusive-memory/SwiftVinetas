import CoreGraphics
import Flux2Core
import Foundation
import Tuberia

// MARK: - VinetasClient

/// The primary public API for SwiftVinetas.
///
/// `VinetasClient` routes all generation, model management, and engine queries
/// through an ``EngineRouter``. Use the ``shared`` singleton for production
/// or inject a custom router via ``init(router:)`` for testing.
///
/// ```swift
/// // Production usage
/// let image = try await VinetasClient.shared.generate(prompt: "A sunset over the ocean")
///
/// // Testing with a mock engine
/// let router = EngineRouter(engines: [mockEngine])
/// let client = VinetasClient(router: router)
/// ```
public final class VinetasClient: Sendable {

  /// The shared singleton instance, pre-configured with all available engines.
  public static let shared = VinetasClient()

  /// The engine router used to dispatch generation requests.
  public let router: EngineRouter

  /// The current SwiftVinetas library version.
  public static let version = "0.7.0"

  /// Default initializer that registers engines based on runtime memory detection.
  ///
  /// ``PixArtEngine`` is always registered (requires 8 GB, matches all iPads and most Macs).
  /// ``Flux2Engine`` is registered only when the device has 16+ GB of memory (macOS high-memory
  /// configurations). This eliminates compile-time platform gates in favour of runtime checks,
  /// so both engines compile on every platform and only registration is conditional.
  public init() {
    var engines: [any ImageGenerationEngine] = [PixArtEngine()]
    if DeviceCapability.current.totalMemoryGB >= 16 {
      engines.append(Flux2Engine())
    }
    self.router = EngineRouter(engines: engines)
  }

  /// Test initializer that accepts a custom router.
  ///
  /// Use this to inject a ``MockEngine`` or other test doubles.
  ///
  /// - Parameter router: The engine router to use for dispatch.
  public init(router: EngineRouter) {
    self.router = router
  }
}

// MARK: - Generation

extension VinetasClient {

  /// Generate a single panel image from a text prompt.
  ///
  /// Resolves the engine via the router, composes the prompt from style and panel
  /// prompts, builds a ``GenerationRequest`` from the style config, calls
  /// `engine.generate(request:stepProgress:)`, and returns the generated image.
  ///
  /// - Parameters:
  ///   - prompt: Text description of the panel to generate.
  ///   - style: Optional style configuration for consistent look across panels.
  ///   - model: The model descriptor to use (default: ``defaultModel``).
  /// - Returns: The generated image as a `CGImage`.
  /// - Throws: ``VinetasError/engineNotFound(engineID:)`` if the engine is unavailable,
  ///           ``VinetasError/generationFailed(_:)`` if image generation fails.
  public func generate(
    prompt: String,
    style: StyleConfig? = nil,
    model: any ModelDescriptor = VinetasClient.defaultModel
  ) async throws -> CGImage {
    let effectiveStyle = style ?? StyleConfig()
    let engine = try await router.engine(for: model)
    let composedPrompt = composePrompt(panelPrompt: prompt, style: effectiveStyle)
    let request = buildRequest(
      prompt: composedPrompt,
      style: effectiveStyle,
      mode: .textToImage
    )
    try await engine.loadModel(model, progress: { _ in })
    let result = try await engine.generate(request: request, stepProgress: nil)
    return result.image
  }

  /// Generate a sequence of panels from an array of prompts.
  ///
  /// Iterates panels calling the engine per-panel. If `referenceImages` are
  /// provided, uses image-to-image generation for character consistency.
  ///
  /// - Parameters:
  ///   - prompts: Ordered text descriptions for each panel.
  ///   - referenceImages: Optional reference images for character consistency.
  ///   - style: Optional style configuration applied to all panels.
  ///   - model: The model descriptor to use (default: ``defaultModel``).
  ///   - progress: Callback reporting (currentPanel, totalPanels).
  ///   - stepProgress: Callback reporting step-level progress per panel.
  /// - Returns: Array of `CGImage` values, one per prompt.
  public func generateSequence(
    prompts: [String],
    referenceImages: [CGImage]? = nil,
    style: StyleConfig? = nil,
    model: any ModelDescriptor = VinetasClient.defaultModel,
    progress: ((Int, Int) -> Void)? = nil,
    stepProgress: (
      @Sendable (_ currentStep: Int, _ totalSteps: Int, _ elapsed: TimeInterval) -> Void
    )? = nil
  ) async throws -> [CGImage] {
    guard !prompts.isEmpty else { return [] }

    let effectiveStyle = style ?? StyleConfig()
    let engine = try await router.engine(for: model)
    try await engine.loadModel(model, progress: { _ in })

    let useImageToImage = referenceImages.map { !$0.isEmpty } ?? false
    let totalPanels = prompts.count
    var images: [CGImage] = []

    for (index, prompt) in prompts.enumerated() {
      progress?(index + 1, totalPanels)

      let composedPrompt = composePrompt(panelPrompt: prompt, style: effectiveStyle)
      let mode: GenerationRequest.GenerationMode =
        useImageToImage
        ? .imageToImage(references: referenceImages!)
        : .textToImage
      let request = buildRequest(
        prompt: composedPrompt,
        style: effectiveStyle,
        mode: mode
      )
      let result = try await engine.generate(request: request, stepProgress: stepProgress)
      images.append(result.image)
    }

    return images
  }

  /// Generate a single panel image with character LoRA and trigger word injection.
  ///
  /// Checks LoRA compatibility against the selected engine: if the character's
  /// trained LoRA engine matches (via `compatibleEngines` when available, or
  /// `model` field otherwise), loads the LoRA before generation and unloads it
  /// after. If the LoRA is incompatible with the engine, proceeds with
  /// prompt-only consistency and logs a warning.
  ///
  /// - Parameters:
  ///   - prompt: Text description of the panel to generate.
  ///   - character: The character whose LoRA and trigger word to apply.
  ///   - style: Optional style configuration.
  ///   - model: The model descriptor to use (default: ``defaultModel``).
  /// - Returns: The generated image as a `CGImage`.
  public func generate(
    prompt: String,
    character: Character,
    style: StyleConfig? = nil,
    model: any ModelDescriptor = VinetasClient.defaultModel
  ) async throws -> CGImage {
    let effectiveStyle = style ?? StyleConfig()
    let engine = try await router.engine(for: model)
    try await engine.loadModel(model, progress: { _ in })

    // Determine whether LoRA is compatible with this engine
    var loraLoaded = false
    if let lora = character.lora {
      let compatible = isLoRACompatible(lora: lora, engineID: engine.engineID)
      if compatible && engine.supports(.loraInference) {
        let manager = CharacterManager()
        let charDir = manager.characterDirectory(slug: character.slug)
        let loraURL = charDir.appendingPathComponent(lora.path)
        try await engine.loadLoRA(at: loraURL, scale: lora.scale)
        loraLoaded = true
      } else {
        let warning =
          "[SwiftVinetas] LoRA for '\(character.name)' is incompatible with engine '\(engine.engineID)'. "
          + "Proceeding with prompt-only consistency.\n"
        if let data = warning.data(using: .utf8) {
          FileHandle.standardError.write(data)
        }
      }
    }

    // Compose prompt: trigger word + style + panel prompt
    let composedPrompt = composeCharacterPrompt(
      panelPrompt: prompt,
      character: character,
      style: effectiveStyle
    )
    let request = buildRequest(
      prompt: composedPrompt,
      style: effectiveStyle,
      mode: .textToImage
    )
    let result = try await engine.generate(request: request, stepProgress: nil)

    // Unload LoRA to prevent bleeding into subsequent generations
    if loraLoaded {
      await engine.unloadLoRA()
    }

    return result.image
  }

  /// Generate a fast, low-quality preview image for rapid prompt iteration.
  ///
  /// FLUX.2-only fast path — forces Klein 4B, 4 inference steps, and 512x512
  /// output for quick turnaround. Resolves directly to the `"flux2"` engine
  /// via ``EngineRouter/engine(forEngineID:)``.
  ///
  /// - Parameter prompt: Text description of the panel to preview.
  /// - Returns: The generated image as a `CGImage` at 512x512.
  public func preview(prompt: String) async throws -> CGImage {
    let previewModel = Flux2ModelDescriptor.klein4B
    let engine = try await router.engine(forEngineID: "flux2")
    try await engine.loadModel(previewModel, progress: { _ in })
    let request = GenerationRequest(
      prompt: prompt,
      steps: 4,
      guidanceScale: previewModel.defaultGuidance,
      width: 512,
      height: 512,
      mode: .textToImage
    )
    let result = try await engine.generate(request: request, stepProgress: nil)
    return result.image
  }
}

// MARK: - Model Management

extension VinetasClient {

  /// Download a model, delegating through the engine router.
  ///
  /// Resolves the engine for the given model descriptor and delegates the
  /// download to `engine.download(_:progress:)`.
  ///
  /// - Parameters:
  ///   - model: The model descriptor to download.
  ///   - progress: Optional callback reporting download progress.
  public func download(
    model: any ModelDescriptor,
    progress: (@Sendable (VinetasDownloadProgress) -> Void)? = nil
  ) async throws {
    let engine = try await router.engine(for: model)
    try await engine.download(model) { dp in
      progress?(VinetasDownloadProgress(overallProgress: dp.fraction, message: dp.message))
    }
  }

  /// Check whether a model is available on disk, via the engine router.
  ///
  /// - Parameter model: The model descriptor to check.
  /// - Returns: `true` if the model's weights are downloaded and ready.
  public func isAvailable(_ model: any ModelDescriptor) async throws -> Bool {
    let engine = try await router.engine(for: model)
    return engine.isAvailable(model)
  }

  /// Delete a model's weights from local storage, via the engine router.
  ///
  /// - Parameter model: The model descriptor to delete.
  public func delete(_ model: any ModelDescriptor) async throws {
    let engine = try await router.engine(for: model)
    try await engine.delete(model)
  }

  /// List all known models across all registered engines with availability status.
  ///
  /// - Returns: An array of ``VinetasModelInfo``, one per known model.
  public func listModels() async -> [VinetasModelInfo] {
    let models = await router.allModels
    return models.map { model in
      VinetasModelInfo(
        name: model.displayName,
        size: 0,
        downloadDate: nil,
        isDownloaded: false
      )
    }
  }

  /// Validate whether the system has sufficient memory for a model.
  ///
  /// Delegates to `engine.validateMemory(for:)`.
  ///
  /// - Parameter model: The model descriptor to validate.
  /// - Returns: A ``MemoryValidation`` result.
  public func validateMemory(for model: any ModelDescriptor) async throws -> MemoryValidation {
    let engine = try await router.engine(for: model)
    return engine.validateMemory(for: model)
  }
}

// MARK: - Private Prompt Helpers

extension VinetasClient {

  /// Compose a prompt from style config and panel prompt.
  ///
  /// Format: `"<stylePrompt>, <panelPrompt>"` (style omitted if empty).
  private func composePrompt(panelPrompt: String, style: StyleConfig) -> String {
    if style.stylePrompt.isEmpty {
      return panelPrompt
    }
    return "\(style.stylePrompt), \(panelPrompt)"
  }

  /// Compose a character-aware prompt.
  ///
  /// Format: `"<triggerWord>, <stylePrompt>, <panelPrompt>"` (each part omitted if empty).
  private func composeCharacterPrompt(
    panelPrompt: String,
    character: Character,
    style: StyleConfig
  ) -> String {
    var parts: [String] = []
    if !character.triggerWord.isEmpty {
      parts.append(character.triggerWord)
    }
    if !style.stylePrompt.isEmpty {
      parts.append(style.stylePrompt)
    }
    parts.append(panelPrompt)
    return parts.joined(separator: ", ")
  }

  /// Build a ``GenerationRequest`` from a composed prompt and style config.
  private func buildRequest(
    prompt: String,
    style: StyleConfig,
    mode: GenerationRequest.GenerationMode
  ) -> GenerationRequest {
    GenerationRequest(
      prompt: prompt,
      negativePrompt: style.negativePrompt,
      steps: style.steps,
      guidanceScale: style.guidanceScale,
      seed: style.seed,
      width: style.width,
      height: style.height,
      mode: mode
    )
  }

  /// Check whether a character LoRA is compatible with a given engine.
  ///
  /// If `compatibleEngines` is empty (no restriction recorded), assumes compatible.
  /// Otherwise, checks that the given `engineID` is listed in `compatibleEngines`.
  private func isLoRACompatible(lora: LoRAMetadata, engineID: String) -> Bool {
    guard !lora.compatibleEngines.isEmpty else {
      // No compatibility restriction recorded — assume compatible
      return true
    }
    return lora.compatibleEngines.contains(engineID)
  }
}

// MARK: - Convenience Model Accessors

extension VinetasClient {

  /// The default model for generation. Currently FLUX.2 Klein 4B.
  public static var defaultModel: any ModelDescriptor { Flux2ModelDescriptor.klein4B }

  /// FLUX.2 Klein 4B model descriptor.
  public static var klein4B: any ModelDescriptor { Flux2ModelDescriptor.klein4B }

  /// FLUX.2 Klein 9B model descriptor.
  public static var klein9B: any ModelDescriptor { Flux2ModelDescriptor.klein9B }

  /// PixArt-Sigma XL model descriptor.
  public static var pixartSigmaXL: any ModelDescriptor { PixArtModelDescriptor.sigmaXL }
}

// MARK: - Deprecated Vinetas Enum

/// SwiftVinetas - Storyboard and comic panel generation from text prompts.
///
/// Generates sequential visual panels from text descriptions using
/// FLUX.2 Klein models on Apple Silicon via MLX.
///
/// - Important: Use ``VinetasClient/shared`` instead. This enum is preserved
///   for backward compatibility and will be removed in a future release.
@available(*, deprecated, message: "Use VinetasClient.shared instead")
public enum Vinetas: Sendable {

  /// The current SwiftVinetas library version.
  public static let version = "0.7.0"

  // MARK: - Generation

  /// Generate a single panel image from a text prompt.
  /// - Parameters:
  ///   - prompt: Text description of the panel to generate.
  ///   - style: Optional style configuration for consistent look across panels.
  ///   - model: The FLUX.2 model variant to use (default: Klein 4B).
  /// - Returns: The generated image as a CGImage.
  public static func generate(
    prompt: String,
    style: StyleConfig? = nil,
    model: VinetasModel = .klein4b
  ) async throws -> CGImage {
    try await VinetasClient.shared.generate(
      prompt: prompt,
      style: style,
      model: model.descriptor
    )
  }

  /// Generate a sequence of panels from an array of prompts.
  ///
  /// If `referenceImages` are provided, uses image-to-image generation
  /// for character consistency across all panels. Otherwise, uses text-to-image.
  ///
  /// - Parameters:
  ///   - prompts: Ordered text descriptions for each panel.
  ///   - referenceImages: Optional reference images for character consistency (up to 3).
  ///   - style: Optional style configuration applied to all panels.
  ///   - model: The FLUX.2 model variant to use.
  ///   - progress: Callback reporting (currentPanel, totalPanels).
  ///   - stepProgress: Callback reporting step-level progress (currentStep, totalSteps, elapsed).
  /// - Returns: Array of generated CGImages, one per prompt.
  public static func generateSequence(
    prompts: [String],
    referenceImages: [CGImage]? = nil,
    style: StyleConfig? = nil,
    model: VinetasModel = .klein4b,
    progress: ((Int, Int) -> Void)? = nil,
    stepProgress: (
      @Sendable (_ currentStep: Int, _ totalSteps: Int, _ elapsed: TimeInterval) -> Void
    )? = nil
  ) async throws -> [CGImage] {
    try await VinetasClient.shared.generateSequence(
      prompts: prompts,
      referenceImages: referenceImages,
      style: style,
      model: model.descriptor,
      progress: progress,
      stepProgress: stepProgress
    )
  }

  /// Generate panels from a YAML prompt file.
  ///
  /// Reads and parses the YAML file at the given URL, then iterates each panel
  /// sequentially, using the project-level style as defaults with per-panel overrides.
  ///
  /// - Parameters:
  ///   - url: Path to the YAML prompt file.
  ///   - model: The FLUX.2 model variant to use.
  ///   - progress: Callback reporting (currentPanel, totalPanels).
  ///   - stepProgress: Callback reporting step-level progress (currentStep, totalSteps, elapsed).
  /// - Returns: Array of PanelOutput containing images and metadata.
  public static func generateFromFile(
    _ url: URL,
    model: VinetasModel = .klein4b,
    progress: ((Int, Int) -> Void)? = nil,
    stepProgress: (
      @Sendable (_ currentStep: Int, _ totalSteps: Int, _ elapsed: TimeInterval) -> Void
    )? = nil
  ) async throws -> [PanelOutput] {
    // generateFromFile retains its own implementation since VinetasClient
    // does not yet expose a prompt-file API; delegate to VinetasPipeline.
    let promptFile = try PromptFile.parse(url: url)
    return try await VinetasPipeline.generateFromPromptFile(
      promptFile,
      model: model,
      panelProgress: progress,
      stepProgress: stepProgress
    )
  }

  // MARK: - Character-Aware Generation

  /// Generate a single panel image with character LoRA and trigger word injection.
  ///
  /// Loads the character's LoRA adapter (if available), prepends the character's
  /// trigger word to the prompt, generates the image, and unloads the LoRA
  /// to prevent bleeding into subsequent generations.
  ///
  /// - Parameters:
  ///   - prompt: Text description of the panel to generate.
  ///   - character: The character whose LoRA and trigger word to apply.
  ///   - style: Optional style configuration for consistent look across panels.
  ///   - model: The FLUX.2 model variant to use (default: Klein 4B).
  /// - Returns: The generated image as a CGImage.
  public static func generate(
    prompt: String,
    character: Character,
    style: StyleConfig? = nil,
    model: VinetasModel = .klein4b
  ) async throws -> CGImage {
    try await VinetasClient.shared.generate(
      prompt: prompt,
      character: character,
      style: style,
      model: model.descriptor
    )
  }

  // MARK: - Preview

  /// Generate a fast, low-quality preview image for rapid prompt iteration.
  ///
  /// Forces Klein 4B, 4 inference steps, and 512x512 output for quick turnaround.
  /// Use this to validate prompt composition before committing to a full generation run.
  ///
  /// - Parameter prompt: Text description of the panel to preview.
  /// - Returns: The generated image as a CGImage at 512x512.
  public static func preview(prompt: String) async throws -> CGImage {
    try await VinetasClient.shared.preview(prompt: prompt)
  }

  // MARK: - Understanding

  /// Classify an image using ViT-B/16 and return top-K predictions.
  ///
  /// Downloads model weights on the first call (idempotent). Subsequent calls
  /// reuse the cached model loaded in memory.
  ///
  /// - Parameters:
  ///   - image: The CGImage to classify.
  ///   - topK: Maximum number of classifications to return (default 5).
  /// - Returns: Array of `Classification` sorted by confidence, highest first.
  /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
  ///           `VinetasError.generationFailed` for runtime errors.
  public static func classify(
    image: CGImage,
    topK: Int = 5
  ) async throws -> [Classification] {
    try await ImageClassifier.shared.classify(image: image, topK: topK)
  }

  /// Classify an image loaded from a file URL using ViT-B/16.
  ///
  /// - Parameters:
  ///   - file: File URL to the image (JPEG, PNG, HEIC, etc.).
  ///   - topK: Maximum number of classifications to return (default 5).
  /// - Returns: Array of `Classification` sorted by confidence, highest first.
  /// - Throws: `VinetasError.generationFailed` if the image cannot be loaded,
  ///           plus any errors from `classify(image:topK:)`.
  public static func classify(
    file: URL,
    topK: Int = 5
  ) async throws -> [Classification] {
    try await ImageClassifier.shared.classify(file: file, topK: topK)
  }

  // MARK: - Feature Extraction

  /// Extract a 768-dimensional feature vector from an image using DINOv2-B/14.
  ///
  /// Downloads model weights on the first call (idempotent). Subsequent calls
  /// reuse the cached model loaded in memory.
  ///
  /// - Parameter image: The CGImage to extract features from.
  /// - Returns: Array of 768 Float values representing the CLS token embedding.
  /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
  ///           `VinetasError.generationFailed` for runtime errors.
  public static func extractFeatures(from image: CGImage) async throws -> [Float] {
    try await FeatureExtractor.shared.extractFeatures(from: image)
  }

  /// Extract a 768-dimensional feature vector from an image loaded from a file URL.
  ///
  /// - Parameter url: File URL to the image (JPEG, PNG, HEIC, etc.).
  /// - Returns: Array of 768 Float values representing the CLS token embedding.
  /// - Throws: `VinetasError.generationFailed` if the image cannot be loaded,
  ///           plus any errors from `extractFeatures(from:)`.
  public static func extractFeatures(from url: URL) async throws -> [Float] {
    try await FeatureExtractor.shared.extractFeatures(from: url)
  }

  /// Compute the cosine similarity between two images using DINOv2-B/14 features.
  ///
  /// Downloads model weights on the first call (idempotent). Extracts feature vectors
  /// from both images and returns their cosine similarity.
  ///
  /// - Parameters:
  ///   - image1: The first CGImage.
  ///   - image2: The second CGImage.
  /// - Returns: Cosine similarity in the range `[-1, 1]`.
  /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
  ///           `VinetasError.generationFailed` for runtime errors.
  public static func similarity(between image1: CGImage, and image2: CGImage) async throws -> Float
  {
    let features1 = try await FeatureExtractor.shared.extractFeatures(from: image1)
    let features2 = try await FeatureExtractor.shared.extractFeatures(from: image2)
    return cosineSimilarity(features1, features2)
  }

  // MARK: - Character Verification

  /// Verify character consistency by computing pairwise DINOv2 similarity
  /// across all reference sheet images.
  ///
  /// Loads all PNG images from `characters/<slug>/references/`, extracts
  /// DINOv2 feature vectors, and computes cosine similarity between every
  /// pair. The character passes verification if all pairwise similarities
  /// meet or exceed the threshold.
  ///
  /// - Parameters:
  ///   - character: The character whose reference sheets to verify.
  ///   - threshold: Minimum cosine similarity required for each pair (default: 0.6).
  /// - Returns: A `VerificationReport` with pairwise scores and pass/fail status.
  /// - Throws: `VinetasError.generationFailed` if no reference images are found or
  ///           images cannot be loaded.
  public static func verifyCharacter(
    _ character: Character,
    threshold: Float = 0.6
  ) async throws -> VerificationReport {
    let manager = CharacterManager()
    let referencesDir = manager.characterDirectory(slug: character.slug)
      .appendingPathComponent("references", isDirectory: true)

    let fm = FileManager.default
    guard fm.fileExists(atPath: referencesDir.path) else {
      throw VinetasError.generationFailed(
        "No references directory found for character '\(character.name)'. "
          + "Generate reference sheets first with Vinetas.generateReferenceSheets(for:)."
      )
    }

    let contents = try fm.contentsOfDirectory(
      at: referencesDir,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    let pngFiles =
      contents
      .filter { $0.pathExtension.lowercased() == "png" }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }

    guard pngFiles.count >= 2 else {
      throw VinetasError.generationFailed(
        "Need at least 2 reference images for verification, found \(pngFiles.count). "
          + "Generate reference sheets first with Vinetas.generateReferenceSheets(for:)."
      )
    }

    // Extract features for each image
    var featuresByName: [(name: String, features: [Float])] = []
    for url in pngFiles {
      let features = try await FeatureExtractor.shared.extractFeatures(from: url)
      let name = url.deletingPathExtension().lastPathComponent
      featuresByName.append((name: name, features: features))
    }

    // Compute pairwise similarities
    var pairs: [(view1: String, view2: String, similarity: Float)] = []
    for i in 0..<featuresByName.count {
      for j in (i + 1)..<featuresByName.count {
        let sim = cosineSimilarity(featuresByName[i].features, featuresByName[j].features)
        pairs.append(
          (
            view1: featuresByName[i].name,
            view2: featuresByName[j].name,
            similarity: sim
          ))
      }
    }

    let allAboveThreshold = pairs.allSatisfy { $0.similarity >= threshold }
    let avgSimilarity: Float =
      pairs.isEmpty
      ? 0.0
      : pairs.map(\.similarity).reduce(0, +) / Float(pairs.count)

    return VerificationReport(
      pairs: pairs,
      passed: allAboveThreshold,
      threshold: threshold,
      averageSimilarity: avgSimilarity
    )
  }

  // MARK: - Model Management

  /// Download a FLUX.2 model, caching it at `~/Library/SharedModels/`.
  ///
  /// Idempotent: if the model is already cached, returns immediately.
  ///
  /// - Parameters:
  ///   - model: The model variant to download.
  ///   - progress: Optional callback reporting download progress.
  /// - Throws: `VinetasError.downloadFailed` if the download fails.
  public static func download(
    model: VinetasModel,
    progress: (@Sendable (VinetasDownloadProgress) -> Void)? = nil
  ) async throws {
    try await VinetasClient.shared.download(model: model.descriptor, progress: progress)
  }

  /// List all known FLUX.2 models with their cache status.
  ///
  /// Returns one entry per known model variant, including whether it has
  /// been downloaded, its size on disk, and its download date.
  ///
  /// - Returns: An array of `VinetasModelInfo` for each known model.
  /// - Throws: If the shared models directory cannot be read.
  public static func listModels() async -> [VinetasModelInfo] {
    await VinetasClient.shared.listModels()
  }

  /// Validate whether the system has sufficient memory for a model.
  ///
  /// Checks the system's physical memory against the model's minimum
  /// requirement (Klein 4B: 16 GB, Klein 9B: 24 GB).
  ///
  /// - Parameter model: The model to validate against.
  /// - Returns: `true` if the system has enough memory to load the model.
  /// - Throws: `VinetasError.insufficientMemory` if validation fails.
  public static func validateMemory(for model: VinetasModel) async throws -> Bool {
    let validation = try await VinetasClient.shared.validateMemory(for: model.descriptor)
    switch validation {
    case .ok:
      return true
    case .warning:
      return true
    case .insufficient(let required, let available):
      throw VinetasError.insufficientMemory(required: required, available: available)
    }
  }

  // MARK: - Character Pipeline

  /// Create a new character with directory structure and optional source photo.
  ///
  /// Sets up `~/Library/SwiftVinetas/characters/<slug>/` with `source/`,
  /// `references/`, `training/`, and `lora/` subdirectories, writes a
  /// `character.yaml` manifest, and optionally saves the source photo as PNG.
  ///
  /// - Parameters:
  ///   - name: Human-readable character name (e.g., "Detective Vale").
  ///   - photo: Optional source photograph. Written to `source/<slug>-photo-01.png`.
  ///   - slug: Optional slug; derived from `name` if omitted (e.g., "detective-vale").
  ///   - description: Plain-text description of the character's appearance.
  /// - Returns: The newly created `Character` value.
  /// - Throws: File I/O or serialization errors.
  public static func createCharacter(
    name: String,
    photo: CGImage? = nil,
    slug: String? = nil,
    description: String = ""
  ) throws -> Character {
    let manager = CharacterManager()
    return try manager.createCharacter(
      name: name,
      photo: photo,
      slug: slug,
      description: description
    )
  }

  /// List all characters stored under `~/Library/SwiftVinetas/characters/`.
  ///
  /// Characters with a missing or malformed `character.yaml` are silently skipped.
  ///
  /// - Returns: Array of `Character` values sorted by name.
  /// - Throws: File I/O errors reading the characters directory.
  public static func listCharacters() throws -> [Character] {
    try CharacterManager().listCharacters()
  }

  /// Load a character by slug from `~/Library/SwiftVinetas/characters/<slug>/`.
  ///
  /// - Parameter slug: The character's slug identifier (e.g., "detective-vale").
  /// - Returns: The decoded `Character`.
  /// - Throws: File I/O or YAML decoding errors.
  public static func loadCharacter(slug: String) throws -> Character {
    try CharacterManager().loadCharacter(slug: slug)
  }

  // MARK: - Reference Sheet Generation

  /// Generate pencil-sketch turnaround reference sheets from a character's source photo.
  ///
  /// Loads the first source photo from the character's directory, then uses FLUX.2
  /// img2img to generate pencil-sketch reference views at each requested angle.
  /// Generated images are saved to `characters/<slug>/references/<view>.png`.
  ///
  /// - Parameters:
  ///   - character: The character to generate reference sheets for. Must have at least
  ///     one entry in `sourcePhotos`.
  ///   - views: The turnaround angles to render (default: all four canonical views).
  ///   - strength: How much to deviate from the source photo (0.0-1.0). Default: 0.65.
  ///   - model: The FLUX.2 model variant to use (default: Klein 4B).
  ///   - progress: Optional callback reporting `(currentView, totalViews)`.
  /// - Returns: Array of generated CGImages, one per requested view.
  /// - Throws: `VinetasError.generationFailed` if the character has no source photos or
  ///           the photo cannot be loaded, `VinetasError.insufficientMemory` if system
  ///           RAM is too low for the selected model.
  public static func generateReferenceSheets(
    for character: Character,
    views: [ReferenceView] = ReferenceView.allCases.map { $0 },
    strength: Float = 0.65,
    model: VinetasModel = .klein4b,
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [CGImage] {
    guard let firstPhoto = character.sourcePhotos.first else {
      throw VinetasError.generationFailed(
        "Character '\(character.name)' has no source photos. "
          + "Add a source photo with createCharacter(name:photo:)."
      )
    }

    let manager = CharacterManager()
    let photoURL = manager.characterDirectory(slug: character.slug)
      .appendingPathComponent(firstPhoto)

    guard let dataProvider = CGDataProvider(url: photoURL as CFURL),
      let sourceImage = CGImage(
        pngDataProviderSource: dataProvider,
        decode: nil,
        shouldInterpolate: true,
        intent: .defaultIntent
      )
    else {
      throw VinetasError.generationFailed(
        "Could not load source photo at \(photoURL.path)"
      )
    }

    return try await ReferenceSheetGenerator.generate(
      for: character,
      views: views,
      sourceImage: sourceImage,
      strength: strength,
      model: model.descriptor,
      progress: progress
    )
  }

  // MARK: - LoRA Training

  /// Train a LoRA adapter for a character using on-device FLUX.2 fine-tuning.
  ///
  /// Loads the character's training data (image/caption pairs from `training/`),
  /// validates system memory, runs LoRA training via Flux2Core, and saves the
  /// resulting `.safetensors` file to `characters/<slug>/lora/<slug>-v<N>.safetensors`
  /// with auto-incrementing version numbers.
  ///
  /// After training completes, the character's `lora` metadata is updated and
  /// the manifest is re-saved.
  ///
  /// **Prerequisites**: Call `prepareTrainingData(for:)` before training to
  /// populate the `training/` directory.
  ///
  /// **Memory**: Klein 4B nf4 requires minimum 8 GB system RAM for training.
  ///
  /// - Parameters:
  ///   - character: The character to train a LoRA for.
  ///   - config: Training hyperparameters (default: rank 48, 1500 steps, nf4).
  ///   - model: The FLUX.2 model variant to train against (default: Klein 4B).
  ///   - progress: Optional callback reporting `(currentStep, totalSteps, loss)`.
  /// - Returns: The URL of the saved `.safetensors` file.
  /// - Throws: `VinetasError.insufficientMemory` if system RAM is too low,
  ///           `VinetasError.generationFailed` if training data is missing.
  public static func trainCharacterLoRA(
    for character: Character,
    config: TrainingConfig = TrainingConfig(),
    model: VinetasModel = .klein4b,
    progress: ((Int, Int, Float) -> Void)? = nil
  ) async throws -> URL {
    let manager = CharacterManager()
    let characterDir = manager.characterDirectory(slug: character.slug)
    let trainer = CharacterTrainer()

    let outputURL = try await trainer.train(
      character: character,
      config: config,
      model: model.descriptor,
      characterDirectory: characterDir,
      progress: progress
    )

    // Update character manifest with new LoRA metadata
    let loraDir = characterDir.appendingPathComponent("lora", isDirectory: true)
    let version = trainer.nextVersion(slug: character.slug, in: loraDir) - 1
    let relativePath = "lora/\(outputURL.lastPathComponent)"

    var updatedCharacter = character
    updatedCharacter.lora = LoRAMetadata(
      path: relativePath,
      scale: 0.8,
      version: version,
      trainedAt: Date(),
      trainingSteps: config.steps,
      compatibleEngines: [model.descriptor.engineID]
    )
    try manager.saveCharacter(updatedCharacter)

    return outputURL
  }

  // MARK: - Training Data Preparation

  /// Prepare a training dataset for LoRA fine-tuning from a character's reference sheets.
  ///
  /// Scans the character's `references/` directory for generated reference images
  /// (front.png, left.png, right.png, back.png), resizes each to VAE-compatible
  /// dimensions (divisible by 16), and creates matching caption text files in
  /// `training/`. Optionally includes the character's source photos as well.
  ///
  /// - Parameters:
  ///   - character: The character whose training data to prepare.
  ///   - includeSourcePhotos: Whether to include the character's source photos
  ///     in addition to reference sheets. Default: `false`.
  /// - Returns: Array of `TrainingDataPreparer.TrainingPair`, one per processed image.
  /// - Throws: File I/O or image processing errors.
  public static func prepareTrainingData(
    for character: Character,
    includeSourcePhotos: Bool = false
  ) throws -> [TrainingDataPreparer.TrainingPair] {
    let manager = CharacterManager()
    let characterDir = manager.characterDirectory(slug: character.slug)
    let preparer = TrainingDataPreparer()
    return try preparer.prepare(
      for: character,
      includeSourcePhotos: includeSourcePhotos,
      characterDirectory: characterDir
    )
  }
}

// MARK: - Deprecated VinetasModel Enum

/// Available FLUX.2 model variants.
///
/// - Important: Use ``ModelDescriptor`` types directly (e.g., ``VinetasClient/klein4B``,
///   ``VinetasClient/klein9B``). This enum is preserved for backward compatibility.
@available(
  *, deprecated, message: "Use ModelDescriptor types directly (e.g., VinetasClient.klein4B)"
)
public enum VinetasModel: String, Sendable, Codable, CaseIterable {
  case klein4b = "klein4b"
  case klein9b = "klein9b"
  case pixartSigma = "pixart-sigma"

  /// Bridge to ``ModelDescriptor``.
  ///
  /// Converts this legacy enum case to the corresponding concrete ``ModelDescriptor``.
  public var descriptor: any ModelDescriptor {
    switch self {
    case .klein4b:
      Flux2ModelDescriptor.klein4B
    case .klein9b:
      Flux2ModelDescriptor.klein9B
    case .pixartSigma:
      PixArtModelDescriptor.sigmaXL
    }
  }

  /// The HuggingFace repository identifier for this model.
  public var huggingFaceRepo: String {
    switch self {
    case .klein4b:
      "black-forest-labs/FLUX.2-klein-4B"
    case .klein9b:
      "black-forest-labs/FLUX.2-klein-9B"
    case .pixartSigma:
      "PixArt-alpha/PixArt-Sigma-XL-2-1024-MS"
    }
  }

  /// Minimum system memory in GB required to run this model.
  public var minimumMemoryGB: Int {
    switch self {
    case .klein4b:
      16
    case .klein9b:
      24
    case .pixartSigma:
      8
    }
  }

  /// The quantization format used for inference.
  public var quantization: String {
    switch self {
    case .klein4b:
      "int4"
    case .klein9b:
      "qint8"
    case .pixartSigma:
      "int4"
    }
  }

  /// Estimated generation time per image in seconds on M3/M4 Pro.
  public var estimatedSecondsPerImage: Int {
    switch self {
    case .klein4b:
      26
    case .klein9b:
      62
    case .pixartSigma:
      10
    }
  }
}

// MARK: - VerificationReport

/// Report from character verification via pairwise DINOv2 similarity scoring.
///
/// Contains the similarity score for every pair of reference sheet images,
/// whether the character passed the threshold check, and summary statistics.
public struct VerificationReport: Sendable {

  /// Pairwise similarity scores between reference sheet images.
  ///
  /// Each tuple contains the view names (e.g., "front", "left") and their
  /// cosine similarity in the range `[-1, 1]`.
  public let pairs: [(view1: String, view2: String, similarity: Float)]

  /// Whether all pairwise similarities met or exceeded the threshold.
  public let passed: Bool

  /// The minimum cosine similarity threshold used for this verification.
  public let threshold: Float

  /// The mean cosine similarity across all pairs.
  public let averageSimilarity: Float

  public init(
    pairs: [(view1: String, view2: String, similarity: Float)],
    passed: Bool,
    threshold: Float,
    averageSimilarity: Float
  ) {
    self.pairs = pairs
    self.passed = passed
    self.threshold = threshold
    self.averageSimilarity = averageSimilarity
  }
}

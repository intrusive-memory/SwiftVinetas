import CoreGraphics
import Flux2Core
import Foundation

// MARK: - ReferenceView

/// The four canonical turnaround views used in character reference sheets.
///
/// Each view maps to a prompt suffix that steers the FLUX.2 img2img pipeline
/// toward a specific camera angle relative to the subject.
public enum ReferenceView: String, CaseIterable, Sendable {
  case front
  case left
  case right
  case back

  /// Descriptive phrase appended to the generation prompt to control camera angle.
  public var promptSuffix: String {
    switch self {
    case .front:
      "front view, facing camera"
    case .left:
      "left three-quarter view, looking to the side"
    case .right:
      "right three-quarter view, looking to the side"
    case .back:
      "back view, facing away"
    }
  }
}

// MARK: - ReferenceSheetGenerator

/// Generates pencil-sketch turnaround reference sheets from a source photograph.
///
/// For each requested `ReferenceView`, the generator composes a prompt incorporating
/// the character's trigger word and description, then runs the FLUX.2 img2img pipeline
/// against the source photo. Generated images are saved to the character's `references/`
/// subdirectory.
internal struct ReferenceSheetGenerator: Sendable {

  /// The default img2img strength for reference sheet generation.
  ///
  /// A value of 0.65 preserves enough of the source photo's structure to maintain
  /// character likeness while allowing sufficient deviation for the pencil-sketch
  /// style and alternate viewing angles.
  static let defaultStrength: Float = 0.65

  // MARK: - Prompt Composition

  /// Compose the full generation prompt for a given view and character.
  ///
  /// Format: `"pencil sketch, <view suffix>, <trigger word> <description>, clean lines, white background"`
  ///
  /// - Parameters:
  ///   - view: The turnaround angle to render.
  ///   - character: The character whose trigger word and description are injected.
  /// - Returns: The composed prompt string.
  static func composePrompt(
    for view: ReferenceView,
    character: Character
  ) -> String {
    "pencil sketch, \(view.promptSuffix), \(character.triggerWord) \(character.description), clean lines, white background"
  }

  // MARK: - Generation

  /// Generate reference sheet images for a character from a source photograph.
  ///
  /// For each view, the generator:
  /// 1. Composes the pencil-sketch prompt with the character's identity tokens.
  /// 2. Runs img2img against the source photo at the specified strength.
  /// 3. Saves the result as PNG to `characters/<slug>/references/<view>.png`.
  /// 4. Reports progress via callback.
  ///
  /// - Parameters:
  ///   - character: The character to generate reference sheets for.
  ///   - views: The turnaround angles to render.
  ///   - sourceImage: The source photograph to use as the img2img input.
  ///   - strength: How much to deviate from the source (0.0 = identical, 1.0 = fully generated).
  ///   - model: The FLUX.2 model variant to use.
  ///   - progress: Optional callback reporting `(currentView, totalViews)`.
  /// - Returns: Array of generated CGImages, one per requested view.
  /// - Throws: `VinetasError.insufficientMemory`, `VinetasError.generationFailed`.
  static func generate(
    for character: Character,
    views: [ReferenceView],
    sourceImage: CGImage,
    strength: Float = defaultStrength,
    model: VinetasModel = .klein4b,
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [CGImage] {
    guard !views.isEmpty else { return [] }

    // 1. Validate memory
    let memoryOK = VinetasMemory.validate(for: model)
    if !memoryOK {
      throw VinetasError.insufficientMemory(
        required: VinetasMemory.requiredMemoryBytes(for: model),
        available: VinetasMemory.systemMemoryBytes
      )
    }

    // 2. Create pipeline
    let flux2Model: Flux2Model =
      switch model {
      case .klein4b: .klein4B
      case .klein9b: .klein9B
      case .pixartSigma: .klein4B  // Fallback — prefer EngineRouter for dispatch
      }

    let quantization: Flux2QuantizationConfig =
      switch model {
      case .klein4b: .ultraMinimal
      case .klein9b: .balanced
      case .pixartSigma: .ultraMinimal  // Fallback — prefer EngineRouter for dispatch
      }

    let memoryOpt = MemoryOptimizationConfig.recommended(
      forRAMGB: VinetasMemory.systemMemoryGB
    )

    let pipeline = Flux2Pipeline(
      model: flux2Model,
      quantization: quantization,
      memoryOptimization: memoryOpt
    )

    // 3. Load models
    log("Loading models for reference sheet generation (\(model.rawValue))...")
    try await pipeline.loadModels(progressCallback: { downloadProgress, message in
      log("Download: \(Int(downloadProgress * 100))% — \(message)")
    })

    // 4. Generate each view
    var images: [CGImage] = []
    let totalViews = views.count

    // Prepare the references directory
    let manager = CharacterManager()
    let referencesDir = manager.characterDirectory(slug: character.slug)
      .appendingPathComponent("references", isDirectory: true)
    try FileManager.default.createDirectory(
      at: referencesDir,
      withIntermediateDirectories: true
    )

    for (index, view) in views.enumerated() {
      progress?(index + 1, totalViews)

      let prompt = composePrompt(for: view, character: character)
      log("Generating reference \(index + 1)/\(totalViews): \(view.rawValue) — \(prompt)")

      let result: Flux2GenerationResult
      do {
        result = try await pipeline.generateImageToImageWithResult(
          prompt: prompt,
          images: [sourceImage],
          height: 1024,
          width: 1024,
          onProgress: { currentStep, totalSteps in
            log("Reference \(view.rawValue) — Step \(currentStep)/\(totalSteps)")
          }
        )
      } catch {
        throw VinetasError.generationFailed(
          "Reference sheet generation failed for \(view.rawValue) view: \(error.localizedDescription)"
        )
      }

      // Save to references/<view>.png
      let outputURL = referencesDir.appendingPathComponent("\(view.rawValue).png")
      try ImageOutput.writePNG(image: result.image, to: outputURL)
      log("Saved reference: \(outputURL.path)")

      images.append(result.image)
    }

    return images
  }

  // MARK: - Logging

  private static func log(_ message: String) {
    let line = "[SwiftVinetas] \(message)\n"
    if let data = line.data(using: .utf8) {
      FileHandle.standardError.write(data)
    }
  }
}

import CoreGraphics
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
/// the character's trigger word and description, then runs img2img generation via
/// the engine router against the source photo. Generated images are saved to the
/// character's `references/` subdirectory.
internal struct ReferenceSheetGenerator: Sendable {

  /// Legacy img2img strength value, retained only for source compatibility.
  ///
  /// This value has **no effect**. FLUX.2 reference conditioning has no
  /// strength control: the source photo is passed as a conditioning reference,
  /// not as a noised latent starting point, so no "strength" preserves or
  /// discards its structure. The generator never reads this value.
  @available(
    *, deprecated,
    message:
      "FLUX.2 reference conditioning has no strength control; removed in the next minor release."
  )
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
  /// Routes generation through the ``EngineRouter`` — resolves the engine for the
  /// given model descriptor, validates that it accepts one reference image, loads
  /// the model, then generates each view using `imageToImage` mode with the source
  /// photo as the single conditioning reference.
  ///
  /// The generator:
  /// 1. Resolves the engine via `router.engine(for:)`.
  /// 2. Validates the reference count (1) with ``ReferenceValidator`` — an engine
  ///    that accepts no references (e.g. PixArt) fails here, before any model load.
  /// 3. Loads the model via `engine.loadModel(_:progress:)`.
  /// 4. For each view, composes the pencil-sketch prompt with the character's
  ///    identity tokens and generates using
  ///    `GenerationRequest(mode: .imageToImage(references:))`.
  /// 5. Saves each result as PNG to `characters/<slug>/references/<view>.png`.
  /// 6. Reports progress via callback.
  ///
  /// There is no strength parameter: FLUX.2 reference conditioning has no
  /// strength control.
  ///
  /// - Parameters:
  ///   - character: The character to generate reference sheets for.
  ///   - views: The turnaround angles to render.
  ///   - sourceImage: The source photograph used as the conditioning reference.
  ///   - model: The model descriptor to use (default: ``VinetasClient/defaultModel``).
  ///   - router: The engine router to dispatch through (default: the shared client's
  ///     router; injectable for tests).
  ///   - progress: Optional callback reporting `(currentView, totalViews)`.
  /// - Returns: Array of generated CGImages, one per requested view.
  /// - Throws: ``VinetasError/referencesUnsupported(engineID:)`` or
  ///   ``VinetasError/tooManyReferences(model:max:got:)`` before loading when the
  ///   engine/model cannot take a reference; `VinetasError.generationFailed` if a
  ///   view fails to generate.
  static func generate(
    for character: Character,
    views: [ReferenceView],
    sourceImage: CGImage,
    model: any ModelDescriptor = VinetasClient.defaultModel,
    router: EngineRouter = VinetasClient.shared.router,
    progress: ((Int, Int) -> Void)? = nil
  ) async throws -> [CGImage] {
    guard !views.isEmpty else { return [] }

    // 1. Resolve engine (no pre-flight memory gate — see VinetasPipeline)
    let engine = try await router.engine(for: model)

    // 2. Validate the single source-photo reference before any model load.
    try ReferenceValidator.validate(referenceCount: 1, engine: engine, model: model)

    // 3. Load model
    log("Loading models for reference sheet generation (\(model.displayName))...")
    try await engine.loadModel(
      model,
      progress: { loadProgress in
        log("Load: \(Int(loadProgress.fraction * 100))% — \(loadProgress.phase)")
      })

    // 4. Prepare the references directory
    let manager = CharacterManager()
    let referencesDir = manager.characterDirectory(slug: character.slug)
      .appendingPathComponent("references", isDirectory: true)
    try FileManager.default.createDirectory(
      at: referencesDir,
      withIntermediateDirectories: true
    )

    // 5. Generate each view
    var images: [CGImage] = []
    let totalViews = views.count

    for (index, view) in views.enumerated() {
      progress?(index + 1, totalViews)

      let prompt = composePrompt(for: view, character: character)
      log("Generating reference \(index + 1)/\(totalViews): \(view.rawValue) — \(prompt)")

      let request = GenerationRequest(
        prompt: prompt,
        steps: model.defaultSteps,
        guidanceScale: model.defaultGuidance,
        width: 1024,
        height: 1024,
        mode: .imageToImage(references: [sourceImage])
      )

      let result: GenerationResult
      do {
        result = try await engine.generate(request: request) { currentStep, totalSteps, _ in
          log("Reference \(view.rawValue) — Step \(currentStep)/\(totalSteps)")
        }
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

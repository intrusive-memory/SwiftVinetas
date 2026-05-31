import CoreGraphics
import Flux2Core
import Foundation
import SwiftAcervo
import Tuberia
import os.lock

// MARK: - VinetasDownloadProgress

/// Progress information for model downloads.
public struct VinetasDownloadProgress: Sendable {
  /// Overall progress from 0.0 to 1.0.
  public let overallProgress: Double
  /// Human-readable status message.
  public let message: String

  public init(overallProgress: Double, message: String) {
    self.overallProgress = overallProgress
    self.message = message
  }
}

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
  public static let version = "0.15.3-dev"

  /// Configures a CDN base URL for model downloads.
  ///
  /// When set, the downloader fetches models from the CDN instead of
  /// HuggingFace. Falls back to HuggingFace if the CDN download fails.
  ///
  /// Call this once at app startup before any download operations.
  ///
  /// - Parameter baseURL: The CDN base URL (e.g. `https://cdn.example.com`).
  public static func configureCDN(baseURL: URL) {
    ModelRegistry.cdnBaseURL = baseURL
  }

  /// Telemetry reporter storage, guarded by an unfair lock so the mutable
  /// reporter can live on a `Sendable` class without making the class an actor.
  /// Per REQUIREMENTS §5.1: the lock is touched only at run boundaries
  /// (set/get on `setTelemetry` and emission sites), satisfying hot-path
  /// discipline.
  private let _telemetryLock = OSAllocatedUnfairLock<(any VinetasTelemetryReporter)?>(
    initialState: nil
  )

  // MARK: - Telemetry propagation
  //
  // OQ-3 (REQUIREMENTS §5.5) resolution: `ImageClassifier` and `FeatureExtractor`
  // are **long-lived process-wide singletons**, NOT instance-held properties on
  // `VinetasClient`. Evidence:
  //   - Sources/SwiftVinetas/Understanding/ImageClassifier.swift:27
  //     `public static let shared = ImageClassifier()` (actor singleton, private init).
  //   - Sources/SwiftVinetas/Understanding/FeatureExtractor.swift:27
  //     `public static let shared = FeatureExtractor()` (actor singleton, private init).
  //   - Sources/SwiftVinetas/Vinetas.swift:558, 573, 588, 598, 614–615, 672
  //     every call site uses `.shared`; nothing constructs them per-call.
  //
  // Because they are singletons and not owned by `VinetasClient`, propagation
  // from `VinetasClient.setTelemetry` reaches them by `await`ing
  // `ImageClassifier.shared.setTelemetry(reporter)` and
  // `FeatureExtractor.shared.setTelemetry(reporter)` directly inside
  // `setTelemetry(_:)`. The router path handles engines; this comment block
  // documents the parallel non-router path for the two image-understanding
  // actors so that Sortie 5 inherits an obvious propagation contract.

  /// Install (or clear) the process-wide telemetry reporter.
  ///
  /// Stores the reporter under the unfair lock, propagates to the
  /// ``EngineRouter`` (which fans out to every registered engine), and also
  /// propagates to the long-lived ``ImageClassifier`` and ``FeatureExtractor``
  /// singletons per the OQ-3 resolution above. Pass `nil` to disable
  /// telemetry; subsequent emissions become no-ops once stored.
  ///
  /// - Parameter reporter: The reporter to install, or `nil` to clear.
  public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
    _telemetryLock.withLock { $0 = reporter }
    await router.setTelemetry(reporter)
    await ImageClassifier.shared.setTelemetry(reporter)
    await FeatureExtractor.shared.setTelemetry(reporter)
  }

  /// The current telemetry reporter, if any. Internal accessor used by
  /// emission sites in this module.
  internal func currentTelemetry() -> (any VinetasTelemetryReporter)? {
    _telemetryLock.withLock { $0 }
  }

  /// Default initializer that registers engines based on runtime memory detection.
  ///
  /// ``PixArtEngine`` is always registered (requires 8 GB, matches all iPads and most Macs).
  /// ``Flux2Engine`` is registered only when the device has 16+ GB of memory (macOS high-memory
  /// configurations). This eliminates compile-time platform gates in favour of runtime checks,
  /// so both engines compile on every platform and only registration is conditional.
  public init() {
    let totalMemoryGB = DeviceCapability.current.totalMemoryGB
    let deviceArch = DeviceCapability.current.chipGeneration.rawValue
    var engines: [any ImageGenerationEngine] = [PixArtEngine()]
    // Telemetry: emit registration outcomes. PixArt is always registered.
    let pixartRegistered = true
    let flux2Eligible = totalMemoryGB >= 16
    if flux2Eligible {
      engines.append(Flux2Engine())
    }
    self.router = EngineRouter(engines: engines)

    // Emit telemetry events for client init + engine registration. The reporter
    // is nil here (setTelemetry has not yet been called) so these capture calls
    // are no-ops on the default path; they fire only if a reporter is installed
    // before this `init()` completes through a re-entrant call (not possible in
    // practice, but the code path is correct). The events are queued as fire-
    // and-forget Tasks so a sync `init` can emit async events without blocking.
    let registeredIDs = engines.map { $0.engineID }
    if let reporter = self._telemetryLock.withLock({ $0 }) {
      Task { [reporter] in
        if pixartRegistered {
          await reporter.capture(
            .engineRegistered(engineID: "pixart-sigma", reason: "always-registered"))
        }
        if flux2Eligible {
          await reporter.capture(
            .engineRegistered(
              engineID: "flux2",
              reason: "memory>=16GB (have \(totalMemoryGB)GB)"))
        } else {
          await reporter.capture(
            .engineSkipped(
              engineID: "flux2",
              reason: "memory<16GB (have \(totalMemoryGB)GB)"))
        }
        await reporter.capture(
          .clientInitialized(
            version: VinetasClient.version,
            registeredEngines: registeredIDs,
            deviceMemoryGB: totalMemoryGB,
            deviceArch: deviceArch))
      }
    }
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
    // MARK: - generationEnd capture
    //
    // OQ-6 resolution: we use the captured-mutable-var + `defer` idiom from
    // REQUIREMENTS §6 / OQ-6. Three mutables (`success`, `outputDims`,
    // `actualSeed`) plus a clock are captured before any throwing work; the
    // outcome is mutated on the success path; the `defer` reads the final
    // values and fires `generationEnd` once per return path (success OR
    // failure). The Task wrapper makes the async `capture` call legal from
    // the synchronous `defer` body — fire-and-forget is acceptable per
    // REQUIREMENTS §6 / OQ-2.
    //
    // The same shape is reused at the other three entry points
    // (`generateSequence`, `generate(prompt:character:...)`, `preview`).
    let reporter = currentTelemetry()
    let endClock = ContinuousClock()
    let endStart = endClock.now
    var success = false
    var outputDims: [Int]? = nil
    var actualSeed: UInt64? = nil
    var endEngineID = ""
    let endModelID = model.id
    defer {
      let duration =
        Double((endClock.now - endStart).components.seconds)
        + Double((endClock.now - endStart).components.attoseconds) / 1e18
      let capturedEngineID = endEngineID
      let capturedSuccess = success
      let capturedDims = outputDims
      let capturedSeed = actualSeed
      let capturedModelID = endModelID
      Task { [reporter] in
        await reporter?.capture(
          .generationEnd(
            engineID: capturedEngineID,
            modelID: capturedModelID,
            success: capturedSuccess,
            durationSeconds: duration,
            outputDims: capturedDims,
            actualSeed: capturedSeed))
      }
    }

    guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else {
      await reporter?.capture(
        .errorThrown(
          phase: .generationFailed,
          errorDescription: "generationFailed: Prompt must not be empty"))
      throw VinetasError.generationFailed("Prompt must not be empty")
    }
    let effectiveStyle = style ?? StyleConfig()
    let composedPrompt = composePrompt(panelPrompt: prompt, style: effectiveStyle)
    let request = buildRequest(
      prompt: composedPrompt,
      style: effectiveStyle,
      mode: .textToImage
    )
    // Emit generationStart BEFORE routing so the ordering invariant holds:
    //   generationStart → engineSelected → … → generationEnd
    // model.engineID is known from the descriptor; the router confirms it next.
    await reporter?.capture(
      .generationStart(
        prompt: composedPrompt,
        promptLength: composedPrompt.count,
        engineID: model.engineID,
        modelID: model.id,
        steps: request.steps,
        guidanceScale: Double(request.guidanceScale),
        seed: request.seed ?? 0,
        width: request.width,
        height: request.height,
        mode: .textToImage,
        referenceImageCount: 0,
        loraAttached: false,
        loraScale: nil,
        upsamplePromptRequested: false,
        interpretImageCount: 0))
    let engine = try await router.engine(for: model)
    endEngineID = engine.engineID
    // Emit engineSelected after the router confirms the route (success path only).
    // engineNotFound remains in EngineRouter for the failure path.
    await reporter?.capture(
      .engineSelected(
        engineID: engine.engineID,
        modelID: model.id,
        requestedFeature: nil,
        fallbackUsed: false))
    try await engine.loadModel(model, progress: { _ in })
    let result = try await engine.generate(request: request, stepProgress: nil)
    success = true
    actualSeed = result.seed
    outputDims = [result.image.width, result.image.height]
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
    // generationEnd capture — see canonical MARK in generate(prompt:style:model:)
    let reporter = currentTelemetry()
    let endClock = ContinuousClock()
    let endStart = endClock.now
    var success = false
    var outputDims: [Int]? = nil
    var actualSeed: UInt64? = nil
    var endEngineID = ""
    let endModelID = model.id
    defer {
      let duration =
        Double((endClock.now - endStart).components.seconds)
        + Double((endClock.now - endStart).components.attoseconds) / 1e18
      let capturedEngineID = endEngineID
      let capturedSuccess = success
      let capturedDims = outputDims
      let capturedSeed = actualSeed
      let capturedModelID = endModelID
      Task { [reporter] in
        await reporter?.capture(
          .generationEnd(
            engineID: capturedEngineID,
            modelID: capturedModelID,
            success: capturedSuccess,
            durationSeconds: duration,
            outputDims: capturedDims,
            actualSeed: capturedSeed))
      }
    }

    guard !prompts.isEmpty else {
      success = true
      return []
    }

    let effectiveStyle = style ?? StyleConfig()
    let useImageToImage = referenceImages.map { !$0.isEmpty } ?? false
    let totalPanels = prompts.count
    var images: [CGImage] = []

    // Emit a single generationStart for the whole sequence BEFORE routing so
    // the ordering invariant holds: generationStart → engineSelected → … → generationEnd.
    // model.engineID is known from the descriptor; the router confirms it next.
    let firstComposed =
      prompts.first.map { composePrompt(panelPrompt: $0, style: effectiveStyle) } ?? ""
    let firstRequest = buildRequest(
      prompt: firstComposed,
      style: effectiveStyle,
      mode: useImageToImage
        ? .imageToImage(references: referenceImages ?? [])
        : .textToImage
    )
    await reporter?.capture(
      .generationStart(
        prompt: firstComposed,
        promptLength: firstComposed.count,
        engineID: model.engineID,
        modelID: model.id,
        steps: firstRequest.steps,
        guidanceScale: Double(firstRequest.guidanceScale),
        seed: firstRequest.seed ?? 0,
        width: firstRequest.width,
        height: firstRequest.height,
        mode: useImageToImage ? .imageToImage : .textToImage,
        referenceImageCount: referenceImages?.count ?? 0,
        loraAttached: false,
        loraScale: nil,
        upsamplePromptRequested: false,
        interpretImageCount: 0))
    let engine = try await router.engine(for: model)
    endEngineID = engine.engineID
    // Emit engineSelected after the router confirms the route (success path only).
    await reporter?.capture(
      .engineSelected(
        engineID: engine.engineID,
        modelID: model.id,
        requestedFeature: nil,
        fallbackUsed: false))
    try await engine.loadModel(model, progress: { _ in })

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
      actualSeed = result.seed
      outputDims = [result.image.width, result.image.height]
    }

    success = true
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
    // generationEnd capture — see canonical MARK in generate(prompt:style:model:)
    let reporter = currentTelemetry()
    let endClock = ContinuousClock()
    let endStart = endClock.now
    var success = false
    var outputDims: [Int]? = nil
    var actualSeed: UInt64? = nil
    var endEngineID = ""
    let endModelID = model.id
    defer {
      let duration =
        Double((endClock.now - endStart).components.seconds)
        + Double((endClock.now - endStart).components.attoseconds) / 1e18
      let capturedEngineID = endEngineID
      let capturedSuccess = success
      let capturedDims = outputDims
      let capturedSeed = actualSeed
      let capturedModelID = endModelID
      Task { [reporter] in
        await reporter?.capture(
          .generationEnd(
            engineID: capturedEngineID,
            modelID: capturedModelID,
            success: capturedSuccess,
            durationSeconds: duration,
            outputDims: capturedDims,
            actualSeed: capturedSeed))
      }
    }

    let effectiveStyle = style ?? StyleConfig()

    // Compose prompt: trigger word + style + panel prompt (known before routing).
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
    // Emit generationStart BEFORE routing so the ordering invariant holds:
    //   generationStart → engineSelected → … → generationEnd
    // LoRA presence is reported from the character metadata (intent), not post-load.
    let loraIntended = character.lora != nil
    let loraScaleIntended = character.lora.map { Double($0.scale) }
    await reporter?.capture(
      .generationStart(
        prompt: composedPrompt,
        promptLength: composedPrompt.count,
        engineID: model.engineID,
        modelID: model.id,
        steps: request.steps,
        guidanceScale: Double(request.guidanceScale),
        seed: request.seed ?? 0,
        width: request.width,
        height: request.height,
        mode: .textToImage,
        referenceImageCount: 0,
        loraAttached: loraIntended,
        loraScale: loraScaleIntended,
        upsamplePromptRequested: false,
        interpretImageCount: 0))
    let engine = try await router.engine(for: model)
    endEngineID = engine.engineID
    // Emit engineSelected after the router confirms the route (success path only).
    await reporter?.capture(
      .engineSelected(
        engineID: engine.engineID,
        modelID: model.id,
        requestedFeature: nil,
        fallbackUsed: false))
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

    let result = try await engine.generate(request: request, stepProgress: nil)

    // Unload LoRA to prevent bleeding into subsequent generations
    if loraLoaded {
      await engine.unloadLoRA()
    }

    success = true
    actualSeed = result.seed
    outputDims = [result.image.width, result.image.height]
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
    // generationEnd capture — see canonical MARK in generate(prompt:style:model:)
    let previewModel = Flux2ModelDescriptor.klein4B
    let reporter = currentTelemetry()
    let endClock = ContinuousClock()
    let endStart = endClock.now
    var success = false
    var outputDims: [Int]? = nil
    var actualSeed: UInt64? = nil
    var endEngineID = ""
    let endModelID = previewModel.id
    defer {
      let duration =
        Double((endClock.now - endStart).components.seconds)
        + Double((endClock.now - endStart).components.attoseconds) / 1e18
      let capturedEngineID = endEngineID
      let capturedSuccess = success
      let capturedDims = outputDims
      let capturedSeed = actualSeed
      let capturedModelID = endModelID
      Task { [reporter] in
        await reporter?.capture(
          .generationEnd(
            engineID: capturedEngineID,
            modelID: capturedModelID,
            success: capturedSuccess,
            durationSeconds: duration,
            outputDims: capturedDims,
            actualSeed: capturedSeed))
      }
    }

    let request = GenerationRequest(
      prompt: prompt,
      steps: 4,
      guidanceScale: previewModel.defaultGuidance,
      width: 512,
      height: 512,
      mode: .textToImage
    )
    // Emit generationStart BEFORE routing so the ordering invariant holds:
    //   generationStart → engineSelected → … → generationEnd
    // preview always targets the flux2 engine; previewModel.engineID confirms this.
    await reporter?.capture(
      .generationStart(
        prompt: prompt,
        promptLength: prompt.count,
        engineID: previewModel.engineID,
        modelID: previewModel.id,
        steps: request.steps,
        guidanceScale: Double(request.guidanceScale),
        seed: request.seed ?? 0,
        width: request.width,
        height: request.height,
        mode: .preview,
        referenceImageCount: 0,
        loraAttached: false,
        loraScale: nil,
        upsamplePromptRequested: false,
        interpretImageCount: 0))
    let engine = try await router.engine(forEngineID: "flux2")
    endEngineID = engine.engineID
    // Emit engineSelected after the router confirms the route (success path only).
    // preview() routes by engineID directly, not by model descriptor, so we use
    // previewModel.id for the modelID field.
    await reporter?.capture(
      .engineSelected(
        engineID: engine.engineID,
        modelID: previewModel.id,
        requestedFeature: nil,
        fallbackUsed: false))
    try await engine.loadModel(previewModel, progress: { _ in })
    let result = try await engine.generate(request: request, stepProgress: nil)
    success = true
    actualSeed = result.seed
    outputDims = [result.image.width, result.image.height]
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

  /// Check whether a model is available locally by its identifier string.
  ///
  /// This is the **canonical, instrumented** availability check. Mirrors the
  /// VoxAlta `VoxAltaModelManager.isModelInAcervo(_:)` pattern. Defers to
  /// ``SwiftAcervo/Acervo/availability(_:)`` and collapses its three-state
  /// result to `Bool` (`.available` → `true`, everything else → `false`).
  /// Emits a single `modelAvailabilityChecked` telemetry event with
  /// `modelId` and the resolved availability.
  ///
  /// Consumers that need to distinguish "downloading…" from "absent" should
  /// use ``availability(_:)`` instead.
  ///
  /// - Parameter modelId: The model identifier string in HuggingFace
  ///   `"org/repo"` form (e.g. `"black-forest-labs/FLUX.2-klein-4B"`).
  /// - Returns: `true` if all manifest files are on disk at their recorded
  ///   sizes; `false` if missing or a download is in flight.
  public func isModelAvailable(_ modelId: String) async -> Bool {
    let available = await Acervo.availability(modelId) == .available
    await recordModelAvailability(modelID: modelId, available: available)
    return available
  }

  /// Four-state availability passthrough for UI consumers (e.g. Vinetas's
  /// `ModelManagementService`).
  ///
  /// Returns the underlying `ModelAvailability` directly so callers can
  /// distinguish `.available`, `.downloading(progress:)`,
  /// `.partial(missing:)`, and `.notAvailable`. This is the canonical
  /// UI-facing surface; the `Bool`-returning ``isModelAvailable(_:)``
  /// collapses these states for code paths that only need a binary answer
  /// (note: `.partial` collapses to `false` there — repair-vs-download UI
  /// must read `availability(_:)` directly).
  ///
  /// - Parameter modelId: The model identifier string in HuggingFace
  ///   `"org/repo"` form.
  ///
  /// - Important: This only works for models that map 1:1 to a single
  ///   HuggingFace repository. For multi-component models (e.g.
  ///   ``PixArtModelDescriptor/sigmaXL``, ``Flux2ModelDescriptor``) use
  ///   ``availability(model:)`` which routes through the engine and
  ///   aggregates per-component availability.
  public func availability(_ modelId: String) async -> ModelAvailability {
    await Acervo.availability(modelId)
  }

  /// Descriptor-keyed four-state availability for multi-component models.
  ///
  /// Resolves the engine for `model` and delegates to
  /// ``ImageGenerationEngine/availability(_:)``, which aggregates per-component
  /// Acervo state. This is the canonical availability API for UI consumers
  /// because it works for both single-repo and multi-component models.
  ///
  /// - Parameter model: The model descriptor to query.
  /// - Returns: ``ModelAvailability`` (`.available`, `.downloading(progress:)`,
  ///   `.partial(missing:)`, or `.notAvailable`). Returns `.notAvailable`
  ///   if no engine is registered for the model.
  public func availability(model: any ModelDescriptor) async -> ModelAvailability {
    guard let engine = try? await router.engine(for: model) else {
      return .notAvailable
    }
    return await engine.availability(model)
  }

  /// Canonical telemetry emission site for `modelAvailabilityChecked`.
  ///
  /// Centralizes the capture so deprecated descriptor-form wrappers can share
  /// a single emission location with the new ``isModelAvailable(_:)`` canonical.
  /// Per REQUIREMENTS §6 there is exactly one emission of this event, and this
  /// helper is it.
  internal func recordModelAvailability(modelID: String, available: Bool) async {
    await currentTelemetry()?.capture(
      .modelAvailabilityChecked(modelID: modelID, available: available))
  }

  /// Check whether a model is available on disk, via the engine router.
  ///
  /// - Parameter model: The model descriptor to check.
  /// - Returns: `true` if the model's weights are downloaded and ready.
  @available(
    *, deprecated, renamed: "isModelAvailable(_:)",
    message:
      "Pass the model's modelId string instead — e.g. isModelAvailable(model.id). The descriptor form will be removed in a future release."
  )
  public func isAvailable(_ model: any ModelDescriptor) async throws -> Bool {
    // Preserve engine-routed behavior on the deprecated path so callers that
    // pass a typed descriptor (whose `id` is a slug, not an HF repo string)
    // get the engine's correct answer. Telemetry still funnels through the
    // single canonical emission site (`recordModelAvailability`).
    let engine = try await router.engine(for: model)
    let available = await engine.isAvailable(model)
    await recordModelAvailability(modelID: model.id, available: available)
    return available
  }

  /// Delete a model's weights from local storage, via the engine router.
  ///
  /// - Parameter model: The model descriptor to delete.
  public func delete(_ model: any ModelDescriptor) async throws {
    let engine = try await router.engine(for: model)
    try await engine.delete(model)
    await currentTelemetry()?.capture(.modelDeleted(modelID: model.id))
  }

  /// List all known models across all registered engines with availability status.
  ///
  /// - Returns: An array of ``VinetasModelInfo``, one per known model.
  public func listModels() async -> [VinetasModelInfo] {
    let models = await router.allModels
    var infos: [VinetasModelInfo] = []
    for model in models {
      let downloaded: Bool
      let size: Int64
      if let engine = try? await router.engine(for: model) {
        downloaded = await engine.isAvailable(model)
        size = await engine.diskSize(of: model) ?? 0
      } else {
        downloaded = false
        size = 0
      }
      infos.append(
        VinetasModelInfo(
          name: model.displayName,
          size: size,
          downloadDate: nil,
          isDownloaded: downloaded
        ))
    }
    return infos
  }

  /// Validate whether the system has sufficient memory for a model.
  ///
  /// Delegates to `engine.validateMemory(for:)`.
  ///
  /// - Parameter model: The model descriptor to validate.
  /// - Returns: A ``MemoryValidation`` result.
  public func validateMemory(for model: any ModelDescriptor) async throws -> MemoryValidation {
    let engine = try await router.engine(for: model)
    let reporter = currentTelemetry()
    let availableMB = Double(VinetasMemory.systemMemoryBytes) / 1_048_576.0
    let requiredMB = Double(model.minimumMemoryGB) * 1024.0
    await reporter?.capture(
      .memoryValidationStart(
        modelID: model.id,
        engineID: engine.engineID,
        estimatedRequiredMB: requiredMB,
        availableMB: availableMB))
    let result = engine.validateMemory(for: model)
    let verdict: VinetasTelemetryEvent.MemoryVerdict
    switch result {
    case .ok: verdict = .sufficient
    case .warning: verdict = .warningMarginal
    case .insufficient: verdict = .insufficient
    }
    await reporter?.capture(
      .memoryValidationResult(
        modelID: model.id,
        engineID: engine.engineID,
        verdict: verdict,
        requiredMB: requiredMB,
        availableMB: availableMB))
    return result
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

  /// The default model for generation: FLUX.2 Klein 4B.
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
  public static let version = "0.15.3-dev"

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
      await VinetasClient.shared.currentTelemetry()?.capture(
        .errorThrown(
          phase: .other,
          errorDescription:
            "generationFailed: No references directory for character '\(character.name)'."))
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
      await VinetasClient.shared.currentTelemetry()?.capture(
        .errorThrown(
          phase: .other,
          errorDescription:
            "generationFailed: need >=2 reference images, found \(pngFiles.count)"))
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
      await VinetasClient.shared.currentTelemetry()?.capture(
        .errorThrown(
          phase: .memoryValidation,
          errorDescription:
            "insufficientMemory(required: \(required), available: \(available))"))
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
      await VinetasClient.shared.currentTelemetry()?.capture(
        .errorThrown(
          phase: .other,
          errorDescription:
            "generationFailed: Character '\(character.name)' has no source photos."))
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
      await VinetasClient.shared.currentTelemetry()?.capture(
        .errorThrown(
          phase: .other,
          errorDescription:
            "generationFailed: Could not load source photo at \(photoURL.path)"))
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
  public var repoId: String {
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

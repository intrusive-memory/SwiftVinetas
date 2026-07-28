import Foundation
import PixArtBackbone
import SwiftAcervo
import Tuberia
import TuberiaCatalog

// MARK: - PixArtModelDescriptor

/// Describes PixArt-Sigma models available through ``PixArtEngine``.
public struct PixArtModelDescriptor: ModelDescriptor {

  public let id: String
  public let displayName: String
  public let engineID: String
  public let license: ModelLicense
  public let minimumMemoryGB: Int
  public let approximateDownloadSize: String
  public let defaultSteps: Int
  public let defaultGuidance: Float
  public let supportedAspectRatios: [AspectRatio]

  /// Acervo component IDs for this model's downloadable weights.
  ///
  /// Sourced from ``PixArtRecipe/allComponentIds``:
  /// - "t5-xxl-encoder-int4" — T5-XXL text encoder (~1.2 GB int4)
  /// - "pixart-sigma-xl-dit-int4" — PixArt-Sigma XL DiT backbone (~300 MB int4)
  /// - "sdxl-vae-decoder-fp16" — SDXL VAE decoder (~160 MB fp16)
  public let componentIds: [String]

  /// PixArt-Sigma XL-2-1024.
  ///
  /// - ID: pixart-sigma-xl
  /// - Engine: pixart-sigma
  /// - License: Apache 2.0
  /// - Memory: 8 GB minimum (int4 transformer + int4 T5 + SDXL VAE)
  /// - Download: ~3.6 GB
  /// - Steps: 20 (default)
  /// - Guidance: 4.5 (default)
  public static let sigmaXL = PixArtModelDescriptor(
    id: "pixart-sigma-xl",
    displayName: "PixArt-Sigma XL",
    engineID: "pixart-sigma",
    license: .apache2,
    minimumMemoryGB: 8,
    approximateDownloadSize: "~3.6 GB",
    defaultSteps: 20,
    defaultGuidance: 4.5,
    supportedAspectRatios: AspectRatio.allCases,
    componentIds: PixArtRecipe().allComponentIds
  )
}

// MARK: - PixArtPipeline Type Alias

/// The concrete DiffusionPipeline type for PixArt-Sigma.
///
/// Assembled from PixArtRecipe's associated types:
///   T5XXLEncoder → DPMSolverScheduler → PixArtDiT → SDXLVAEDecoder → ImageRenderer
private typealias PixArtPipeline = DiffusionPipeline<
  T5XXLEncoder,
  DPMSolverScheduler,
  PixArtDiT,
  SDXLVAEDecoder,
  ImageRenderer
>

// MARK: - PixArtEngine

/// An ``ImageGenerationEngine`` that wraps the PixArt-Sigma diffusion pipeline.
///
/// Assembles a ``DiffusionPipeline`` from ``PixArtRecipe`` and delegates all
/// lifecycle, generation, and LoRA operations to it. Download and availability
/// queries use Acervo component IDs from ``PixArtModelDescriptor/componentIds``.
///
/// Component registration (``PixArtComponents/registered``) is triggered during
/// `loadModel` to ensure weights are discoverable before loading begins.
public actor PixArtEngine: ImageGenerationEngine {

  // MARK: - Identity

  public let engineID = "pixart-sigma"

  // MARK: - Model Catalog

  public nonisolated var supportedModels: [any ModelDescriptor] {
    [PixArtModelDescriptor.sigmaXL]
  }

  // MARK: - Internal State

  /// The assembled DiffusionPipeline, present only when a model is loaded.
  private var pipeline: PixArtPipeline?

  /// The model descriptor currently loaded into the pipeline.
  private var loadedModelID: String?

  /// The LoRA config currently active, if any.
  private var activeLoRAConfig: LoRAConfig?

  /// Prevents actor reentrancy during async generation.
  ///
  /// Swift actors allow reentrancy at `await` suspension points. Without this
  /// guard, two concurrent callers can both enter `generate` and run the MLX
  /// pipeline simultaneously. MLX uses a shared global Metal context and is not
  /// safe for concurrent graph execution — concurrent calls corrupt tensor shapes.
  private var isGenerating = false

  /// Vinetas-scope telemetry reporter, propagated from
  /// ``VinetasClient/setTelemetry(_:)`` via ``EngineRouter``. Stored only —
  /// per REQUIREMENTS §5.3 this override does NOT bridge `PixArtTelemetryEvent`
  /// onto the Vinetas surface.
  private var telemetry: (any VinetasTelemetryReporter)?

  /// Per-component integrity checker invoked in `loadModel` before pipeline
  /// assembly and weight loading (B2 · C4 · R2.2), mirroring ``Flux2Engine``.
  ///
  /// Production default wraps `Acervo.availability(_:verifyHashes:true)`, which is
  /// **marker-aware**: a valid `.acervo-verified.json` marker short-circuits to
  /// `.available` with no SHA-256 hashing; otherwise a full SHA-256 audit runs and
  /// the marker is written on success. A `.partial` verdict means on-disk weights
  /// do not match the CDN manifest (corrupted or incomplete download), and
  /// `loadModel` throws `.modelIncomplete`.
  ///
  /// Unit tests supply a stub via `init(integrityChecker:)` to force specific
  /// verdicts without filesystem or CDN access.
  private var integrityChecker: @Sendable (String) async -> ModelAvailability

  // MARK: - Init

  /// Creates a `PixArtEngine` with the production marker-aware integrity checker.
  ///
  /// The default checker calls `Acervo.availability(_:verifyHashes:true)`: when a
  /// valid `.acervo-verified.json` marker is present it returns `.available` without
  /// re-hashing; when no marker or a stale marker exists it performs a full SHA-256
  /// audit and writes the marker on success.
  public init() {
    self.integrityChecker = { repoId in
      await Acervo.availability(repoId, verifyHashes: true)
    }
  }

  /// Creates a `PixArtEngine` with an injected integrity checker (test seam).
  ///
  /// - Parameter integrityChecker: A `@Sendable (String) async -> ModelAvailability`
  ///   closure. The production default uses `Acervo.availability(_:verifyHashes:true)`
  ///   (marker-aware); inject a stub in unit tests to force specific availability
  ///   verdicts without filesystem or CDN access.
  init(integrityChecker: @escaping @Sendable (String) async -> ModelAvailability) {
    self.integrityChecker = integrityChecker
  }

  // MARK: - Telemetry

  public func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
    self.telemetry = reporter
  }

  // MARK: - Capabilities

  public nonisolated func supports(_ feature: EngineFeature) -> Bool {
    switch feature {
    case .textToImage:
      return true
    case .loraInference:
      return true
    case .imageToImage, .loraTraining, .promptUpsampling:
      return false
    }
  }

  // MARK: - Lifecycle

  public func loadModel(
    _ model: any ModelDescriptor,
    progress: @escaping @Sendable (LoadProgress) -> Void
  ) async throws {
    guard model.engineID == engineID || model.id == PixArtModelDescriptor.sigmaXL.id else {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelNotSupported,
          errorDescription:
            "modelNotSupported(modelID: \(model.id), engineID: \(engineID))"))
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }

    // If the same model is already loaded, skip
    if loadedModelID == model.id, pipeline != nil {
      progress(LoadProgress(phase: "Already loaded", fraction: 1.0))
      return
    }

    // Unload any existing pipeline first
    await unloadModel()

    // Ensure PixArt components are registered with CatalogRegistration
    _ = PixArtComponents.registered

    // Bridge CatalogRegistration → ComponentRegistry so AcervoManager.withModelAccess
    // can resolve short component IDs (e.g. "t5-xxl-encoder-int4") to their repo paths.
    // WeightLoader calls withModelAccess(componentId) with the short ID; the updated
    // withModelAccess fallback looks up ComponentRegistry to get the repoId.
    let catalogRegistry = CatalogRegistration.shared
    for componentId in PixArtRecipe().allComponentIds {
      // Only register components not already in the registry (e.g. those registered
      // by CatalogRegistration/PixArtComponents with correct type/memory values).
      // Re-registering with a different descriptor triggers a SwiftAcervo warning.
      guard Acervo.component(componentId) == nil,
        let catalogDescriptor = catalogRegistry.descriptor(for: componentId)
      else { continue }
      // Un-hydrated init: omit `files:` so the CDN manifest hydrates the file list.
      // TODO: source `type` from catalogDescriptor if it exposes one (R3.1).
      let descriptor = SwiftAcervo.ComponentDescriptor(
        id: catalogDescriptor.id,
        type: .backbone,
        displayName: catalogDescriptor.id,
        repoId: catalogDescriptor.repoId,
        minimumMemoryBytes: 0
      )
      Acervo.register(descriptor)
    }

    // Fail-fast integrity guard — mirrors Flux2Engine's checkpoint (B2 · C4 · R2.2).
    //
    // Before assembling the pipeline or loading any weights, run the marker-aware
    // integrity checker for each required component repo. A `.partial` verdict means
    // on-disk weights do not match the CDN manifest (corrupted or incomplete
    // download); surface a clear `.modelIncomplete` error here instead of letting the
    // MLX deep loader emit a cryptic shard-missing message.
    //
    // Only `.partial` (downloaded-but-corrupt) throws here — `.notAvailable`
    // (not-yet-downloaded) is the caller's responsibility to resolve before
    // `loadModel`, matching the Flux2 contract. Components are deduped by repoId so a
    // shared model directory is hashed once; a component whose descriptor can't be
    // resolved is skipped (re-downloading wouldn't fix a registration anomaly).
    //
    // The checker defaults to `Acervo.availability(_:verifyHashes:true)` (marker-
    // aware). Unit tests inject a stub via `init(integrityChecker:)`.
    progress(LoadProgress(phase: "Verifying model integrity", fraction: 0.0))
    let integrityRegistry = CatalogRegistration.shared
    var verifiedRepoIds = Set<String>()
    var incompleteComponents: [String] = []
    for componentId in model.componentIds {
      guard let componentDescriptor = integrityRegistry.descriptor(for: componentId),
        verifiedRepoIds.insert(componentDescriptor.repoId).inserted
      else { continue }
      let result = await integrityChecker(componentDescriptor.repoId)
      if case .partial = result {
        incompleteComponents.append(componentDescriptor.repoId)
      }
    }
    if !incompleteComponents.isEmpty {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelLoad,
          errorDescription:
            "modelIncomplete: \(model.id) — components: \(incompleteComponents.joined(separator: ", "))"
        ))
      throw VinetasError.modelIncomplete(
        modelID: model.id,
        components: incompleteComponents
      )
    }

    progress(LoadProgress(phase: "Assembling pipeline", fraction: 0.0))

    await telemetry?.capture(.modelLoadStart(modelID: model.id, engineID: engineID))
    let loadClock = ContinuousClock()
    let loadStart = loadClock.now

    let newPipeline: PixArtPipeline
    do {
      newPipeline = try PixArtPipeline(recipe: PixArtRecipe())
    } catch {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelLoad,
          errorDescription:
            "generationFailed: Failed to assemble PixArt pipeline: \(error.localizedDescription)"))
      throw VinetasError.generationFailed(
        "Failed to assemble PixArt pipeline: \(error.localizedDescription)"
      )
    }

    progress(LoadProgress(phase: "Loading model weights", fraction: 0.1))

    // Configure MLX memory budget for the current process before loading
    VinetasMemory.configureMLXBudgetForCurrentProcess()

    do {
      try await newPipeline.loadModels { fraction, component in
        let mapped = 0.1 + fraction * 0.9
        progress(LoadProgress(phase: component, fraction: mapped))
      }
    } catch {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelLoad,
          errorDescription:
            "generationFailed: Failed to load PixArt model weights: \(String(describing: error))"))
      throw VinetasError.generationFailed(
        "Failed to load PixArt model weights: \(String(describing: error))"
      )
    }

    self.pipeline = newPipeline
    self.loadedModelID = model.id
    let loadDuration =
      Double((loadClock.now - loadStart).components.seconds)
      + Double((loadClock.now - loadStart).components.attoseconds) / 1e18
    await telemetry?.capture(
      .modelLoadComplete(
        modelID: model.id, engineID: engineID, durationSeconds: loadDuration))
    progress(LoadProgress(phase: "Ready", fraction: 1.0))
  }

  public func unloadModel() async {
    let unloadingID = loadedModelID
    if let pipeline = pipeline {
      await pipeline.unloadModels()
      VinetasMemory.releaseMLXCache()
    }
    pipeline = nil
    loadedModelID = nil
    activeLoRAConfig = nil
    if let unloadingID {
      await telemetry?.capture(.modelUnload(modelID: unloadingID, engineID: engineID))
    }
  }

  // MARK: - Generation

  public func generate(
    request: GenerationRequest,
    stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
  ) async throws -> GenerationResult {
    guard !isGenerating else {
      await telemetry?.capture(
        .concurrencyGateRejected(
          engineID: engineID,
          modelID: loadedModelID ?? "",
          reason: "Generation already in progress."))
      await telemetry?.capture(
        .errorThrown(
          phase: .generationConcurrency,
          errorDescription:
            "generationFailed: Generation already in progress (PixArt)."))
      throw VinetasError.generationFailed(
        "Generation already in progress. MLX does not support concurrent pipeline execution — await the current call before starting another."
      )
    }
    guard let pipeline = self.pipeline, let modelID = self.loadedModelID else {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelLoad,
          errorDescription:
            "generationFailed: No model loaded (PixArt)."))
      throw VinetasError.generationFailed(
        "No model loaded. Call loadModel(_:progress:) before generating."
      )
    }

    // PixArt only supports text-to-image
    if case .imageToImage = request.mode {
      await telemetry?.capture(
        .errorThrown(
          phase: .generationFailed,
          errorDescription:
            "engineFeatureUnsupported: imageToImage on engineID \(engineID)"))
      throw VinetasError.engineFeatureUnsupported(
        feature: .imageToImage(maxReferenceImages: 0),
        engineID: engineID
      )
    }

    let resolvedSeed: UInt32 =
      request.seed.map { UInt32($0 & 0xFFFF_FFFF) }
      ?? UInt32.random(in: 0...UInt32.max)
    let diffusionRequest = translateRequest(request, seed: resolvedSeed)

    let clock = ContinuousClock()
    let startTime = clock.now

    isGenerating = true
    defer { isGenerating = false }
    defer { VinetasMemory.releaseMLXCache() }

    let result: DiffusionGenerationResult
    do {
      // PixArt already flushes the MLX cache on any exit via the
      // `defer { VinetasMemory.releaseMLXCache() }` above (which covers the
      // cancellation throw). The explicit `withTaskCancellationHandler` here
      // matches Flux2's structure and guarantees the flush runs synchronously at
      // the cancellation point rather than only when the awaited call unwinds.
      result = try await withTaskCancellationHandler {
        try await pipeline.generate(request: diffusionRequest) { pipelineProgress in
          if case .generating(let step, let total, let elapsed) = pipelineProgress {
            stepProgress?(step, total, elapsed)
          }
        }
      } onCancel: {
        VinetasMemory.releaseMLXCache()
      }
    } catch {
      await telemetry?.capture(
        .errorThrown(
          phase: .generationFailed,
          errorDescription:
            "PixArt generation failed: \(String(describing: error))"))
      throw VinetasError.generationFailed(
        "PixArt generation failed: \(String(describing: error))"
      )
    }

    // Extract CGImage from RenderedOutput
    guard case .image(let cgImage) = result.output else {
      await telemetry?.capture(
        .errorThrown(
          phase: .generationFailed,
          errorDescription:
            "PixArt pipeline returned unexpected output type."))
      throw VinetasError.generationFailed(
        "PixArt pipeline returned unexpected output type."
      )
    }

    let elapsed = clock.now - startTime
    let durationSeconds =
      Double(elapsed.components.seconds)
      + Double(elapsed.components.attoseconds) / 1e18

    return GenerationResult(
      image: cgImage,
      usedPrompt: request.prompt,
      seed: UInt64(resolvedSeed),
      durationSeconds: durationSeconds,
      modelID: modelID
    )
  }

  // MARK: - LoRA

  public func loadLoRA(at path: URL, scale: Float) async throws {
    guard pipeline != nil else {
      await telemetry?.capture(
        .errorThrown(
          phase: .loraAttach,
          errorDescription:
            "generationFailed: No model loaded for LoRA load (PixArt)."))
      throw VinetasError.generationFailed(
        "No model loaded. Call loadModel(_:progress:) before loading LoRA."
      )
    }
    guard FileManager.default.fileExists(atPath: path.path) else {
      await telemetry?.capture(
        .errorThrown(
          phase: .loraAttach,
          errorDescription:
            "modelNotFound: LoRA file not found at path: \(path.path)"))
      throw VinetasError.modelNotFound(
        "LoRA file not found at path: \(path.path)"
      )
    }
    let effectiveScale = min(max(scale, 0.0), 1.0)
    let loraClock = ContinuousClock()
    let loraStart = loraClock.now
    await telemetry?.capture(
      .loraAttachStart(
        engineID: engineID,
        sourceURL: path.absoluteString,
        scale: Double(effectiveScale)))
    activeLoRAConfig = LoRAConfig(
      localPath: path.path,
      scale: effectiveScale
    )
    let loraDuration =
      Double((loraClock.now - loraStart).components.seconds)
      + Double((loraClock.now - loraStart).components.attoseconds) / 1e18
    await telemetry?.capture(
      .loraAttachComplete(
        engineID: engineID,
        sourceURL: path.absoluteString,
        durationSeconds: loraDuration))
  }

  public func unloadLoRA() async {
    activeLoRAConfig = nil
  }

  // MARK: - Model Management

  #if os(iOS)
    /// Enqueue PixArt's components for iOS background download (#81).
    ///
    /// PixArt is component-addressed: each short `componentId` only resolves to a
    /// repo + file list after SwiftAcervo registry hydration, so this routes
    /// through `Acervo.enqueueBackgroundDownloadComponent(_:)`. Mirrors the
    /// validation of ``download(_:progress:)`` but enqueues instead of awaiting.
    public func enqueueBackgroundDownload(_ model: any ModelDescriptor) async throws {
      guard model.engineID == engineID || model.id == PixArtModelDescriptor.sigmaXL.id else {
        throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
      }
      _ = PixArtComponents.registered
      let ids = model.componentIds
      guard !ids.isEmpty else {
        throw VinetasError.downloadFailed("No component IDs defined for model \(model.id).")
      }
      let registry = CatalogRegistration.shared
      for componentId in ids {
        guard registry.descriptor(for: componentId) != nil else {
          throw VinetasError.downloadFailed(
            "Component '\(componentId)' is not registered in CatalogRegistration.")
        }
        try await Acervo.enqueueBackgroundDownloadComponent(componentId)
      }
    }

    /// PixArt's component ids resolve to Acervo repos via the registry (hydrated
    /// by `enqueueBackgroundDownload`, so `Acervo.component(_:)` carries the repoId).
    public func backgroundDownloadRepoIds(_ model: any ModelDescriptor) async -> [String] {
      _ = PixArtComponents.registered
      return model.componentIds.compactMap { Acervo.component($0)?.repoId }
    }
  #endif

  public func download(
    _ model: any ModelDescriptor,
    progress: @Sendable (DownloadProgress) -> Void
  ) async throws {
    guard model.engineID == engineID || model.id == PixArtModelDescriptor.sigmaXL.id else {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelNotSupported,
          errorDescription:
            "modelNotSupported(modelID: \(model.id), engineID: \(engineID))"))
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }

    // Ensure components are registered before downloading
    _ = PixArtComponents.registered

    let ids = model.componentIds
    guard !ids.isEmpty else {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelDownload,
          errorDescription:
            "downloadFailed: No component IDs defined for model \(model.id)."))
      throw VinetasError.downloadFailed(
        "No component IDs defined for model \(model.id)."
      )
    }

    let total = Double(ids.count)
    let registry = CatalogRegistration.shared
    let reporter = self.telemetry
    // Forward whatever Acervo reporter the CLI bootstrap installed so the
    // 0.17+ inFlightDownloadRegistered/Cleared events (and the rest of the
    // ensureComponentReady event stream) reach the JSONL sink.
    let acervoReporter = await AcervoManager.shared.currentTelemetry

    try await withoutActuallyEscaping(progress) { escapableProgress in
      for (index, componentId) in ids.enumerated() {
        guard registry.descriptor(for: componentId) != nil else {
          await reporter?.capture(
            .errorThrown(
              phase: .modelDownload,
              errorDescription:
                "downloadFailed: Component '\(componentId)' is not registered in CatalogRegistration."
            ))
          throw VinetasError.downloadFailed(
            "Component '\(componentId)' is not registered in CatalogRegistration."
          )
        }

        do {
          try await Acervo.ensureComponentReady(
            componentId,
            progress: { acervoProgress in
              let overall = (Double(index) + acervoProgress.overallProgress) / total
              escapableProgress(
                DownloadProgress(
                  fraction: overall,
                  message: "Downloading \(componentId): \(acervoProgress.fileName)"
                ))
            },
            telemetry: acervoReporter
          )
        } catch {
          print("[PixArtEngine] Failed component '\(componentId)': \(error)")
          await reporter?.capture(
            .errorThrown(
              phase: .modelDownload,
              errorDescription:
                "downloadFailed: Failed to download component '\(componentId)': \(error.localizedDescription)"
            ))
          throw VinetasError.downloadFailed(
            "Failed to download component '\(componentId)': \(error.localizedDescription)"
          )
        }
      }
    }
  }

  public func isAvailable(_ model: any ModelDescriptor) async -> Bool {
    // Ensure components are registered before checking — mirrors the guard in
    // `download` and `loadModel`. Without this, CatalogRegistration has no
    // descriptors on a fresh launch and `isAvailable` always returns false.
    _ = PixArtComponents.registered

    let ids = model.componentIds
    guard !ids.isEmpty else { return false }

    let registry = CatalogRegistration.shared
    for componentId in ids {
      guard let descriptor = registry.descriptor(for: componentId) else { return false }
      let state = await Acervo.availability(descriptor.repoId)
      if state != .available { return false }
    }
    return true
  }

  public func availability(_ model: any ModelDescriptor) async -> ModelAvailability {
    _ = PixArtComponents.registered

    let ids = model.componentIds
    guard !ids.isEmpty else { return .notAvailable }

    let registry = CatalogRegistration.shared
    var entries: [AvailabilityAggregation.Entry] = []
    for componentId in ids {
      guard let descriptor = registry.descriptor(for: componentId) else {
        // Unregistered component → treat as missing so the model surfaces as
        // partial/not-available rather than silently dropping it.
        entries.append(
          AvailabilityAggregation.Entry(componentId: componentId, state: .notAvailable))
        continue
      }
      let state = await Acervo.availability(descriptor.repoId)
      entries.append(AvailabilityAggregation.Entry(componentId: componentId, state: state))
    }
    return AvailabilityAggregation.aggregate(entries)
  }

  public func delete(_ model: any ModelDescriptor) async throws {
    guard model.engineID == engineID || model.id == PixArtModelDescriptor.sigmaXL.id else {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelNotSupported,
          errorDescription:
            "modelNotSupported(modelID: \(model.id), engineID: \(engineID))"))
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }

    let ids = model.componentIds
    let registry = CatalogRegistration.shared

    for componentId in ids {
      guard registry.descriptor(for: componentId) != nil else { continue }
      do {
        try Acervo.deleteComponent(componentId)
      } catch let acervoError as AcervoError {
        // Silently skip components that are not registered with the
        // SwiftAcervo registry: deleteComponent throws
        // `componentNotRegistered` in that case; if registered but absent
        // on disk, it is a no-op and does not throw.
        if case .componentNotRegistered = acervoError { continue }
        await telemetry?.capture(
          .errorThrown(
            phase: .other,
            errorDescription:
              "generationFailed: Failed to delete component '\(componentId)': \(acervoError.localizedDescription)"
          ))
        throw VinetasError.generationFailed(
          "Failed to delete component '\(componentId)': \(acervoError.localizedDescription)"
        )
      }
    }
  }

  public func diskSize(of model: any ModelDescriptor) async -> Int64? {
    let ids = model.componentIds
    guard !ids.isEmpty else { return nil }

    let registry = CatalogRegistration.shared
    // Dedupe by repoId so components that share a model directory don't get
    // counted twice. Returns nil if any descriptor or repoId can't be
    // resolved, matching the prior "missing means unknown size" semantics.
    var repoIds = Set<String>()
    for componentId in ids {
      guard registry.descriptor(for: componentId) != nil else { return nil }
      guard let acervo = Acervo.component(componentId) else { return nil }
      guard Acervo.isComponentReady(componentId) else { return nil }
      repoIds.insert(acervo.repoId)
    }

    var totalSize: Int64 = 0
    for repoId in repoIds {
      do {
        totalSize += try Acervo.modelInfo(repoId).sizeBytes
      } catch {
        return nil
      }
    }
    return totalSize
  }

  public nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation {
    let requiredGB = UInt64(model.minimumMemoryGB)
    let requiredBytes = requiredGB * 1_073_741_824
    let availableBytes = VinetasMemory.systemMemoryBytes

    if availableBytes >= requiredBytes {
      let marginThreshold = requiredBytes + (requiredBytes / 5)
      if availableBytes < marginThreshold {
        return .warning(
          message: "System has \(availableBytes / 1_073_741_824) GB available, "
            + "minimum is \(requiredGB) GB. Performance may be reduced."
        )
      }
      return .ok
    } else {
      return .insufficient(required: requiredBytes, available: availableBytes)
    }
  }

  // MARK: - Private Helpers

  /// Translate a SwiftVinetas ``GenerationRequest`` into a Tuberia ``DiffusionGenerationRequest``.
  ///
  /// - Parameter seed: Pre-resolved seed (always concrete; caller generates random value if request has none).
  private func translateRequest(_ request: GenerationRequest, seed: UInt32)
    -> DiffusionGenerationRequest
  {
    return DiffusionGenerationRequest(
      prompt: request.prompt,
      negativePrompt: request.negativePrompt,
      width: request.width,
      height: request.height,
      steps: request.steps,
      guidanceScale: request.guidanceScale,
      seed: seed,
      loRA: activeLoRAConfig
    )
  }
}

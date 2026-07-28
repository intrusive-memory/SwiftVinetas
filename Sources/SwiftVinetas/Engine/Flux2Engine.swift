import CoreGraphics
import Flux2Core
import Foundation
import SwiftAcervo

// MARK: - Flux2ModelDescriptor

/// Model descriptor for FLUX.2 Klein models.
///
/// Provides static instances for the two supported FLUX.2 Klein variants:
/// - `.klein4B` — 4-billion parameter model (int4 quantized, 16 GB minimum)
/// - `.klein9B` — 9-billion parameter model (qint8 quantized, 24 GB minimum)
public struct Flux2ModelDescriptor: ModelDescriptor {

  public let id: String
  public let displayName: String
  public let engineID: String = "flux2"
  public let license: ModelLicense
  public let minimumMemoryGB: Int
  public let approximateDownloadSize: String
  public let defaultSteps: Int
  public let defaultGuidance: Float
  public let supportedAspectRatios: [AspectRatio]

  // MARK: - Engine-Internal Metadata

  /// The Flux2Core model variant this descriptor maps to.
  internal let flux2Model: Flux2Model

  /// The quantization configuration for this model variant.
  internal let quantizationConfig: Flux2QuantizationConfig

  // MARK: - Static Instances

  /// FLUX.2 Klein 4B — fast generation, 16 GB minimum, int4 quantized.
  public static let klein4B = Flux2ModelDescriptor(
    id: "flux2-klein-4b",
    displayName: "FLUX.2 Klein 4B",
    license: .nonCommercial(details: "FLUX.2 Community License"),
    minimumMemoryGB: 16,
    approximateDownloadSize: "~11 GB",
    defaultSteps: 8,
    defaultGuidance: 3.5,
    supportedAspectRatios: AspectRatio.allCases,
    flux2Model: .klein4B,
    quantizationConfig: .ultraMinimal
  )

  /// FLUX.2 Klein 9B — higher quality, 24 GB minimum, qint8 quantized.
  public static let klein9B = Flux2ModelDescriptor(
    id: "flux2-klein-9b",
    displayName: "FLUX.2 Klein 9B",
    license: .nonCommercial(details: "FLUX.2 Community License"),
    minimumMemoryGB: 24,
    approximateDownloadSize: "~18 GB",
    defaultSteps: 8,
    defaultGuidance: 3.5,
    supportedAspectRatios: AspectRatio.allCases,
    flux2Model: .klein9B,
    quantizationConfig: .balanced
  )
}

// MARK: - Flux2Engine

/// An ``ImageGenerationEngine`` conformance wrapping the existing FLUX.2 pipeline.
///
/// Delegates to `Flux2Pipeline` from Flux2Core for generation, `SwiftAcervo`
/// (`Acervo.ensureAvailable` + `Flux2ModelPaths`) for model management,
/// `VinetasMemory` for memory validation, and
/// `VinetasLoRAManager` for LoRA adapter loading/unloading.
///
/// Quantization selection (`.ultraMinimal` for Klein 4B, `.balanced` for Klein 9B)
/// and two-phase loading (text encoder then transformer + VAE) are handled internally
/// and are not exposed through the protocol.
public actor Flux2Engine: ImageGenerationEngine {

  // MARK: - Identity

  public nonisolated let engineID = "flux2"

  // MARK: - Model Catalog

  public nonisolated var supportedModels: [any ModelDescriptor] {
    [Flux2ModelDescriptor.klein4B, Flux2ModelDescriptor.klein9B]
  }

  // MARK: - Internal State

  /// The currently loaded Flux2Pipeline, if any.
  private var pipeline: Flux2Pipeline?

  /// The model ID currently loaded into the pipeline.
  private var loadedModelID: String?

  /// Prevents actor reentrancy during async generation.
  ///
  /// Swift actors allow reentrancy at `await` suspension points. Without this
  /// guard, two concurrent callers can both enter `generate` and run the MLX
  /// pipeline simultaneously. MLX uses a shared global Metal context and is not
  /// safe for concurrent graph execution — concurrent calls corrupt tensor shapes.
  private var isGenerating = false

  /// Vinetas-scope telemetry reporter, propagated from
  /// ``VinetasClient/setTelemetry(_:)`` via ``EngineRouter``. Stored only —
  /// per REQUIREMENTS §5.3 this override does NOT bridge `Flux2TelemetryEvent`
  /// onto the Vinetas surface.
  private var telemetry: (any VinetasTelemetryReporter)?

  /// Per-component integrity checker invoked in `loadModel` before the deep
  /// loader runs (B2 · C4 · R2.2).
  ///
  /// Production default is a closure wrapping `Acervo.availability(_:verifyHashes:true)`,
  /// which is **marker-aware**:
  /// - When a valid `.acervo-verified.json` marker exists (its `manifestChecksum`
  ///   matches the local manifest), the call returns `.available` immediately —
  ///   no SHA-256 hashing occurs.
  /// - When no marker exists, or the marker is stale, a full SHA-256 audit is
  ///   run and — on a passing result — the marker is written, so subsequent
  ///   calls skip re-hashing.
  /// - A `.partial` result means on-disk weights do not match the manifest
  ///   (corrupted or incomplete download); `loadModel` throws `.modelIncomplete`.
  ///
  /// Note: a model present WITHOUT any marker (e.g. first access before a
  /// download has completed) will full-audit once per session; the download
  /// path writes a marker so subsequent loads take the fast-path.
  ///
  /// Unit tests supply a stub via `init(integrityChecker:)` to force specific
  /// `.partial`/`.available` verdicts without filesystem or CDN access.
  private var integrityChecker: @Sendable (String) async -> ModelAvailability

  // MARK: - Init

  /// Creates a `Flux2Engine` with the production marker-aware integrity checker.
  ///
  /// The default checker calls `Acervo.availability(_:verifyHashes:true)`: when a
  /// valid `.acervo-verified.json` marker is present, it returns `.available` without
  /// re-hashing; when no marker or a stale marker exists, it performs a full SHA-256
  /// audit and writes the marker on success.
  public init() {
    self.integrityChecker = { repoId in
      await Acervo.availability(repoId, verifyHashes: true)
    }
  }

  /// Creates a `Flux2Engine` with an injected integrity checker.
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
      true
    case .imageToImage:
      true
    case .loraInference:
      true
    case .loraTraining:
      true
    case .promptUpsampling:
      false
    }
  }

  // MARK: - Lifecycle

  public func loadModel(
    _ model: any ModelDescriptor,
    progress: @Sendable (LoadProgress) -> Void
  ) async throws {
    guard let descriptor = resolveDescriptor(model) else {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelNotSupported,
          errorDescription:
            "modelNotSupported(modelID: \(model.id), engineID: \(engineID))"))
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }

    // If the same model is already loaded, skip
    if loadedModelID == descriptor.id, pipeline != nil {
      progress(LoadProgress(phase: "Already loaded", fraction: 1.0))
      return
    }

    // Unload any existing model first
    await unloadModel()

    // B2: Fail-fast integrity guard (C4 · R2.2 · R6).
    //
    // Before the Flux2Pipeline constructor or any deep loader call, run the
    // marker-aware integrity checker for each required component:
    //
    //   • Valid `.acervo-verified.json` marker present → `.available` immediately,
    //     no SHA-256 re-hashing (fast-path; typical for already-downloaded models).
    //   • No marker / stale marker → full SHA-256 audit; marker written on pass.
    //   • `.partial` result → on-disk weights do not match CDN manifest (corrupted
    //     or incomplete download); surface a clear user-facing error here instead of
    //     letting the MLX loader emit a cryptic shard-missing message.
    //
    // The checker defaults to `Acervo.availability(_:verifyHashes:true)` (marker-
    // aware). Unit tests inject a stub via `init(integrityChecker:)` to force
    // specific verdicts without filesystem or CDN access.
    progress(LoadProgress(phase: "Verifying model integrity", fraction: 0.0))
    var incompleteComponents: [String] = []
    for component in Self.modelComponents(for: descriptor) {
      let repoId = Self.acervoRepoId(for: component)
      let result = await integrityChecker(repoId)
      if case .partial = result {
        incompleteComponents.append(repoId)
      }
    }
    if !incompleteComponents.isEmpty {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelLoad,
          errorDescription:
            "modelIncomplete: \(descriptor.id) — components: \(incompleteComponents.joined(separator: ", "))"
        ))
      throw VinetasError.modelIncomplete(
        modelID: descriptor.id,
        components: incompleteComponents
      )
    }

    progress(LoadProgress(phase: "Creating pipeline", fraction: 0.05))

    let memoryOpt = MemoryOptimizationConfig.recommended(
      forRAMGB: VinetasMemory.systemMemoryGB
    )

    let newPipeline = Flux2Pipeline(
      model: descriptor.flux2Model,
      quantization: descriptor.quantizationConfig,
      memoryOptimization: memoryOpt
    )

    progress(LoadProgress(phase: "Loading models", fraction: 0.1))

    await telemetry?.capture(.modelLoadStart(modelID: descriptor.id, engineID: engineID))
    let loadClock = ContinuousClock()
    let loadStart = loadClock.now

    // Configure MLX memory budget for the current process before loading
    VinetasMemory.configureMLXBudgetForCurrentProcess()

    try await withoutActuallyEscaping(progress) { escapableProgress in
      try await newPipeline.loadModels(progressCallback: { downloadProgress, message in
        let fraction = 0.1 + downloadProgress * 0.9
        escapableProgress(LoadProgress(phase: message, fraction: fraction))
      })
    }

    self.pipeline = newPipeline
    self.loadedModelID = descriptor.id

    let loadDuration = Self.elapsedSeconds(from: loadStart, clock: loadClock)
    await telemetry?.capture(
      .modelLoadComplete(
        modelID: descriptor.id, engineID: engineID, durationSeconds: loadDuration))

    progress(LoadProgress(phase: "Ready", fraction: 1.0))
  }

  public func unloadModel() async {
    let unloadingID = loadedModelID
    if let pipeline = pipeline {
      await pipeline.clearAll()
    }
    pipeline = nil
    loadedModelID = nil
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
            "generationFailed: Generation already in progress (Flux2)."))
      throw VinetasError.generationFailed(
        "Generation already in progress. MLX does not support concurrent pipeline execution — await the current call before starting another."
      )
    }
    guard let pipeline = self.pipeline, let modelID = self.loadedModelID else {
      await telemetry?.capture(
        .errorThrown(
          phase: .modelLoad,
          errorDescription:
            "generationFailed: No model loaded (Flux2)."))
      throw VinetasError.generationFailed(
        "No model loaded. Call loadModel(_:progress:) before generating."
      )
    }

    let resolvedSeed = request.seed ?? UInt64.random(in: 0...UInt64.max)

    let clock = ContinuousClock()
    let startTime = clock.now

    isGenerating = true
    defer { isGenerating = false }

    let flux2Result: Flux2GenerationResult

    switch request.mode {
    case .textToImage:
      do {
        // Wrap the pipeline call so a cancelled generation Task deterministically
        // flushes the MLX buffer cache. PixArt already does this via
        // `defer { VinetasMemory.releaseMLXCache() }`; Flux2 lacked an equivalent,
        // leaving the cache un-flushed on cancel. `releaseMLXCache()` is a static
        // `enum` call (Memory.clearCache()) — Sendable and non-actor-isolated, so
        // it is legal inside the synchronous, nonisolated `onCancel` closure.
        // Flush-only (not unload): keeps the loaded weights warm for the next
        // generate while reclaiming the transient diffusion working-set buffers.
        flux2Result = try await withTaskCancellationHandler {
          try await pipeline.generateTextToImageWithResult(
            prompt: request.prompt,
            height: request.height,
            width: request.width,
            steps: request.steps,
            guidance: request.guidanceScale,
            seed: resolvedSeed,
            onProgress: { currentStep, totalSteps in
              let elapsed = Self.elapsedSeconds(from: startTime, clock: clock)
              stepProgress?(currentStep, totalSteps, elapsed)
            }
          )
        } onCancel: {
          VinetasMemory.releaseMLXCache()
        }
      } catch {
        await telemetry?.capture(
          .errorThrown(
            phase: .generationFailed,
            errorDescription:
              "Text-to-image generation failed: \(error.localizedDescription)"))
        throw VinetasError.generationFailed(
          "Text-to-image generation failed: \(error.localizedDescription)"
        )
      }

    case .imageToImage(let references):
      do {
        // See the text-to-image branch above: flush the MLX cache on cancel so a
        // cancelled Flux2 generation does not leave transient buffers resident.
        flux2Result = try await withTaskCancellationHandler {
          try await pipeline.generateImageToImageWithResult(
            prompt: request.prompt,
            images: references,
            height: request.height,
            width: request.width,
            steps: request.steps,
            guidance: request.guidanceScale,
            seed: resolvedSeed,
            onProgress: { currentStep, totalSteps in
              let elapsed = Self.elapsedSeconds(from: startTime, clock: clock)
              stepProgress?(currentStep, totalSteps, elapsed)
            }
          )
        } onCancel: {
          VinetasMemory.releaseMLXCache()
        }
      } catch {
        await telemetry?.capture(
          .errorThrown(
            phase: .generationFailed,
            errorDescription:
              "Image-to-image generation failed: \(error.localizedDescription)"))
        throw VinetasError.generationFailed(
          "Image-to-image generation failed: \(error.localizedDescription)"
        )
      }
    }

    let durationSeconds = Self.elapsedSeconds(from: startTime, clock: clock)

    return GenerationResult(
      image: flux2Result.image,
      usedPrompt: request.prompt,
      seed: resolvedSeed,
      durationSeconds: durationSeconds,
      modelID: modelID
    )
  }

  // MARK: - LoRA

  public func loadLoRA(at path: URL, scale: Float) async throws {
    guard let pipeline = self.pipeline else {
      await telemetry?.capture(
        .errorThrown(
          phase: .loraAttach,
          errorDescription: "generationFailed: No model loaded for LoRA load (Flux2)."))
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
    let config = LoRAConfig(
      filePath: path.path,
      scale: effectiveScale,
      activationKeyword: nil
    )
    try pipeline.loadLoRA(config)
    let loraDuration = Self.elapsedSeconds(from: loraStart, clock: loraClock)
    await telemetry?.capture(
      .loraAttachComplete(
        engineID: engineID,
        sourceURL: path.absoluteString,
        durationSeconds: loraDuration))
  }

  public func unloadLoRA() async {
    pipeline?.unloadAllLoRAs()
  }

  // MARK: - Model Management

  #if os(iOS)
    /// Enqueue FLUX.2's component repos for iOS background download (#81).
    ///
    /// FLUX.2 is repo-addressed: each component exposes a `repoId`, so this
    /// routes through `Acervo.enqueueBackgroundDownload(modelId:)`. Mirrors the
    /// CDN-provisioning guard of ``download(_:progress:)`` but enqueues instead
    /// of awaiting.
    public nonisolated func enqueueBackgroundDownload(_ model: any ModelDescriptor) async throws {
      guard let descriptor = resolveDescriptor(model) else {
        throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
      }
      for component in Self.modelComponents(for: descriptor) {
        if case .transformer(let variant) = component, !variant.isProvisionedOnCDN {
          throw VinetasError.downloadFailed(
            "Variant \(variant.rawValue) is not provisioned on the Acervo CDN.")
        }
        try await Acervo.enqueueBackgroundDownload(modelId: component.repoId)
      }
    }

    /// FLUX.2 components are repo-addressed, so the repo ids are known directly.
    public nonisolated func backgroundDownloadRepoIds(_ model: any ModelDescriptor) async
      -> [String]
    {
      guard let descriptor = resolveDescriptor(model) else { return [] }
      return Self.modelComponents(for: descriptor).map { $0.repoId }
    }
  #endif

  public nonisolated func download(
    _ model: any ModelDescriptor,
    progress: @Sendable (DownloadProgress) -> Void
  ) async throws {
    let reporter = await self.telemetry
    guard let descriptor = resolveDescriptor(model) else {
      await reporter?.capture(
        .errorThrown(
          phase: .modelNotSupported,
          errorDescription:
            "modelNotSupported(modelID: \(model.id), engineID: \(engineID))"))
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }

    let components = Self.modelComponents(for: descriptor)
    let total = Double(components.count)

    try await withoutActuallyEscaping(progress) { escapableProgress in
      for (index, component) in components.enumerated() {
        if case .transformer(let variant) = component, !variant.isProvisionedOnCDN {
          await reporter?.capture(
            .errorThrown(
              phase: .modelDownload,
              errorDescription:
                "downloadFailed: Variant \(variant.rawValue) is not provisioned on the Acervo CDN."
            ))
          throw VinetasError.downloadFailed(
            "Variant \(variant.rawValue) is not provisioned on the Acervo CDN."
          )
        }
        do {
          try await Acervo.ensureAvailable(
            component.repoId,
            files: []
          ) { acervoProgress in
            let overall = (Double(index) + acervoProgress.overallProgress) / total
            let msg =
              "Downloading \(component.displayName): \(acervoProgress.fileName) "
              + "(\(acervoProgress.fileIndex + 1)/\(acervoProgress.totalFiles))"
            escapableProgress(DownloadProgress(fraction: overall, message: msg))
          }
        } catch {
          await reporter?.capture(
            .errorThrown(
              phase: .modelDownload,
              errorDescription:
                "downloadFailed: Failed to download \(component.displayName): \(error.localizedDescription)"
            ))
          throw VinetasError.downloadFailed(
            "Failed to download \(component.displayName): \(error.localizedDescription)"
          )
        }
      }
    }
  }

  public func isAvailable(_ model: any ModelDescriptor) async -> Bool {
    guard let descriptor = resolveDescriptor(model) else { return false }
    for component in Self.modelComponents(for: descriptor) {
      let state = await Acervo.availability(Self.acervoRepoId(for: component))
      if state != .available { return false }
    }
    return true
  }

  public func availability(_ model: any ModelDescriptor) async -> ModelAvailability {
    guard let descriptor = resolveDescriptor(model) else { return .notAvailable }
    var entries: [AvailabilityAggregation.Entry] = []
    for component in Self.modelComponents(for: descriptor) {
      let repoId = Self.acervoRepoId(for: component)
      let state = await Acervo.availability(repoId)
      entries.append(AvailabilityAggregation.Entry(componentId: repoId, state: state))
    }
    return AvailabilityAggregation.aggregate(entries)
  }

  public nonisolated func delete(_ model: any ModelDescriptor) async throws {
    let reporter = await self.telemetry
    guard let descriptor = resolveDescriptor(model) else {
      await reporter?.capture(
        .errorThrown(
          phase: .modelNotSupported,
          errorDescription:
            "modelNotSupported(modelID: \(model.id), engineID: \(engineID))"))
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }
    for component in Self.modelComponents(for: descriptor) {
      if let registryComponent = component.registryComponent {
        try Flux2ModelPaths.delete(registryComponent)
      } else {
        // Text encoder: SwiftVinetas manages it by repo id directly (the
        // upstream component would resolve to the wrong Mistral repo). Delete
        // the Acervo model directory if present; idempotent otherwise.
        let repoId = component.repoId
        if let modelDir = try? Acervo.modelDirectory(for: repoId),
          FileManager.default.fileExists(atPath: modelDir.path)
        {
          try? Acervo.deleteModel(repoId)
        }
      }
    }
  }

  public func diskSize(of model: any ModelDescriptor) async -> Int64? {
    guard let descriptor = resolveDescriptor(model) else { return nil }
    let components = Self.modelComponents(for: descriptor)
    // Multiple Flux components can share a repoId (e.g., Klein 4B transformer
    // and VAE both live under "black-forest-labs/FLUX.2-klein-4B"). Dedupe so
    // we don't double-count the shared directory.
    let uniqueRepoIds = Set(components.map { Self.acervoRepoId(for: $0) })
    var totalSize: Int64 = 0
    for repoId in uniqueRepoIds {
      do {
        totalSize += try Acervo.modelInfo(repoId).sizeBytes
      } catch {
        return nil
      }
    }
    return totalSize
  }

  public nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation {
    guard let descriptor = resolveDescriptor(model) else {
      return .insufficient(required: 0, available: VinetasMemory.systemMemoryBytes)
    }

    let requiredGB = UInt64(descriptor.minimumMemoryGB)
    let requiredBytes = requiredGB * 1_073_741_824
    let availableBytes = VinetasMemory.systemMemoryBytes

    if availableBytes >= requiredBytes {
      // Check if memory is marginal (within 20% above minimum)
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

  /// Resolve a generic `ModelDescriptor` to a `Flux2ModelDescriptor`.
  ///
  /// Returns `nil` if the model does not belong to this engine.
  private nonisolated func resolveDescriptor(_ model: any ModelDescriptor) -> Flux2ModelDescriptor?
  {
    // First, check if it's already the right type
    if let flux2 = model as? Flux2ModelDescriptor {
      return flux2
    }
    // Fall back to ID-based lookup
    switch model.id {
    case Flux2ModelDescriptor.klein4B.id:
      return .klein4B
    case Flux2ModelDescriptor.klein9B.id:
      return .klein9B
    default:
      return nil
    }
  }

  /// Resolve the Acervo repo ID for a ``Flux2Component``.
  ///
  /// Used by `isAvailable`/`availability`/`diskSize` as the `repoId` argument to
  /// the corresponding `Acervo` queries.
  ///
  /// **Note**: The VAE shares its `repoId` (`"black-forest-labs/FLUX.2-klein-4B"`) with
  /// the Klein 4B transformer; both Acervo checks resolve to the same directory.
  /// This is intentional — the VAE lives in a subfolder of the same Acervo model directory.
  ///
  /// **Text encoder**: SwiftVinetas owns this mapping via ``Flux2Component/TextEncoder``
  /// and routes to the Acervo-managed Qwen3-MLX-8bit encoders — never the upstream
  /// `ModelRegistry.TextEncoderVariant.repoId`, which returns Mistral repos.
  nonisolated static func acervoRepoId(for component: Flux2Component) -> String {
    component.repoId
  }

  /// Map a descriptor to its FLUX.2 model components.
  ///
  /// Klein 4B/9B both require a transformer, a dedicated Qwen3 text encoder, and
  /// the shared VAE. Enumerating the text encoder here is what lets
  /// `availability(_:)` surface a missing dependency as `.partial` rather than
  /// reporting the model `.available` with the encoder absent (R4 / D1).
  nonisolated static func modelComponents(
    for descriptor: Flux2ModelDescriptor
  ) -> [Flux2Component] {
    // Resolve the transformer variant the pipeline will ACTUALLY load at
    // generation time (via `Flux2Pipeline.loadTransformer()`), rather than
    // hardcoding the bf16 variant. Availability/download/delete/diskSize all
    // key off this set, so it must match the variant generation loads — e.g.
    // Klein 4B's `.ultraMinimal` config resolves to `.klein4B_4bit` (int4),
    // NOT `.klein4B_bf16`. Klein 9B always resolves to bf16.
    let transformerVariant = ModelRegistry.TransformerVariant.variant(
      for: descriptor.flux2Model,
      quantization: descriptor.quantizationConfig.transformer
    )
    switch descriptor.id {
    case Flux2ModelDescriptor.klein9B.id:
      return [.transformer(transformerVariant), .textEncoder(.klein9B), .vae(.standard)]
    default:
      return [.transformer(transformerVariant), .textEncoder(.klein4B), .vae(.standard)]
    }
  }

  /// Calculate elapsed seconds from a start time.
  private static func elapsedSeconds(
    from start: ContinuousClock.Instant,
    clock: ContinuousClock
  ) -> Double {
    let elapsed = clock.now - start
    return Double(elapsed.components.seconds)
      + Double(elapsed.components.attoseconds) / 1e18
  }
}

// MARK: - Flux2Component

/// SwiftVinetas-owned model-component descriptor for FLUX.2 Klein.
///
/// Mirrors `ModelRegistry.ModelComponent` for the transformer and VAE, but owns
/// the text-encoder repo-id mapping directly. The upstream
/// `ModelRegistry.TextEncoderVariant` (and its `repoId`/`huggingFaceRepo`)
/// resolves to **Mistral** repos, which is the wrong source for the FLUX.2 Klein
/// text encoder. SwiftVinetas instead routes the text encoder to the
/// Acervo-managed Qwen3-MLX-8bit encoders:
/// - `klein4B` → `lmstudio-community/Qwen3-4B-MLX-8bit`
/// - `klein9B` → `lmstudio-community/Qwen3-8B-MLX-8bit`
enum Flux2Component: Sendable {
  case transformer(ModelRegistry.TransformerVariant)
  case textEncoder(TextEncoder)
  case vae(ModelRegistry.VAEVariant)

  /// The Acervo-managed Qwen3 text encoder paired with a FLUX.2 Klein variant.
  ///
  /// Deliberately **not** backed by `ModelRegistry.TextEncoderVariant`, whose
  /// `repoId` returns Mistral repos. SwiftVinetas owns this mapping so the
  /// dependency audit targets the correct (Qwen3) source.
  enum TextEncoder: String, Sendable, CaseIterable {
    case klein4B
    case klein9B

    /// Acervo repo id for the paired Qwen3-MLX-8bit text encoder.
    var repoId: String {
      switch self {
      case .klein4B: return "lmstudio-community/Qwen3-4B-MLX-8bit"
      case .klein9B: return "lmstudio-community/Qwen3-8B-MLX-8bit"
      }
    }

    var displayName: String {
      switch self {
      case .klein4B: return "Qwen3-4B Text Encoder"
      case .klein9B: return "Qwen3-8B Text Encoder"
      }
    }
  }

  /// Acervo repo id for this component.
  var repoId: String {
    switch self {
    case .transformer(let variant): return variant.repoId
    case .textEncoder(let encoder): return encoder.repoId
    case .vae(let variant): return variant.repoId
    }
  }

  /// Human-readable name surfaced in download progress + telemetry.
  var displayName: String {
    switch self {
    case .transformer(let variant):
      return ModelRegistry.ModelComponent.transformer(variant).displayName
    case .textEncoder(let encoder):
      return encoder.displayName
    case .vae(let variant):
      return ModelRegistry.ModelComponent.vae(variant).displayName
    }
  }

  /// Bridge to the upstream `ModelRegistry.ModelComponent` for `Flux2ModelPaths`
  /// path/delete helpers. Returns `nil` for the text encoder, which SwiftVinetas
  /// manages by repo id directly (the upstream component would resolve to the
  /// wrong Mistral repo).
  var registryComponent: ModelRegistry.ModelComponent? {
    switch self {
    case .transformer(let variant): return .transformer(variant)
    case .vae(let variant): return .vae(variant)
    case .textEncoder: return nil
    }
  }
}

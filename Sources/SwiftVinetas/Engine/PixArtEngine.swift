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
  public let estimatedSecondsPerImage: Int

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
  /// - Estimated time: ~10 sec on M2 Max
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
    estimatedSecondsPerImage: 10,
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

  // MARK: - Init

  public init() {}

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

    let result: DiffusionGenerationResult
    do {
      result = try await pipeline.generate(request: diffusionRequest) { pipelineProgress in
        if case .generating(let step, let total, let elapsed) = pipelineProgress {
          stepProgress?(step, total, elapsed)
        }
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
          try await Acervo.ensureComponentReady(componentId) { acervoProgress in
            let overall = (Double(index) + acervoProgress.overallProgress) / total
            escapableProgress(
              DownloadProgress(
                fraction: overall,
                message: "Downloading \(componentId): \(acervoProgress.fileName)"
              ))
          }
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
        // SwiftAcervo registry (per Acervo.swift:1820, deleteComponent
        // throws `componentNotRegistered` in that case; if registered
        // but absent on disk, it is a no-op and does not throw).
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
    var totalSize: Int64 = 0

    for componentId in ids {
      guard registry.descriptor(for: componentId) != nil else { return nil }
      // Skip components that aren't downloaded — return nil to match the
      // prior "missing directory means unknown size" semantics rather
      // than letting `withComponentAccess` throw.
      guard Acervo.isComponentReady(componentId) else { return nil }

      let componentSize: Int64
      do {
        componentSize = try await AcervoManager.shared.withComponentAccess(componentId) {
          handle -> Int64 in
          // FileManager.default is fetched inside the @Sendable closure to
          // avoid capturing a non-Sendable FileManager from the outer scope.
          let fm = FileManager.default
          var sum: Int64 = 0
          guard
            let enumerator = fm.enumerator(
              at: handle.rootDirectoryURL,
              includingPropertiesForKeys: [.fileSizeKey]
            )
          else { return 0 }
          while let fileURL = enumerator.nextObject() as? URL {
            if let resourceValues = try? fileURL.resourceValues(
              forKeys: Set<URLResourceKey>([.fileSizeKey])),
              let fileSize = resourceValues.fileSize
            {
              sum += Int64(fileSize)
            }
          }
          return sum
        }
      } catch {
        // Integrity check or registry mismatch — surface as "unknown".
        return nil
      }
      totalSize += componentSize
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

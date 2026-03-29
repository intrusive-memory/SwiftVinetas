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

  // MARK: - Init

  public init() {}

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
    progress: @Sendable (LoadProgress) -> Void
  ) async throws {
    guard model.engineID == engineID || model.id == PixArtModelDescriptor.sigmaXL.id else {
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

    progress(LoadProgress(phase: "Assembling pipeline", fraction: 0.0))

    let newPipeline: PixArtPipeline
    do {
      newPipeline = try PixArtPipeline(recipe: PixArtRecipe())
    } catch {
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
      throw VinetasError.generationFailed(
        "Failed to load PixArt model weights: \(error.localizedDescription)"
      )
    }

    self.pipeline = newPipeline
    self.loadedModelID = model.id
    progress(LoadProgress(phase: "Ready", fraction: 1.0))
  }

  public func unloadModel() async {
    if let pipeline = pipeline {
      await pipeline.unloadModels()
    }
    pipeline = nil
    loadedModelID = nil
    activeLoRAConfig = nil
  }

  // MARK: - Generation

  public func generate(
    request: GenerationRequest,
    stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
  ) async throws -> GenerationResult {
    guard let pipeline = self.pipeline, let modelID = self.loadedModelID else {
      throw VinetasError.generationFailed(
        "No model loaded. Call loadModel(_:progress:) before generating."
      )
    }

    // PixArt only supports text-to-image
    if case .imageToImage = request.mode {
      throw VinetasError.engineFeatureUnsupported(
        feature: .imageToImage(maxReferenceImages: 0),
        engineID: engineID
      )
    }

    let diffusionRequest = translateRequest(request)
    let startTime = Date()

    let result: DiffusionGenerationResult
    do {
      result = try await pipeline.generate(request: diffusionRequest) { pipelineProgress in
        if case .generating(let step, let total, let elapsed) = pipelineProgress {
          stepProgress?(step, total, elapsed)
        }
      }
    } catch {
      throw VinetasError.generationFailed(
        "PixArt generation failed: \(error.localizedDescription)"
      )
    }

    // Extract CGImage from RenderedOutput
    guard case .image(let cgImage) = result.output else {
      throw VinetasError.generationFailed(
        "PixArt pipeline returned unexpected output type."
      )
    }

    let duration = Date().timeIntervalSince(startTime)

    return GenerationResult(
      image: cgImage,
      usedPrompt: request.prompt,
      seed: UInt64(result.seed),
      durationSeconds: duration,
      modelID: modelID
    )
  }

  // MARK: - LoRA

  public func loadLoRA(at path: URL, scale: Float) async throws {
    guard pipeline != nil else {
      throw VinetasError.generationFailed(
        "No model loaded. Call loadModel(_:progress:) before loading LoRA."
      )
    }
    guard FileManager.default.fileExists(atPath: path.path) else {
      throw VinetasError.modelNotFound(
        "LoRA file not found at path: \(path.path)"
      )
    }
    let effectiveScale = min(max(scale, 0.0), 1.0)
    activeLoRAConfig = LoRAConfig(
      localPath: path.path,
      scale: effectiveScale
    )
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
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }

    // Ensure components are registered before downloading
    _ = PixArtComponents.registered

    let ids = model.componentIds
    guard !ids.isEmpty else {
      throw VinetasError.downloadFailed(
        "No component IDs defined for model \(model.id)."
      )
    }

    let total = Double(ids.count)
    let registry = CatalogRegistration.shared

    try await withoutActuallyEscaping(progress) { escapableProgress in
      for (index, componentId) in ids.enumerated() {
        guard let descriptor = registry.descriptor(for: componentId) else {
          throw VinetasError.downloadFailed(
            "Component '\(componentId)' is not registered in CatalogRegistration."
          )
        }
        let repoId = descriptor.huggingFaceRepo

        // Debug: log the CDN URL being requested
        let slug = repoId.replacingOccurrences(of: "/", with: "_")
        print("[PixArtEngine] Downloading component '\(componentId)'")
        print("[PixArtEngine]   HuggingFace repo: \(repoId)")
        print("[PixArtEngine]   CDN slug: \(slug)")
        print(
          "[PixArtEngine]   CDN manifest URL: https://pub-8e049ed02be340cbb18f921765fd24f3.r2.dev/models/\(slug)/manifest.json"
        )

        do {
          // Pass empty files array to download ALL files listed in the
          // CDN manifest. The registry's filePatterns are globs (e.g.
          // "*.safetensors") which Acervo cannot match by exact path.
          try await AcervoManager.shared.download(
            repoId,
            files: []
          ) { acervoProgress in
            let overall = (Double(index) + acervoProgress.overallProgress) / total
            escapableProgress(
              DownloadProgress(
                fraction: overall,
                message: "Downloading \(componentId): \(acervoProgress.fileName)"
              ))
          }
        } catch {
          print("[PixArtEngine] Failed component '\(componentId)': \(error)")
          throw VinetasError.downloadFailed(
            "Failed to download component '\(componentId)': \(error.localizedDescription)"
          )
        }
      }
    }
  }

  public nonisolated func isAvailable(_ model: any ModelDescriptor) -> Bool {
    let ids = model.componentIds
    guard !ids.isEmpty else { return false }

    let registry = CatalogRegistration.shared
    return ids.allSatisfy { componentId in
      guard let descriptor = registry.descriptor(for: componentId) else { return false }
      return Acervo.isModelAvailable(descriptor.huggingFaceRepo)
    }
  }

  public func delete(_ model: any ModelDescriptor) async throws {
    guard model.engineID == engineID || model.id == PixArtModelDescriptor.sigmaXL.id else {
      throw VinetasError.modelNotSupported(modelID: model.id, engineID: engineID)
    }

    let ids = model.componentIds
    let registry = CatalogRegistration.shared

    for componentId in ids {
      guard let descriptor = registry.descriptor(for: componentId) else { continue }
      do {
        try Acervo.deleteModel(descriptor.huggingFaceRepo)
      } catch let acervoError as AcervoError {
        // Silently skip components that are not present on disk.
        if case .modelNotFound = acervoError { continue }
        throw VinetasError.generationFailed(
          "Failed to delete component '\(componentId)': \(acervoError.localizedDescription)"
        )
      }
    }
  }

  public nonisolated func diskSize(of model: any ModelDescriptor) -> Int64? {
    let ids = model.componentIds
    guard !ids.isEmpty else { return nil }

    let registry = CatalogRegistration.shared
    var totalSize: Int64 = 0
    let fm = FileManager.default

    for componentId in ids {
      guard let descriptor = registry.descriptor(for: componentId),
        let dir = try? Acervo.modelDirectory(for: descriptor.huggingFaceRepo)
      else {
        return nil
      }
      guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey])
      else {
        return nil
      }
      while let fileURL = enumerator.nextObject() as? URL {
        if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
          let fileSize = resourceValues.fileSize
        {
          totalSize += Int64(fileSize)
        }
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
  private func translateRequest(_ request: GenerationRequest) -> DiffusionGenerationRequest {
    // Seed: GenerationRequest uses UInt64, DiffusionGenerationRequest uses UInt32.
    // Truncate to UInt32 range for compatibility.
    let seed32: UInt32? = request.seed.map { UInt32($0 & 0xFFFF_FFFF) }

    return DiffusionGenerationRequest(
      prompt: request.prompt,
      negativePrompt: request.negativePrompt,
      width: request.width,
      height: request.height,
      steps: request.steps,
      guidanceScale: request.guidanceScale,
      seed: seed32,
      loRA: activeLoRAConfig
    )
  }
}

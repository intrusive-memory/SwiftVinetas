import Flux2Core
import Foundation

/// Progress information for model downloads.
public struct VinetasDownloadProgress: Sendable {
  /// Overall progress from 0.0 to 1.0.
  public let overallProgress: Double
  /// Human-readable status message.
  public let message: String
}

/// Manages FLUX.2 model downloads, caching, and availability via Flux2Core.
///
/// Wraps `Flux2ModelDownloader` and `ModelRegistry` to provide model management
/// specific to SwiftVinetas' FLUX.2 models. Models are stored at
/// `~/Library/Caches/models/` where the Flux2 pipeline can find them.
public enum VinetasModelManager: Sendable {

  /// Downloads required model components (transformer + VAE) for a FLUX.2 model.
  ///
  /// Uses `Flux2ModelDownloader` so models are stored where the pipeline expects them.
  /// Idempotent: if the model is already cached, returns immediately.
  ///
  /// - Parameters:
  ///   - model: The FLUX.2 model variant to download.
  ///   - progress: Optional progress callback reporting download status.
  /// - Throws: `VinetasError.downloadFailed` if the download fails.
  public static func download(
    model: VinetasModel,
    progress: (@Sendable (VinetasDownloadProgress) -> Void)? = nil
  ) async throws {
    let downloader = Flux2ModelDownloader()
    let components = modelComponents(for: model)
    let total = Double(components.count)

    for (index, component) in components.enumerated() {
      let componentProgress: Flux2DownloadProgressCallback = { p, msg in
        let overall = (Double(index) + p) / total
        progress?(VinetasDownloadProgress(overallProgress: overall, message: msg))
      }
      do {
        _ = try await downloader.download(component, progress: componentProgress)
      } catch {
        throw VinetasError.downloadFailed(
          "Failed to download \(component.displayName): \(error.localizedDescription)"
        )
      }
    }
  }

  /// Checks whether all required components for a model are downloaded.
  ///
  /// - Parameter model: The model to check.
  /// - Returns: `true` if the model is cached and ready to use.
  public static func isAvailable(_ model: VinetasModel) -> Bool {
    modelComponents(for: model).allSatisfy { ModelRegistry.isDownloaded($0) }
  }

  /// Returns the local filesystem directory for the transformer component.
  ///
  /// - Parameter model: The model to locate.
  /// - Returns: The URL of the model's local directory.
  /// - Throws: `VinetasError.modelNotFound` if the model directory cannot be resolved.
  public static func modelDirectory(for model: VinetasModel) throws -> URL {
    let variant = transformerVariant(for: model)
    guard let path = Flux2ModelDownloader.findModelPath(for: .transformer(variant)) else {
      throw VinetasError.modelNotFound(model.rawValue)
    }
    return path
  }

  /// Deletes the downloaded model components from local storage.
  ///
  /// - Parameter model: The model to delete.
  /// - Throws: If the deletion fails.
  public static func delete(model: VinetasModel) throws {
    for component in modelComponents(for: model) {
      try Flux2ModelDownloader.delete(component)
    }
  }

  /// Lists all known FLUX.2 models with their availability status.
  ///
  /// Returns one `VinetasModelInfo` per known `VinetasModel` case, including
  /// models that have not yet been downloaded.
  ///
  /// - Returns: An array of `VinetasModelInfo`, one per known model.
  public static func listAllModels() throws -> [VinetasModelInfo] {
    VinetasModel.allCases.map { model in
      VinetasModelInfo(
        name: model.huggingFaceRepo,
        size: 0,
        downloadDate: nil,
        isDownloaded: isAvailable(model)
      )
    }
  }

  // MARK: - CDN Configuration

  /// Configures a CDN base URL for model downloads.
  ///
  /// When set, the downloader fetches models from the CDN instead of
  /// HuggingFace, eliminating authentication requirements. Falls back
  /// to HuggingFace if the CDN download fails.
  ///
  /// Call this once at app startup before any download operations.
  ///
  /// - Parameter baseURL: The CDN base URL (e.g. `https://cdn.example.com`).
  public static func configureCDN(baseURL: URL) {
    ModelRegistry.cdnBaseURL = baseURL
  }

  // MARK: - Private

  private static func transformerVariant(for model: VinetasModel)
    -> ModelRegistry.TransformerVariant
  {
    switch model {
    case .klein4b: .klein4B_bf16
    case .klein9b: .klein9B_bf16
    case .pixartSigma:
      // Fallback: PixArt models are not managed through Flux2 downloader.
      // This case exists only for exhaustive switch; prefer EngineRouter for dispatch.
      .klein4B_bf16
    }
  }

  private static func modelComponents(for model: VinetasModel) -> [ModelRegistry.ModelComponent] {
    [.transformer(transformerVariant(for: model)), .vae(.standard)]
  }
}

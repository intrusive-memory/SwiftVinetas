import Flux2Core
import Foundation
import SwiftAcervo

/// Progress information for model downloads.
public struct VinetasDownloadProgress: Sendable {
  /// Overall progress from 0.0 to 1.0.
  public let overallProgress: Double
  /// Human-readable status message.
  public let message: String
}

/// Manages model downloads, caching, and availability via the engine router.
///
/// `VinetasModelManager` routes all operations through `VinetasClient.shared.router`,
/// delegating to the appropriate engine for each model. This replaces the previous
/// direct coupling to `Flux2ModelDownloader`.
///
/// For new code, prefer calling `VinetasClient.shared.download(model:progress:)`,
/// `VinetasClient.shared.isAvailable(_:)`, etc. directly.
public enum VinetasModelManager: Sendable {

  // MARK: - Primary API (any ModelDescriptor)

  /// Downloads a model by routing through the engine responsible for it.
  ///
  /// - Parameters:
  ///   - model: The model descriptor to download.
  ///   - progress: Optional callback reporting download progress.
  /// - Throws: ``VinetasError/engineNotFound(engineID:)`` if no engine handles the model,
  ///           ``VinetasError/downloadFailed(_:)`` if the download fails.
  public static func download(
    model: any ModelDescriptor,
    progress: (@Sendable (VinetasDownloadProgress) -> Void)? = nil
  ) async throws {
    try await VinetasClient.shared.download(model: model, progress: progress)
  }

  /// Checks whether a model's weights are available on disk.
  ///
  /// Routes through the engine registered for the model's `engineID`.
  ///
  /// - Parameter model: The model descriptor to check.
  /// - Returns: `true` if the model is cached and ready to use.
  public static func isAvailable(_ model: any ModelDescriptor) async throws -> Bool {
    try await VinetasClient.shared.isAvailable(model)
  }

  /// Deletes a model's weights from local storage.
  ///
  /// Routes through the engine registered for the model's `engineID`.
  ///
  /// - Parameter model: The model descriptor to delete.
  /// - Throws: ``VinetasError/engineNotFound(engineID:)`` if no engine handles the model.
  public static func delete(_ model: any ModelDescriptor) async throws {
    try await VinetasClient.shared.delete(model)
  }

  /// Lists all known models across all registered engines with their availability status.
  ///
  /// - Returns: An array of ``VinetasModelInfo``, one per known model.
  public static func listAllModels() async -> [VinetasModelInfo] {
    await VinetasClient.shared.listModels()
  }

  // MARK: - CDN Configuration

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

  // MARK: - Storage Configuration

  /// No-op — storage is configured via the `ACERVO_APP_GROUP_ID` environment
  /// variable (or the process entitlement).
  ///
  /// SwiftAcervo resolves the storage location automatically:
  /// - **macOS**: `~/Library/Group Containers/<ACERVO_APP_GROUP_ID>/SharedModels/`
  /// - **iOS with entitlement**: App group shared container
  ///
  /// Set `ACERVO_APP_GROUP_ID` in `~/.zprofile` for CLI/test use, or declare
  /// `com.apple.security.application-groups` in the app's `.entitlements` file.
  ///
  /// Called automatically by ``VinetasClient/init()``.
  public static func configureStorage() {
  }

  /// No-op stub retained for source compatibility.
  ///
  /// `Acervo.customBaseDirectory` no longer exists; storage path is driven by
  /// `ACERVO_APP_GROUP_ID` (env var) or the app-group entitlement. This
  /// overload can no longer redirect Acervo's base directory.
  ///
  /// - Parameter baseURL: Ignored.
  @available(
    *, deprecated,
    message:
      "Acervo.customBaseDirectory was removed. Set ACERVO_APP_GROUP_ID instead."
  )
  public static func configureStorage(baseURL: URL) {
  }

  // MARK: - Deprecated API (VinetasModel)

  /// Downloads a FLUX.2 model by its legacy ``VinetasModel`` enum case.
  ///
  /// - Parameters:
  ///   - model: The legacy model variant to download.
  ///   - progress: Optional callback reporting download progress.
  @available(*, deprecated, message: "Use download(model: any ModelDescriptor) instead")
  public static func download(
    model: VinetasModel,
    progress: (@Sendable (VinetasDownloadProgress) -> Void)? = nil
  ) async throws {
    try await download(model: model.descriptor, progress: progress)
  }

  /// Checks whether a FLUX.2 model's weights are available on disk.
  ///
  /// - Parameter model: The legacy model variant to check.
  /// - Returns: `true` if the model is cached and ready to use.
  @available(*, deprecated, message: "Use isAvailable(_ model: any ModelDescriptor) instead")
  public static func isAvailable(_ model: VinetasModel) -> Bool {
    modelComponents(for: model).allSatisfy { ModelRegistry.isDownloaded($0) }
  }

  /// Deletes the downloaded FLUX.2 model components from local storage.
  ///
  /// - Parameter model: The legacy model variant to delete.
  @available(*, deprecated, message: "Use delete(_ model: any ModelDescriptor) instead")
  public static func delete(model: VinetasModel) throws {
    for component in modelComponents(for: model) {
      try Flux2ModelDownloader.delete(component)
    }
  }

  /// Returns the local filesystem directory for the transformer component.
  ///
  /// - Parameter model: The model to locate.
  /// - Returns: The URL of the model's local directory.
  /// - Throws: `VinetasError.modelNotFound` if the model directory cannot be resolved.
  @available(*, deprecated, message: "Access model paths through the engine directly")
  public static func modelDirectory(for model: VinetasModel) throws -> URL {
    let variant = transformerVariant(for: model)
    guard let path = Flux2ModelDownloader.findModelPath(for: .transformer(variant)) else {
      throw VinetasError.modelNotFound(model.rawValue)
    }
    return path
  }

  // MARK: - Private Helpers

  private static func transformerVariant(for model: VinetasModel)
    -> ModelRegistry.TransformerVariant
  {
    switch model {
    case .klein4b: .klein4B_bf16
    case .klein9b: .klein9B_bf16
    case .pixartSigma:
      // Fallback: PixArt models are not managed through Flux2 downloader.
      .klein4B_bf16
    }
  }

  private static func modelComponents(for model: VinetasModel) -> [ModelRegistry.ModelComponent] {
    [.transformer(transformerVariant(for: model)), .vae(.standard)]
  }
}

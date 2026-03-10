import Foundation
import SwiftAcervo

/// Manages FLUX.2 model downloads, caching, and availability via SwiftAcervo.
///
/// Wraps SwiftAcervo's `Acervo` API to provide model management specific
/// to SwiftVinetas' FLUX.2 models, including download, listing, and
/// validation of cached models at `~/Library/SharedModels/`.
public enum VinetasModelManager: Sendable {

    /// The core model files required for a FLUX.2 model to be usable.
    private static let requiredModelFiles: [String] = [
        "config.json",
    ]

    /// Downloads a FLUX.2 model if not already cached.
    ///
    /// Uses `Acervo.ensureAvailable` for idempotent downloading -- if the model
    /// is already cached, this returns immediately without re-downloading.
    ///
    /// - Parameters:
    ///   - model: The FLUX.2 model variant to download.
    ///   - progress: Optional progress callback reporting download status.
    /// - Throws: `VinetasError.downloadFailed` if the download fails.
    public static func download(
        model: VinetasModel,
        progress: (@Sendable (AcervoDownloadProgress) -> Void)? = nil
    ) async throws {
        do {
            try await Acervo.ensureAvailable(
                model.huggingFaceRepo,
                files: requiredModelFiles,
                token: nil,
                progress: progress
            )
        } catch {
            throw VinetasError.downloadFailed(
                "Failed to download \(model.rawValue) from \(model.huggingFaceRepo): \(error.localizedDescription)"
            )
        }
    }

    /// Checks whether a model is locally available.
    ///
    /// - Parameter model: The model to check.
    /// - Returns: `true` if the model is cached and ready to use.
    public static func isAvailable(_ model: VinetasModel) -> Bool {
        Acervo.isModelAvailable(model.huggingFaceRepo)
    }

    /// Returns the local filesystem directory for a cached model.
    ///
    /// - Parameter model: The model to locate.
    /// - Returns: The URL of the model's local directory.
    /// - Throws: `VinetasError.modelNotFound` if the model directory cannot be resolved.
    public static func modelDirectory(for model: VinetasModel) throws -> URL {
        do {
            return try Acervo.modelDirectory(for: model.huggingFaceRepo)
        } catch {
            throw VinetasError.modelNotFound(model.rawValue)
        }
    }

    /// Lists all FLUX.2 models currently cached in `~/Library/SharedModels/`.
    ///
    /// Returns information about each cached model that matches a known
    /// `VinetasModel` HuggingFace repository ID.
    ///
    /// - Returns: An array of `VinetasModelInfo` for each cached model.
    /// - Throws: If the shared models directory cannot be read.
    public static func listCachedModels() throws -> [VinetasModelInfo] {
        let allModels = try Acervo.listModels()
        let knownRepos = Set(VinetasModel.allCases.map(\.huggingFaceRepo))

        return allModels
            .filter { knownRepos.contains($0.id) }
            .map { acervoModel in
                VinetasModelInfo(
                    name: acervoModel.id,
                    size: acervoModel.sizeBytes,
                    downloadDate: acervoModel.downloadDate,
                    isDownloaded: true
                )
            }
    }

    /// Lists all known FLUX.2 models with their availability status.
    ///
    /// Returns one `VinetasModelInfo` per known `VinetasModel` case, including
    /// models that have not yet been downloaded. For downloaded models, includes
    /// size and download date from SwiftAcervo.
    ///
    /// - Returns: An array of `VinetasModelInfo`, one per known model.
    public static func listAllModels() throws -> [VinetasModelInfo] {
        let cachedModels = try Acervo.listModels()
        let cachedByID = Dictionary(uniqueKeysWithValues: cachedModels.map { ($0.id, $0) })

        return VinetasModel.allCases.map { model in
            if let cached = cachedByID[model.huggingFaceRepo] {
                VinetasModelInfo(
                    name: model.huggingFaceRepo,
                    size: cached.sizeBytes,
                    downloadDate: cached.downloadDate,
                    isDownloaded: true
                )
            } else {
                VinetasModelInfo(
                    name: model.huggingFaceRepo,
                    size: 0,
                    downloadDate: nil,
                    isDownloaded: false
                )
            }
        }
    }
}

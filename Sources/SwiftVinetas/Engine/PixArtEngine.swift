import Foundation

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
        estimatedSecondsPerImage: 10
    )
}

// MARK: - PixArtEngine

#if canImport(PixArtCore)
import PixArtCore

/// An ``ImageGenerationEngine`` conformance that wraps the PixArt-Sigma pipeline
/// from the `PixArtCore` module.
///
/// When `PixArtCore` is available, this actor delegates all operations to the
/// real PixArt inference pipeline. When `PixArtCore` is not importable, a stub
/// actor replaces this implementation — see the `#else` branch below.
public actor PixArtEngine: ImageGenerationEngine {

    public let engineID = "pixart-sigma"

    public nonisolated var supportedModels: [any ModelDescriptor] {
        [PixArtModelDescriptor.sigmaXL]
    }

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

    public nonisolated func isAvailable(_ model: any ModelDescriptor) -> Bool {
        // Delegate to PixArtCore model registry when available.
        // PixArtCore integration is stubbed until the package ships.
        return false
    }

    public nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation {
        // PixArtCore integration is stubbed until the package ships.
        return .insufficient(required: 0, available: 0)
    }

    public nonisolated func diskSize(of model: any ModelDescriptor) -> Int64? {
        return nil
    }

    public func loadModel(
        _ model: any ModelDescriptor,
        progress: @Sendable (LoadProgress) -> Void
    ) async throws {
        throw VinetasError.generationFailed("PixArtCore integration is not yet implemented.")
    }

    public func unloadModel() async {
        // No-op until PixArtCore integration is implemented.
    }

    public func generate(
        request: GenerationRequest,
        stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
    ) async throws -> GenerationResult {
        throw VinetasError.generationFailed(
            "PixArt-Sigma generation is not yet implemented. PixArtCore integration is pending."
        )
    }

    public func loadLoRA(at path: URL, scale: Float) async throws {
        throw VinetasError.generationFailed("PixArtCore LoRA injection is not yet implemented.")
    }

    public func unloadLoRA() async {
        // No-op until PixArtCore integration is implemented.
    }

    public func download(
        _ model: any ModelDescriptor,
        progress: @Sendable (DownloadProgress) -> Void
    ) async throws {
        throw VinetasError.downloadFailed("PixArtCore download is not yet implemented.")
    }

    public func delete(_ model: any ModelDescriptor) async throws {
        throw VinetasError.generationFailed("PixArtCore delete is not yet implemented.")
    }
}

#else

/// Stub ``ImageGenerationEngine`` for PixArt-Sigma used when `PixArtCore` is not
/// available (i.e., the `pixart-swift-mlx` package has not been added to the project).
///
/// All generation and download operations throw or return failure values.
/// ``isAvailable(_:)`` always returns `false` so the engine is safely excluded from
/// model selection in the UI.
///
/// Replace this stub with the real implementation once `PixArtCore` is importable.
public actor PixArtEngine: ImageGenerationEngine {

    public let engineID = "pixart-sigma"

    public nonisolated var supportedModels: [any ModelDescriptor] {
        [PixArtModelDescriptor.sigmaXL]
    }

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

    /// Always returns `false` when `PixArtCore` is unavailable.
    public nonisolated func isAvailable(_ model: any ModelDescriptor) -> Bool {
        return false
    }

    /// Always returns `.insufficient` when `PixArtCore` is unavailable.
    public nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation {
        return .insufficient(required: 0, available: 0)
    }

    public nonisolated func diskSize(of model: any ModelDescriptor) -> Int64? {
        return nil
    }

    public func loadModel(
        _ model: any ModelDescriptor,
        progress: @Sendable (LoadProgress) -> Void
    ) async throws {
        throw VinetasError.generationFailed(
            "PixArt-Sigma is not available. Add the pixart-swift-mlx package to enable it."
        )
    }

    public func unloadModel() async {
        // No-op — no model is loaded in the stub.
    }

    /// Always throws ``VinetasError/generationFailed(_:)`` when `PixArtCore` is unavailable.
    public func generate(
        request: GenerationRequest,
        stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
    ) async throws -> GenerationResult {
        throw VinetasError.generationFailed(
            "PixArt-Sigma is not available. Add the pixart-swift-mlx package to enable it."
        )
    }

    public func loadLoRA(at path: URL, scale: Float) async throws {
        throw VinetasError.generationFailed(
            "PixArt-Sigma is not available. Add the pixart-swift-mlx package to enable it."
        )
    }

    public func unloadLoRA() async {
        // No-op — no LoRA is loaded in the stub.
    }

    /// Always throws ``VinetasError/downloadFailed(_:)`` when `PixArtCore` is unavailable.
    public func download(
        _ model: any ModelDescriptor,
        progress: @Sendable (DownloadProgress) -> Void
    ) async throws {
        throw VinetasError.downloadFailed(
            "PixArt-Sigma is not available. Add the pixart-swift-mlx package to enable it."
        )
    }

    public func delete(_ model: any ModelDescriptor) async throws {
        throw VinetasError.generationFailed(
            "PixArt-Sigma is not available. Add the pixart-swift-mlx package to enable it."
        )
    }
}

#endif

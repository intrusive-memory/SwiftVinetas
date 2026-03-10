import CoreGraphics
import Flux2Core
import Foundation
import SwiftAcervo

/// SwiftVinetas - Storyboard and comic panel generation from text prompts.
///
/// Generates sequential visual panels from text descriptions using
/// FLUX.2 Klein models on Apple Silicon via MLX.
public enum Vinetas: Sendable {

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
        let effectiveStyle = style ?? StyleConfig()
        let output = try await VinetasPipeline.generatePanel(
            prompt: prompt,
            style: effectiveStyle,
            model: model
        )
        return output.image
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
        stepProgress: (@Sendable (_ currentStep: Int, _ totalSteps: Int, _ elapsed: TimeInterval) -> Void)? = nil
    ) async throws -> [CGImage] {
        let effectiveStyle = style ?? StyleConfig()
        let outputs = try await VinetasPipeline.generateSequence(
            prompts: prompts,
            referenceImages: referenceImages,
            style: effectiveStyle,
            model: model,
            panelProgress: progress,
            stepProgress: stepProgress
        )
        return outputs.map(\.image)
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
        stepProgress: (@Sendable (_ currentStep: Int, _ totalSteps: Int, _ elapsed: TimeInterval) -> Void)? = nil
    ) async throws -> [PanelOutput] {
        let promptFile = try PromptFile.parse(url: url)
        return try await VinetasPipeline.generateFromPromptFile(
            promptFile,
            model: model,
            panelProgress: progress,
            stepProgress: stepProgress
        )
    }

    // MARK: - Preview

    /// Generate a fast, low-quality preview image for rapid prompt iteration.
    ///
    /// Forces Klein 4B, 4 inference steps, and 512×512 output for quick turnaround.
    /// Use this to validate prompt composition before committing to a full generation run.
    ///
    /// - Parameter prompt: Text description of the panel to preview.
    /// - Returns: The generated image as a CGImage at 512×512.
    public static func preview(prompt: String) async throws -> CGImage {
        let previewStyle = StyleConfig(
            steps: 4,
            width: 512,
            height: 512
        )
        let output = try await VinetasPipeline.generatePanel(
            prompt: prompt,
            style: previewStyle,
            model: .klein4b
        )
        return output.image
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
        progress: (@Sendable (AcervoDownloadProgress) -> Void)? = nil
    ) async throws {
        try await VinetasModelManager.download(model: model, progress: progress)
    }

    /// List all known FLUX.2 models with their cache status.
    ///
    /// Returns one entry per known model variant, including whether it has
    /// been downloaded, its size on disk, and its download date.
    ///
    /// - Returns: An array of `VinetasModelInfo` for each known model.
    /// - Throws: If the shared models directory cannot be read.
    public static func listModels() throws -> [VinetasModelInfo] {
        try VinetasModelManager.listAllModels()
    }

    /// Validate whether the system has sufficient memory for a model.
    ///
    /// Checks the system's physical memory against the model's minimum
    /// requirement (Klein 4B: 16 GB, Klein 9B: 24 GB).
    ///
    /// - Parameter model: The model to validate against.
    /// - Returns: `true` if the system has enough memory to load the model.
    /// - Throws: `VinetasError.insufficientMemory` if validation fails.
    public static func validateMemory(for model: VinetasModel) throws -> Bool {
        let sufficient = VinetasMemory.validate(for: model)
        if !sufficient {
            throw VinetasError.insufficientMemory(
                required: VinetasMemory.requiredMemoryBytes(for: model),
                available: VinetasMemory.systemMemoryBytes
            )
        }
        return true
    }
}

/// Available FLUX.2 model variants.
public enum VinetasModel: String, Sendable, CaseIterable {
    case klein4b = "klein4b"
    case klein9b = "klein9b"

    /// The HuggingFace repository identifier for this model.
    public var huggingFaceRepo: String {
        switch self {
        case .klein4b:
            "black-forest-labs/FLUX.2-klein-4B"
        case .klein9b:
            "black-forest-labs/FLUX.2-klein-9B"
        }
    }

    /// Minimum system memory in GB required to run this model.
    public var minimumMemoryGB: Int {
        switch self {
        case .klein4b:
            16
        case .klein9b:
            24
        }
    }

    /// The quantization format used for inference.
    public var quantization: String {
        switch self {
        case .klein4b:
            "int4"
        case .klein9b:
            "qint8"
        }
    }

    /// Estimated generation time per image in seconds on M3/M4 Pro.
    public var estimatedSecondsPerImage: Int {
        switch self {
        case .klein4b:
            26
        case .klein9b:
            62
        }
    }
}

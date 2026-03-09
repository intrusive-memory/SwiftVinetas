import CoreGraphics
import Flux2Core
import Foundation

/// SwiftVinetas - Storyboard and comic panel generation from text prompts.
///
/// Generates sequential visual panels from text descriptions using
/// FLUX.2 Klein models on Apple Silicon via MLX.
public enum Vinetas: Sendable {

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
        // TODO: Initialize Flux2Pipeline, configure, generate
        fatalError("Not yet implemented")
    }

    /// Generate a sequence of panels from an array of prompts.
    /// - Parameters:
    ///   - prompts: Ordered text descriptions for each panel.
    ///   - referenceImages: Optional reference images for character consistency (up to 3).
    ///   - style: Optional style configuration applied to all panels.
    ///   - model: The FLUX.2 model variant to use.
    ///   - progress: Callback reporting (currentPanel, totalPanels).
    /// - Returns: Array of generated CGImages, one per prompt.
    public static func generateSequence(
        prompts: [String],
        referenceImages: [CGImage]? = nil,
        style: StyleConfig? = nil,
        model: VinetasModel = .klein4b,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [CGImage] {
        // TODO: Batch generation with optional image-to-image conditioning
        fatalError("Not yet implemented")
    }

    /// Generate panels from a YAML prompt file.
    /// - Parameters:
    ///   - url: Path to the YAML prompt file.
    ///   - model: The FLUX.2 model variant to use.
    ///   - progress: Callback reporting (currentPanel, totalPanels).
    /// - Returns: Array of PanelOutput containing images and metadata.
    public static func generateFromFile(
        _ url: URL,
        model: VinetasModel = .klein4b,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [PanelOutput] {
        // TODO: Parse YAML, generate sequence
        fatalError("Not yet implemented")
    }
}

/// Available FLUX.2 model variants.
public enum VinetasModel: String, Sendable, CaseIterable {
    case klein4b = "klein4b"
    case klein9b = "klein9b"
}

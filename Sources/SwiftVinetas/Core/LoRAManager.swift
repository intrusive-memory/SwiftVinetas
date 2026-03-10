import Flux2Core
import Foundation

/// Manages LoRA adapter loading and unloading on a `Flux2Pipeline`.
///
/// Wraps `Flux2Pipeline.loadLoRA(_:)` and `Flux2Pipeline.unloadAllLoRAs()`
/// with validation, scale clamping, and activation keyword support.
internal struct VinetasLoRAManager: Sendable {

    // MARK: - Loading

    /// Load a LoRA adapter from a safetensors file onto the pipeline.
    ///
    /// - Parameters:
    ///   - path: Absolute path to the `.safetensors` file.
    ///   - scale: Adapter influence scale (clamped to 0.0–1.0). Defaults to 1.0 if nil.
    ///   - activationKeyword: Optional trigger word injected at the start of prompts.
    ///   - pipeline: The Flux2Pipeline to load the adapter onto.
    /// - Returns: The activation keyword if one was provided, otherwise nil.
    /// - Throws: `VinetasError.modelNotFound` if the safetensors file does not exist.
    @discardableResult
    static func load(
        path: String,
        scale: Float? = nil,
        activationKeyword: String? = nil,
        on pipeline: Flux2Pipeline
    ) throws -> String? {
        // Validate file exists
        guard FileManager.default.fileExists(atPath: path) else {
            throw VinetasError.modelNotFound(
                "LoRA file not found at path: \(path)"
            )
        }

        // Clamp scale to valid range
        let effectiveScale = scale.map { min(max($0, 0.0), 1.0) }

        let config = LoRAConfig(
            filePath: path,
            scale: effectiveScale,
            activationKeyword: activationKeyword
        )

        try pipeline.loadLoRA(config)
        return activationKeyword
    }

    /// Unload all LoRA adapters from the pipeline.
    ///
    /// - Parameter pipeline: The Flux2Pipeline to clear adapters from.
    static func unloadAll(from pipeline: Flux2Pipeline) {
        pipeline.unloadAllLoRAs()
    }

    // MARK: - Style Integration

    /// Load a LoRA if configured in a `StyleConfig`.
    ///
    /// If the style has a `loraPath`, this loads the corresponding adapter
    /// onto the pipeline. Otherwise, this is a no-op.
    ///
    /// - Parameters:
    ///   - style: The style configuration to inspect for LoRA settings.
    ///   - pipeline: The Flux2Pipeline to load onto.
    /// - Returns: The activation keyword if one was configured on the LoRA, otherwise nil.
    @discardableResult
    static func loadIfConfigured(
        style: StyleConfig,
        on pipeline: Flux2Pipeline
    ) throws -> String? {
        guard let loraPath = style.loraPath else {
            return nil
        }

        return try load(
            path: loraPath,
            scale: style.loraScale,
            on: pipeline
        )
    }
}

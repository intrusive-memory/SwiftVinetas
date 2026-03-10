import CoreGraphics
import Flux2Core
import Foundation

/// Wraps `Flux2Pipeline` from Flux2Core, managing the full lifecycle:
/// model selection, memory validation, model loading, generation, and result return.
///
/// Reports the loading strategy to stderr so callers can observe pipeline behavior.
internal enum VinetasPipeline {

    // MARK: - Flux2Model Mapping

    /// Maps a `VinetasModel` to the corresponding `Flux2Model` case.
    private static func flux2Model(for model: VinetasModel) -> Flux2Model {
        switch model {
        case .klein4b:
            .klein4B
        case .klein9b:
            .klein9B
        }
    }

    /// Selects the appropriate quantization config for a model.
    ///
    /// - Klein 4B: `.ultraMinimal` (int4 transformer, ~30 GB)
    /// - Klein 9B: `.balanced` (qint8 transformer, ~57 GB)
    private static func quantizationConfig(for model: VinetasModel) -> Flux2QuantizationConfig {
        switch model {
        case .klein4b:
            .ultraMinimal
        case .klein9b:
            .balanced
        }
    }

    /// Selects the appropriate memory optimization config based on system RAM.
    private static func memoryOptimizationConfig() -> MemoryOptimizationConfig {
        MemoryOptimizationConfig.recommended(forRAMGB: VinetasMemory.systemMemoryGB)
    }

    // MARK: - Logging

    /// Writes a log message to stderr.
    private static func log(_ message: String) {
        let line = "[SwiftVinetas] \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    // MARK: - Generation

    /// Generates a single panel image from a text prompt.
    ///
    /// Creates a `Flux2Pipeline`, validates memory, loads models, composes the prompt
    /// from style and panel prompts, generates the image, and returns a `PanelOutput`
    /// with full metadata.
    ///
    /// - Parameters:
    ///   - prompt: The text description for the panel.
    ///   - style: Style configuration (steps, guidance, seed, dimensions, style/negative prompts).
    ///   - model: The FLUX.2 model variant to use.
    /// - Returns: A `PanelOutput` containing the generated image and metadata.
    /// - Throws: `VinetasError.insufficientMemory` if the system lacks sufficient RAM,
    ///           `VinetasError.generationFailed` if image generation fails.
    internal static func generatePanel(
        prompt: String,
        style: StyleConfig,
        model: VinetasModel
    ) async throws -> PanelOutput {
        // 1. Validate memory
        let memoryOK = VinetasMemory.validate(for: model)
        if !memoryOK {
            throw VinetasError.insufficientMemory(
                required: VinetasMemory.requiredMemoryBytes(for: model),
                available: VinetasMemory.systemMemoryBytes
            )
        }

        // 2. Log loading strategy
        let strategy = VinetasMemory.loadingStrategy()
        let availableGB = VinetasMemory.systemMemoryGB
        log("Loading strategy: \(strategy) (\(availableGB) GB available)")

        // 3. Create pipeline
        let flux2 = flux2Model(for: model)
        let quantization = quantizationConfig(for: model)
        let memoryOpt = memoryOptimizationConfig()

        let pipeline = Flux2Pipeline(
            model: flux2,
            quantization: quantization,
            memoryOptimization: memoryOpt
        )

        // 4. Load models
        log("Loading models for \(model.rawValue)...")
        try await pipeline.loadModels(progressCallback: { progress, message in
            log("Download: \(Int(progress * 100))% — \(message)")
        })

        // 5. Compose prompt: prepend style prompt to panel prompt
        let composedPrompt: String
        if style.stylePrompt.isEmpty {
            composedPrompt = prompt
        } else {
            composedPrompt = "\(style.stylePrompt), \(prompt)"
        }

        // 6. Resolve seed
        let resolvedSeed: UInt64
        if let userSeed = style.seed {
            resolvedSeed = userSeed
        } else {
            resolvedSeed = UInt64.random(in: 0...UInt64.max)
        }

        // 7. Measure generation time
        let clock = ContinuousClock()
        let startTime = clock.now

        // 8. Generate
        log("Generating image: \(style.width)x\(style.height), \(style.steps) steps, seed \(resolvedSeed)")

        let result: Flux2GenerationResult
        do {
            result = try await pipeline.generateTextToImageWithResult(
                prompt: composedPrompt,
                height: style.height,
                width: style.width,
                steps: style.steps,
                guidance: style.guidanceScale,
                seed: resolvedSeed,
                onProgress: { currentStep, totalSteps in
                    log("Step \(currentStep)/\(totalSteps)")
                }
            )
        } catch {
            throw VinetasError.generationFailed(
                "Pipeline generation failed: \(error.localizedDescription)"
            )
        }

        let elapsed = clock.now - startTime
        let durationSeconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18

        log("Generation complete in \(String(format: "%.1f", durationSeconds))s")

        // 9. Build PanelOutput
        let output = PanelOutput(
            image: result.image,
            prompt: composedPrompt,
            seed: resolvedSeed,
            durationSeconds: durationSeconds,
            model: model,
            width: style.width,
            height: style.height
        )

        return output
    }
}

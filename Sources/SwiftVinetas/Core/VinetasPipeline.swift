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

    // MARK: - Character-Aware Generation

    /// Generates a single panel image with character LoRA support.
    ///
    /// When a character is provided, its trigger word is prepended to the prompt
    /// and its LoRA adapter (if available) is loaded before generation and unloaded
    /// after generation to prevent bleeding into subsequent calls.
    ///
    /// - Parameters:
    ///   - prompt: The text description for the panel.
    ///   - character: The character whose trigger word and LoRA to apply.
    ///   - style: Style configuration (steps, guidance, seed, dimensions, style/negative prompts).
    ///   - model: The FLUX.2 model variant to use.
    /// - Returns: A `PanelOutput` containing the generated image and metadata.
    /// - Throws: `VinetasError.insufficientMemory` if the system lacks sufficient RAM,
    ///           `VinetasError.generationFailed` if image generation fails,
    ///           `VinetasError.modelNotFound` if the character's LoRA file does not exist.
    internal static func generatePanelWithCharacter(
        prompt: String,
        character: Character,
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
        log("Character: \(character.name) (trigger: \(character.triggerWord))")

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

        // 5. Load character LoRA if available
        if let lora = character.lora {
            let manager = CharacterManager()
            let charDir = manager.characterDirectory(slug: character.slug)
            let loraPath = charDir.appendingPathComponent(lora.path).path
            log("Loading character LoRA: \(lora.path) (scale: \(lora.scale))")
            try VinetasLoRAManager.load(
                path: loraPath,
                scale: lora.scale,
                activationKeyword: character.triggerWord,
                on: pipeline
            )
        }

        // 6. Compose prompt: trigger word + style + panel prompt
        let composedPrompt = composeCharacterPrompt(
            panelPrompt: prompt,
            character: character,
            style: style
        )

        // 7. Resolve seed
        let resolvedSeed: UInt64
        if let userSeed = style.seed {
            resolvedSeed = userSeed
        } else {
            resolvedSeed = UInt64.random(in: 0...UInt64.max)
        }

        // 8. Measure generation time
        let clock = ContinuousClock()
        let startTime = clock.now

        // 9. Generate
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

        // 10. Unload LoRA to prevent bleeding
        if character.lora != nil {
            VinetasLoRAManager.unloadAll(from: pipeline)
        }

        // 11. Build PanelOutput
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

    // MARK: - Character Prompt Composition

    /// Compose a prompt with character trigger word injection.
    ///
    /// The trigger word is always prepended at the START of the prompt,
    /// followed by the style prompt (if any), followed by the panel prompt.
    /// Format: `"<triggerWord>, <stylePrompt>, <panelPrompt>"`
    ///
    /// - Parameters:
    ///   - panelPrompt: The panel-specific text prompt.
    ///   - character: The character whose trigger word to inject.
    ///   - style: The style configuration.
    /// - Returns: The composed prompt string.
    internal static func composeCharacterPrompt(
        panelPrompt: String,
        character: Character,
        style: StyleConfig
    ) -> String {
        var composed = ""
        if !character.triggerWord.isEmpty {
            composed += "\(character.triggerWord), "
        }
        if !style.stylePrompt.isEmpty {
            composed += "\(style.stylePrompt), "
        }
        composed += panelPrompt
        return composed
    }

    // MARK: - Batch Generation

    /// Progress callback providing step-level detail during generation.
    ///
    /// - Parameters:
    ///   - currentStep: The current inference step within the current panel.
    ///   - totalSteps: Total inference steps for the current panel.
    ///   - elapsed: Wall-clock time elapsed since generation of the current panel started.
    internal typealias StepProgressCallback = @Sendable (
        _ currentStep: Int,
        _ totalSteps: Int,
        _ elapsed: TimeInterval
    ) -> Void

    /// Generates a sequence of panels from an array of prompts.
    ///
    /// If `referenceImages` are provided, uses image-to-image generation for each panel.
    /// Otherwise, uses text-to-image generation.
    ///
    /// - Parameters:
    ///   - prompts: Ordered text descriptions for each panel.
    ///   - referenceImages: Optional reference images for character consistency.
    ///   - style: Style configuration applied to all panels.
    ///   - model: The FLUX.2 model variant to use.
    ///   - panelProgress: Callback reporting (currentPanel, totalPanels).
    ///   - stepProgress: Callback reporting step-level progress within each panel.
    /// - Returns: Array of PanelOutput containing generated images and metadata.
    internal static func generateSequence(
        prompts: [String],
        referenceImages: [CGImage]? = nil,
        style: StyleConfig,
        model: VinetasModel,
        panelProgress: ((Int, Int) -> Void)? = nil,
        stepProgress: StepProgressCallback? = nil
    ) async throws -> [PanelOutput] {
        guard !prompts.isEmpty else { return [] }

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

        // 5. Load LoRA if configured
        let activationKeyword = try VinetasLoRAManager.loadIfConfigured(
            style: style,
            on: pipeline
        )

        // 6. Iterate panels sequentially
        var outputs: [PanelOutput] = []
        let totalPanels = prompts.count
        let useImageToImage = referenceImages != nil && !referenceImages!.isEmpty

        for (index, prompt) in prompts.enumerated() {
            panelProgress?(index + 1, totalPanels)

            // Compose prompt: activation keyword + style + panel prompt
            var composedPrompt = ""
            if let keyword = activationKeyword, !keyword.isEmpty {
                composedPrompt += "\(keyword), "
            }
            if !style.stylePrompt.isEmpty {
                composedPrompt += "\(style.stylePrompt), "
            }
            composedPrompt += prompt

            // Resolve seed
            let resolvedSeed: UInt64
            if let userSeed = style.seed {
                resolvedSeed = userSeed
            } else {
                resolvedSeed = UInt64.random(in: 0...UInt64.max)
            }

            // Measure generation time
            let clock = ContinuousClock()
            let startTime = clock.now

            log("Generating panel \(index + 1)/\(totalPanels): \(style.width)x\(style.height), \(style.steps) steps, seed \(resolvedSeed)")

            let result: Flux2GenerationResult
            do {
                if useImageToImage {
                    result = try await pipeline.generateImageToImageWithResult(
                        prompt: composedPrompt,
                        images: referenceImages!,
                        height: style.height,
                        width: style.width,
                        steps: style.steps,
                        guidance: style.guidanceScale,
                        seed: resolvedSeed,
                        onProgress: { currentStep, totalSteps in
                            let elapsed = Double((clock.now - startTime).components.seconds)
                                + Double((clock.now - startTime).components.attoseconds) / 1e18
                            stepProgress?(currentStep, totalSteps, elapsed)
                            log("Panel \(index + 1) — Step \(currentStep)/\(totalSteps)")
                        }
                    )
                } else {
                    result = try await pipeline.generateTextToImageWithResult(
                        prompt: composedPrompt,
                        height: style.height,
                        width: style.width,
                        steps: style.steps,
                        guidance: style.guidanceScale,
                        seed: resolvedSeed,
                        onProgress: { currentStep, totalSteps in
                            let elapsed = Double((clock.now - startTime).components.seconds)
                                + Double((clock.now - startTime).components.attoseconds) / 1e18
                            stepProgress?(currentStep, totalSteps, elapsed)
                            log("Panel \(index + 1) — Step \(currentStep)/\(totalSteps)")
                        }
                    )
                }
            } catch {
                throw VinetasError.generationFailed(
                    "Panel \(index + 1) generation failed: \(error.localizedDescription)"
                )
            }

            let elapsed = clock.now - startTime
            let durationSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18

            log("Panel \(index + 1) complete in \(String(format: "%.1f", durationSeconds))s")

            let output = PanelOutput(
                image: result.image,
                prompt: composedPrompt,
                seed: resolvedSeed,
                durationSeconds: durationSeconds,
                model: model,
                width: style.width,
                height: style.height
            )
            outputs.append(output)
        }

        // 7. Clean up LoRAs
        if style.loraPath != nil {
            VinetasLoRAManager.unloadAll(from: pipeline)
        }

        return outputs
    }

    // MARK: - Prompt File Generation

    /// Generates panels from a parsed `PromptFile`.
    ///
    /// Iterates panels sequentially, resolving per-panel style overrides,
    /// and reports progress at both panel and step levels.
    ///
    /// - Parameters:
    ///   - promptFile: The parsed prompt file with project metadata and panels.
    ///   - model: The FLUX.2 model variant to use.
    ///   - panelProgress: Callback reporting (currentPanel, totalPanels).
    ///   - stepProgress: Callback reporting step-level progress within each panel.
    /// - Returns: Array of PanelOutput, one per panel in the prompt file.
    internal static func generateFromPromptFile(
        _ promptFile: PromptFile,
        model: VinetasModel,
        panelProgress: ((Int, Int) -> Void)? = nil,
        stepProgress: StepProgressCallback? = nil
    ) async throws -> [PanelOutput] {
        guard !promptFile.panels.isEmpty else { return [] }

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
        log("Project: \(promptFile.project.title)")

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

        // 5. Load project-level LoRA if configured
        let projectStyle = promptFile.resolvedStyle(for: 0)
        var activationKeyword: String? = nil
        if projectStyle.loraPath != nil {
            activationKeyword = try VinetasLoRAManager.loadIfConfigured(
                style: projectStyle,
                on: pipeline
            )
        }

        // 6. Iterate panels sequentially
        var outputs: [PanelOutput] = []
        let totalPanels = promptFile.panels.count

        for index in 0..<totalPanels {
            panelProgress?(index + 1, totalPanels)

            let panel = promptFile.panels[index]
            let panelStyle = promptFile.resolvedStyle(for: index)

            // Check if this panel has a different LoRA than what's loaded
            if panelStyle.loraPath != projectStyle.loraPath {
                VinetasLoRAManager.unloadAll(from: pipeline)
                if panelStyle.loraPath != nil {
                    activationKeyword = try VinetasLoRAManager.loadIfConfigured(
                        style: panelStyle,
                        on: pipeline
                    )
                } else {
                    activationKeyword = nil
                }
            }

            // Compose prompt: activation keyword + style + panel prompt
            var composedPrompt = ""
            if let keyword = activationKeyword, !keyword.isEmpty {
                composedPrompt += "\(keyword), "
            }
            if !panelStyle.stylePrompt.isEmpty {
                composedPrompt += "\(panelStyle.stylePrompt), "
            }
            composedPrompt += panel.prompt

            // Resolve seed
            let resolvedSeed: UInt64
            if let userSeed = panelStyle.seed {
                resolvedSeed = userSeed
            } else {
                resolvedSeed = UInt64.random(in: 0...UInt64.max)
            }

            // Measure generation time
            let clock = ContinuousClock()
            let startTime = clock.now

            log("Generating panel \(index + 1)/\(totalPanels): \(panelStyle.width)x\(panelStyle.height), \(panelStyle.steps) steps, seed \(resolvedSeed)")

            let result: Flux2GenerationResult
            do {
                result = try await pipeline.generateTextToImageWithResult(
                    prompt: composedPrompt,
                    height: panelStyle.height,
                    width: panelStyle.width,
                    steps: panelStyle.steps,
                    guidance: panelStyle.guidanceScale,
                    seed: resolvedSeed,
                    onProgress: { currentStep, totalSteps in
                        let elapsed = Double((clock.now - startTime).components.seconds)
                            + Double((clock.now - startTime).components.attoseconds) / 1e18
                        stepProgress?(currentStep, totalSteps, elapsed)
                        log("Panel \(index + 1) — Step \(currentStep)/\(totalSteps)")
                    }
                )
            } catch {
                throw VinetasError.generationFailed(
                    "Panel \(index + 1) generation failed: \(error.localizedDescription)"
                )
            }

            let elapsed = clock.now - startTime
            let durationSeconds = Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18

            log("Panel \(index + 1) complete in \(String(format: "%.1f", durationSeconds))s")

            let output = PanelOutput(
                image: result.image,
                prompt: composedPrompt,
                seed: resolvedSeed,
                durationSeconds: durationSeconds,
                model: model,
                width: panelStyle.width,
                height: panelStyle.height
            )
            outputs.append(output)
        }

        // 7. Clean up LoRAs
        VinetasLoRAManager.unloadAll(from: pipeline)

        return outputs
    }
}

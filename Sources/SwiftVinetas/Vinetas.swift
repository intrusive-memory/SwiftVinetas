import CoreGraphics
import Flux2Core
import Foundation
import SwiftAcervo

// MARK: - VinetasClient

/// The primary public API for SwiftVinetas.
///
/// `VinetasClient` routes all generation, model management, and engine queries
/// through an ``EngineRouter``. Use the ``shared`` singleton for production
/// or inject a custom router via ``init(router:)`` for testing.
///
/// ```swift
/// // Production usage
/// let image = try await VinetasClient.shared.generate(prompt: "A sunset over the ocean")
///
/// // Testing with a mock engine
/// let router = EngineRouter(engines: [mockEngine])
/// let client = VinetasClient(router: router)
/// ```
public final class VinetasClient: Sendable {

  /// The shared singleton instance, pre-configured with all available engines.
  public static let shared = VinetasClient()

  /// The engine router used to dispatch generation requests.
  public let router: EngineRouter

  /// The current SwiftVinetas library version.
  public static let version = "0.5.0"

  /// Default initializer that registers all available engines.
  ///
  /// Registers ``Flux2Engine`` unconditionally. Registers ``PixArtEngine``
  /// only when `PixArtCore` is importable.
  public init() {
    var engines: [any ImageGenerationEngine] = [Flux2Engine()]
    #if canImport(PixArtCore)
    engines.append(PixArtEngine())
    #endif
    self.router = EngineRouter(engines: engines)
  }

  /// Test initializer that accepts a custom router.
  ///
  /// Use this to inject a ``MockEngine`` or other test doubles.
  ///
  /// - Parameter router: The engine router to use for dispatch.
  public init(router: EngineRouter) {
    self.router = router
  }
}

// MARK: - Generation

extension VinetasClient {

  /// Generate a single panel image from a text prompt.
  ///
  /// Resolves the engine via the router, composes the prompt from style and panel
  /// prompts, builds a ``GenerationRequest`` from the style config, calls
  /// `engine.generate(request:stepProgress:)`, and returns the generated image.
  ///
  /// - Parameters:
  ///   - prompt: Text description of the panel to generate.
  ///   - style: Optional style configuration for consistent look across panels.
  ///   - model: The model descriptor to use (default: ``defaultModel``).
  /// - Returns: The generated image as a `CGImage`.
  /// - Throws: ``VinetasError/engineNotFound(engineID:)`` if the engine is unavailable,
  ///           ``VinetasError/generationFailed(_:)`` if image generation fails.
  public func generate(
    prompt: String,
    style: StyleConfig? = nil,
    model: any ModelDescriptor = VinetasClient.defaultModel
  ) async throws -> CGImage {
    let effectiveStyle = style ?? StyleConfig()
    let engine = try await router.engine(for: model)
    let composedPrompt = composePrompt(panelPrompt: prompt, style: effectiveStyle)
    let request = buildRequest(
      prompt: composedPrompt,
      style: effectiveStyle,
      mode: .textToImage
    )
    try await engine.loadModel(model, progress: { _ in })
    let result = try await engine.generate(request: request, stepProgress: nil)
    return result.image
  }

  /// Generate a sequence of panels from an array of prompts.
  ///
  /// Iterates panels calling the engine per-panel. If `referenceImages` are
  /// provided, uses image-to-image generation for character consistency.
  ///
  /// - Parameters:
  ///   - prompts: Ordered text descriptions for each panel.
  ///   - referenceImages: Optional reference images for character consistency.
  ///   - style: Optional style configuration applied to all panels.
  ///   - model: The model descriptor to use (default: ``defaultModel``).
  ///   - progress: Callback reporting (currentPanel, totalPanels).
  ///   - stepProgress: Callback reporting step-level progress per panel.
  /// - Returns: Array of `CGImage` values, one per prompt.
  public func generateSequence(
    prompts: [String],
    referenceImages: [CGImage]? = nil,
    style: StyleConfig? = nil,
    model: any ModelDescriptor = VinetasClient.defaultModel,
    progress: ((Int, Int) -> Void)? = nil,
    stepProgress: (
      @Sendable (_ currentStep: Int, _ totalSteps: Int, _ elapsed: TimeInterval) -> Void
    )? = nil
  ) async throws -> [CGImage] {
    guard !prompts.isEmpty else { return [] }

    let effectiveStyle = style ?? StyleConfig()
    let engine = try await router.engine(for: model)
    try await engine.loadModel(model, progress: { _ in })

    let useImageToImage = referenceImages.map { !$0.isEmpty } ?? false
    let totalPanels = prompts.count
    var images: [CGImage] = []

    for (index, prompt) in prompts.enumerated() {
      progress?(index + 1, totalPanels)

      let composedPrompt = composePrompt(panelPrompt: prompt, style: effectiveStyle)
      let mode: GenerationRequest.GenerationMode =
        useImageToImage
        ? .imageToImage(references: referenceImages!)
        : .textToImage
      let request = buildRequest(
        prompt: composedPrompt,
        style: effectiveStyle,
        mode: mode
      )
      let result = try await engine.generate(request: request, stepProgress: stepProgress)
      images.append(result.image)
    }

    return images
  }

  /// Generate a single panel image with character LoRA and trigger word injection.
  ///
  /// Checks LoRA compatibility against the selected engine: if the character's
  /// trained LoRA engine matches (via `compatibleEngines` when available, or
  /// `model` field otherwise), loads the LoRA before generation and unloads it
  /// after. If the LoRA is incompatible with the engine, proceeds with
  /// prompt-only consistency and logs a warning.
  ///
  /// - Parameters:
  ///   - prompt: Text description of the panel to generate.
  ///   - character: The character whose LoRA and trigger word to apply.
  ///   - style: Optional style configuration.
  ///   - model: The model descriptor to use (default: ``defaultModel``).
  /// - Returns: The generated image as a `CGImage`.
  public func generate(
    prompt: String,
    character: Character,
    style: StyleConfig? = nil,
    model: any ModelDescriptor = VinetasClient.defaultModel
  ) async throws -> CGImage {
    let effectiveStyle = style ?? StyleConfig()
    let engine = try await router.engine(for: model)
    try await engine.loadModel(model, progress: { _ in })

    // Determine whether LoRA is compatible with this engine
    var loraLoaded = false
    if let lora = character.lora {
      let compatible = isLoRACompatible(lora: lora, engineID: engine.engineID)
      if compatible && engine.supports(.loraInference) {
        let manager = CharacterManager()
        let charDir = manager.characterDirectory(slug: character.slug)
        let loraURL = charDir.appendingPathComponent(lora.path)
        try await engine.loadLoRA(at: loraURL, scale: lora.scale)
        loraLoaded = true
      } else {
        let warning =
          "[SwiftVinetas] LoRA for '\(character.name)' is incompatible with engine '\(engine.engineID)'. "
          + "Proceeding with prompt-only consistency.\n"
        if let data = warning.data(using: .utf8) {
          FileHandle.standardError.write(data)
        }
      }
    }

    // Compose prompt: trigger word + style + panel prompt
    let composedPrompt = composeCharacterPrompt(
      panelPrompt: prompt,
      character: character,
      style: effectiveStyle
    )
    let request = buildRequest(
      prompt: composedPrompt,
      style: effectiveStyle,
      mode: .textToImage
    )
    let result = try await engine.generate(request: request, stepProgress: nil)

    // Unload LoRA to prevent bleeding into subsequent generations
    if loraLoaded {
      await engine.unloadLoRA()
    }

    return result.image
  }

  /// Generate a fast, low-quality preview image for rapid prompt iteration.
  ///
  /// FLUX.2-only fast path — forces Klein 4B, 4 inference steps, and 512x512
  /// output for quick turnaround. Resolves directly to the `"flux2"` engine
  /// via ``EngineRouter/engine(forEngineID:)``.
  ///
  /// - Parameter prompt: Text description of the panel to preview.
  /// - Returns: The generated image as a `CGImage` at 512x512.
  public func preview(prompt: String) async throws -> CGImage {
    let previewModel = Flux2ModelDescriptor.klein4B
    let engine = try await router.engine(forEngineID: "flux2")
    try await engine.loadModel(previewModel, progress: { _ in })
    let request = GenerationRequest(
      prompt: prompt,
      steps: 4,
      guidanceScale: previewModel.defaultGuidance,
      width: 512,
      height: 512,
      mode: .textToImage
    )
    let result = try await engine.generate(request: request, stepProgress: nil)
    return result.image
  }
}

// MARK: - Model Management

extension VinetasClient {

  /// Download a model, delegating through the engine router.
  ///
  /// Resolves the engine for the given model descriptor and delegates the
  /// download to `engine.download(_:progress:)`.
  ///
  /// - Parameters:
  ///   - model: The model descriptor to download.
  ///   - progress: Optional callback reporting download progress.
  public func download(
    model: any ModelDescriptor,
    progress: (@Sendable (VinetasDownloadProgress) -> Void)? = nil
  ) async throws {
    let engine = try await router.engine(for: model)
    try await engine.download(model) { dp in
      progress?(VinetasDownloadProgress(overallProgress: dp.fraction, message: dp.message))
    }
  }

  /// Check whether a model is available on disk, via the engine router.
  ///
  /// - Parameter model: The model descriptor to check.
  /// - Returns: `true` if the model's weights are downloaded and ready.
  public func isAvailable(_ model: any ModelDescriptor) async throws -> Bool {
    let engine = try await router.engine(for: model)
    return engine.isAvailable(model)
  }

  /// Delete a model's weights from local storage, via the engine router.
  ///
  /// - Parameter model: The model descriptor to delete.
  public func delete(_ model: any ModelDescriptor) async throws {
    let engine = try await router.engine(for: model)
    try await engine.delete(model)
  }

  /// List all known models across all registered engines with availability status.
  ///
  /// - Returns: An array of ``VinetasModelInfo``, one per known model.
  public func listModels() async -> [VinetasModelInfo] {
    let models = await router.allModels
    return models.map { model in
      VinetasModelInfo(
        name: model.displayName,
        size: 0,
        downloadDate: nil,
        isDownloaded: false
      )
    }
  }

  /// Validate whether the system has sufficient memory for a model.
  ///
  /// Delegates to `engine.validateMemory(for:)`.
  ///
  /// - Parameter model: The model descriptor to validate.
  /// - Returns: A ``MemoryValidation`` result.
  public func validateMemory(for model: any ModelDescriptor) async throws -> MemoryValidation {
    let engine = try await router.engine(for: model)
    return engine.validateMemory(for: model)
  }
}

// MARK: - Private Prompt Helpers

extension VinetasClient {

  /// Compose a prompt from style config and panel prompt.
  ///
  /// Format: `"<stylePrompt>, <panelPrompt>"` (style omitted if empty).
  private func composePrompt(panelPrompt: String, style: StyleConfig) -> String {
    if style.stylePrompt.isEmpty {
      return panelPrompt
    }
    return "\(style.stylePrompt), \(panelPrompt)"
  }

  /// Compose a character-aware prompt.
  ///
  /// Format: `"<triggerWord>, <stylePrompt>, <panelPrompt>"` (each part omitted if empty).
  private func composeCharacterPrompt(
    panelPrompt: String,
    character: Character,
    style: StyleConfig
  ) -> String {
    var parts: [String] = []
    if !character.triggerWord.isEmpty {
      parts.append(character.triggerWord)
    }
    if !style.stylePrompt.isEmpty {
      parts.append(style.stylePrompt)
    }
    parts.append(panelPrompt)
    return parts.joined(separator: ", ")
  }

  /// Build a ``GenerationRequest`` from a composed prompt and style config.
  private func buildRequest(
    prompt: String,
    style: StyleConfig,
    mode: GenerationRequest.GenerationMode
  ) -> GenerationRequest {
    GenerationRequest(
      prompt: prompt,
      negativePrompt: style.negativePrompt,
      steps: style.steps,
      guidanceScale: style.guidanceScale,
      seed: style.seed,
      width: style.width,
      height: style.height,
      mode: mode
    )
  }

  /// Check whether a character LoRA is compatible with a given engine.
  ///
  /// If `compatibleEngines` is empty (no restriction recorded), assumes compatible.
  /// Otherwise, checks that the given `engineID` is listed in `compatibleEngines`.
  private func isLoRACompatible(lora: LoRAMetadata, engineID: String) -> Bool {
    guard !lora.compatibleEngines.isEmpty else {
      // No compatibility restriction recorded — assume compatible
      return true
    }
    return lora.compatibleEngines.contains(engineID)
  }
}

// MARK: - Convenience Model Accessors

extension VinetasClient {

  /// The default model for generation. Currently FLUX.2 Klein 4B.
  public static var defaultModel: any ModelDescriptor { Flux2ModelDescriptor.klein4B }

  /// FLUX.2 Klein 4B model descriptor.
  public static var klein4B: any ModelDescriptor { Flux2ModelDescriptor.klein4B }

  /// FLUX.2 Klein 9B model descriptor.
  public static var klein9B: any ModelDescriptor { Flux2ModelDescriptor.klein9B }

  /// PixArt-Sigma XL model descriptor.
  public static var pixartSigmaXL: any ModelDescriptor { PixArtModelDescriptor.sigmaXL }
}

// MARK: - Deprecated Vinetas Enum

/// SwiftVinetas - Storyboard and comic panel generation from text prompts.
///
/// Generates sequential visual panels from text descriptions using
/// FLUX.2 Klein models on Apple Silicon via MLX.
///
/// - Important: Use ``VinetasClient/shared`` instead. This enum is preserved
///   for backward compatibility and will be removed in a future release.
@available(*, deprecated, message: "Use VinetasClient.shared instead")
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

    // MARK: - Understanding

    /// Classify an image using ViT-B/16 and return top-K predictions.
    ///
    /// Downloads model weights on the first call (idempotent). Subsequent calls
    /// reuse the cached model loaded in memory.
    ///
    /// - Parameters:
    ///   - image: The CGImage to classify.
    ///   - topK: Maximum number of classifications to return (default 5).
    /// - Returns: Array of `Classification` sorted by confidence, highest first.
    /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
    ///           `VinetasError.generationFailed` for runtime errors.
    public static func classify(
        image: CGImage,
        topK: Int = 5
    ) async throws -> [Classification] {
        try await ImageClassifier.shared.classify(image: image, topK: topK)
    }

    /// Classify an image loaded from a file URL using ViT-B/16.
    ///
    /// - Parameters:
    ///   - file: File URL to the image (JPEG, PNG, HEIC, etc.).
    ///   - topK: Maximum number of classifications to return (default 5).
    /// - Returns: Array of `Classification` sorted by confidence, highest first.
    /// - Throws: `VinetasError.generationFailed` if the image cannot be loaded,
    ///           plus any errors from `classify(image:topK:)`.
    public static func classify(
        file: URL,
        topK: Int = 5
    ) async throws -> [Classification] {
        try await ImageClassifier.shared.classify(file: file, topK: topK)
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

    // MARK: - Character Pipeline

    /// Create a new character with directory structure and optional source photo.
    ///
    /// Sets up `~/Library/SwiftVinetas/characters/<slug>/` with `source/`,
    /// `references/`, `training/`, and `lora/` subdirectories, writes a
    /// `character.yaml` manifest, and optionally saves the source photo as PNG.
    ///
    /// - Parameters:
    ///   - name: Human-readable character name (e.g., "Detective Vale").
    ///   - photo: Optional source photograph. Written to `source/<slug>-photo-01.png`.
    ///   - slug: Optional slug; derived from `name` if omitted (e.g., "detective-vale").
    ///   - description: Plain-text description of the character's appearance.
    /// - Returns: The newly created `Character` value.
    /// - Throws: File I/O or serialization errors.
    public static func createCharacter(
        name: String,
        photo: CGImage? = nil,
        slug: String? = nil,
        description: String = ""
    ) throws -> Character {
        let manager = CharacterManager()
        return try manager.createCharacter(
            name: name,
            photo: photo,
            slug: slug,
            description: description
        )
    }

    /// List all characters stored under `~/Library/SwiftVinetas/characters/`.
    ///
    /// Characters with a missing or malformed `character.yaml` are silently skipped.
    ///
    /// - Returns: Array of `Character` values sorted by name.
    /// - Throws: File I/O errors reading the characters directory.
    public static func listCharacters() throws -> [Character] {
        try CharacterManager().listCharacters()
    }

    /// Load a character by slug from `~/Library/SwiftVinetas/characters/<slug>/`.
    ///
    /// - Parameter slug: The character's slug identifier (e.g., "detective-vale").
    /// - Returns: The decoded `Character`.
    /// - Throws: File I/O or YAML decoding errors.
    public static func loadCharacter(slug: String) throws -> Character {
        try CharacterManager().loadCharacter(slug: slug)
    }
}

// MARK: - Deprecated VinetasModel Enum

/// Available FLUX.2 model variants.
public enum VinetasModel: String, Sendable, Codable, CaseIterable {
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

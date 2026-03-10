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

    // MARK: - Feature Extraction

    /// Extract a 768-dimensional feature vector from an image using DINOv2-B/14.
    ///
    /// Downloads model weights on the first call (idempotent). Subsequent calls
    /// reuse the cached model loaded in memory.
    ///
    /// - Parameter image: The CGImage to extract features from.
    /// - Returns: Array of 768 Float values representing the CLS token embedding.
    /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
    ///           `VinetasError.generationFailed` for runtime errors.
    public static func extractFeatures(from image: CGImage) async throws -> [Float] {
        try await FeatureExtractor.shared.extractFeatures(from: image)
    }

    /// Extract a 768-dimensional feature vector from an image loaded from a file URL.
    ///
    /// - Parameter url: File URL to the image (JPEG, PNG, HEIC, etc.).
    /// - Returns: Array of 768 Float values representing the CLS token embedding.
    /// - Throws: `VinetasError.generationFailed` if the image cannot be loaded,
    ///           plus any errors from `extractFeatures(from:)`.
    public static func extractFeatures(from url: URL) async throws -> [Float] {
        try await FeatureExtractor.shared.extractFeatures(from: url)
    }

    /// Compute the cosine similarity between two images using DINOv2-B/14 features.
    ///
    /// Downloads model weights on the first call (idempotent). Extracts feature vectors
    /// from both images and returns their cosine similarity.
    ///
    /// - Parameters:
    ///   - image1: The first CGImage.
    ///   - image2: The second CGImage.
    /// - Returns: Cosine similarity in the range `[-1, 1]`.
    /// - Throws: `VinetasError.downloadFailed` if weights cannot be fetched,
    ///           `VinetasError.generationFailed` for runtime errors.
    public static func similarity(between image1: CGImage, and image2: CGImage) async throws -> Float {
        let features1 = try await FeatureExtractor.shared.extractFeatures(from: image1)
        let features2 = try await FeatureExtractor.shared.extractFeatures(from: image2)
        return cosineSimilarity(features1, features2)
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

    // MARK: - Reference Sheet Generation

    /// Generate pencil-sketch turnaround reference sheets from a character's source photo.
    ///
    /// Loads the first source photo from the character's directory, then uses FLUX.2
    /// img2img to generate pencil-sketch reference views at each requested angle.
    /// Generated images are saved to `characters/<slug>/references/<view>.png`.
    ///
    /// - Parameters:
    ///   - character: The character to generate reference sheets for. Must have at least
    ///     one entry in `sourcePhotos`.
    ///   - views: The turnaround angles to render (default: all four canonical views).
    ///   - strength: How much to deviate from the source photo (0.0-1.0). Default: 0.65.
    ///   - model: The FLUX.2 model variant to use (default: Klein 4B).
    ///   - progress: Optional callback reporting `(currentView, totalViews)`.
    /// - Returns: Array of generated CGImages, one per requested view.
    /// - Throws: `VinetasError.generationFailed` if the character has no source photos or
    ///           the photo cannot be loaded, `VinetasError.insufficientMemory` if system
    ///           RAM is too low for the selected model.
    public static func generateReferenceSheets(
        for character: Character,
        views: [ReferenceView] = ReferenceView.allCases.map { $0 },
        strength: Float = 0.65,
        model: VinetasModel = .klein4b,
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [CGImage] {
        guard let firstPhoto = character.sourcePhotos.first else {
            throw VinetasError.generationFailed(
                "Character '\(character.name)' has no source photos. "
                    + "Add a source photo with createCharacter(name:photo:)."
            )
        }

        let manager = CharacterManager()
        let photoURL = manager.characterDirectory(slug: character.slug)
            .appendingPathComponent(firstPhoto)

        guard let dataProvider = CGDataProvider(url: photoURL as CFURL),
            let sourceImage = CGImage(
                pngDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
            )
        else {
            throw VinetasError.generationFailed(
                "Could not load source photo at \(photoURL.path)"
            )
        }

        return try await ReferenceSheetGenerator.generate(
            for: character,
            views: views,
            sourceImage: sourceImage,
            strength: strength,
            model: model,
            progress: progress
        )
    }

    // MARK: - LoRA Training

    /// Train a LoRA adapter for a character using on-device FLUX.2 fine-tuning.
    ///
    /// Loads the character's training data (image/caption pairs from `training/`),
    /// validates system memory, runs LoRA training via Flux2Core, and saves the
    /// resulting `.safetensors` file to `characters/<slug>/lora/<slug>-v<N>.safetensors`
    /// with auto-incrementing version numbers.
    ///
    /// After training completes, the character's `lora` metadata is updated and
    /// the manifest is re-saved.
    ///
    /// **Prerequisites**: Call `prepareTrainingData(for:)` before training to
    /// populate the `training/` directory.
    ///
    /// **Memory**: Klein 4B nf4 requires minimum 8 GB system RAM for training.
    ///
    /// - Parameters:
    ///   - character: The character to train a LoRA for.
    ///   - config: Training hyperparameters (default: rank 48, 1500 steps, nf4).
    ///   - model: The FLUX.2 model variant to train against (default: Klein 4B).
    ///   - progress: Optional callback reporting `(currentStep, totalSteps, loss)`.
    /// - Returns: The URL of the saved `.safetensors` file.
    /// - Throws: `VinetasError.insufficientMemory` if system RAM is too low,
    ///           `VinetasError.generationFailed` if training data is missing.
    public static func trainCharacterLoRA(
        for character: Character,
        config: TrainingConfig = TrainingConfig(),
        model: VinetasModel = .klein4b,
        progress: ((Int, Int, Float) -> Void)? = nil
    ) async throws -> URL {
        let manager = CharacterManager()
        let characterDir = manager.characterDirectory(slug: character.slug)
        let trainer = CharacterTrainer()

        let outputURL = try await trainer.train(
            character: character,
            config: config,
            model: model,
            characterDirectory: characterDir,
            progress: progress
        )

        // Update character manifest with new LoRA metadata
        let loraDir = characterDir.appendingPathComponent("lora", isDirectory: true)
        let version = trainer.nextVersion(slug: character.slug, in: loraDir) - 1
        let relativePath = "lora/\(outputURL.lastPathComponent)"

        var updatedCharacter = character
        updatedCharacter.lora = LoRAMetadata(
            path: relativePath,
            scale: 0.8,
            version: version,
            trainedAt: Date(),
            trainingSteps: config.steps,
            model: model
        )
        try manager.saveCharacter(updatedCharacter)

        return outputURL
    }

    // MARK: - Training Data Preparation

    /// Prepare a training dataset for LoRA fine-tuning from a character's reference sheets.
    ///
    /// Scans the character's `references/` directory for generated reference images
    /// (front.png, left.png, right.png, back.png), resizes each to VAE-compatible
    /// dimensions (divisible by 16), and creates matching caption text files in
    /// `training/`. Optionally includes the character's source photos as well.
    ///
    /// - Parameters:
    ///   - character: The character whose training data to prepare.
    ///   - includeSourcePhotos: Whether to include the character's source photos
    ///     in addition to reference sheets. Default: `false`.
    /// - Returns: Array of `TrainingDataPreparer.TrainingPair`, one per processed image.
    /// - Throws: File I/O or image processing errors.
    public static func prepareTrainingData(
        for character: Character,
        includeSourcePhotos: Bool = false
    ) throws -> [TrainingDataPreparer.TrainingPair] {
        let manager = CharacterManager()
        let characterDir = manager.characterDirectory(slug: character.slug)
        let preparer = TrainingDataPreparer()
        return try preparer.prepare(
            for: character,
            includeSourcePhotos: includeSourcePhotos,
            characterDirectory: characterDir
        )
    }
}

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

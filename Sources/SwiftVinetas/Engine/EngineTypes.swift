import CoreGraphics
import Foundation

// MARK: - GenerationRequest

/// A fully-composed generation request passed to an engine.
///
/// The engine receives a flat request with a single composed `prompt: String`
/// rather than structured fields (trigger word, style prompt, panel prompt).
/// This keeps the engine ignorant of upstream prompt semantics.
/// SwiftVinetas composes the prompt; the engine renders it.
public struct GenerationRequest: Sendable {

    /// The fully-composed prompt string.
    public var prompt: String

    /// An optional negative prompt for models that support classifier-free guidance.
    public var negativePrompt: String?

    /// Number of inference steps.
    public var steps: Int

    /// Classifier-free guidance scale.
    public var guidanceScale: Float

    /// Optional seed for reproducible generation. Nil means random.
    public var seed: UInt64?

    /// Output width in pixels.
    public var width: Int

    /// Output height in pixels.
    public var height: Int

    /// The generation mode (text-to-image or image-to-image).
    public var mode: GenerationMode

    /// Creates a new generation request.
    ///
    /// - Parameters:
    ///   - prompt: The fully-composed prompt string.
    ///   - negativePrompt: Optional negative prompt.
    ///   - steps: Number of inference steps.
    ///   - guidanceScale: Classifier-free guidance scale.
    ///   - seed: Optional seed for reproducibility.
    ///   - width: Output width in pixels.
    ///   - height: Output height in pixels.
    ///   - mode: The generation mode.
    public init(
        prompt: String,
        negativePrompt: String? = nil,
        steps: Int,
        guidanceScale: Float,
        seed: UInt64? = nil,
        width: Int,
        height: Int,
        mode: GenerationMode = .textToImage
    ) {
        self.prompt = prompt
        self.negativePrompt = negativePrompt
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.width = width
        self.height = height
        self.mode = mode
    }

    // MARK: - GenerationMode

    /// The mode of image generation.
    public enum GenerationMode: Sendable {
        /// Generate an image purely from a text prompt.
        case textToImage

        /// Generate an image conditioned on one or more reference images.
        case imageToImage(references: [CGImage])
    }
}

// MARK: - GenerationResult

/// The result of a successful image generation.
public struct GenerationResult: Sendable {

    /// The generated image.
    public var image: CGImage

    /// The prompt that was actually used for generation.
    public var usedPrompt: String

    /// The seed used for this generation (for reproducibility).
    public var seed: UInt64

    /// Wall-clock duration of the generation in seconds.
    public var durationSeconds: Double

    /// Identifier of the model used for generation.
    public var modelID: String

    /// Creates a new generation result.
    ///
    /// - Parameters:
    ///   - image: The generated image.
    ///   - usedPrompt: The prompt used for generation.
    ///   - seed: The seed used.
    ///   - durationSeconds: Wall-clock generation duration.
    ///   - modelID: Identifier of the model used.
    public init(
        image: CGImage,
        usedPrompt: String,
        seed: UInt64,
        durationSeconds: Double,
        modelID: String
    ) {
        self.image = image
        self.usedPrompt = usedPrompt
        self.seed = seed
        self.durationSeconds = durationSeconds
        self.modelID = modelID
    }
}

// MARK: - DownloadProgress

/// Progress information during model weight download.
public struct DownloadProgress: Sendable {

    /// Download fraction completed (0.0 to 1.0).
    public var fraction: Double

    /// Human-readable progress message.
    public var message: String

    /// Creates a new download progress value.
    ///
    /// - Parameters:
    ///   - fraction: Download fraction completed (0.0 to 1.0).
    ///   - message: Human-readable progress message.
    public init(fraction: Double, message: String) {
        self.fraction = fraction
        self.message = message
    }
}

// MARK: - LoadProgress

/// Progress information during model loading into memory.
public struct LoadProgress: Sendable {

    /// Current loading phase (e.g., "Loading text encoder", "Loading transformer").
    public var phase: String

    /// Load fraction completed for the current phase (0.0 to 1.0).
    public var fraction: Double

    /// Creates a new load progress value.
    ///
    /// - Parameters:
    ///   - phase: Current loading phase description.
    ///   - fraction: Load fraction completed (0.0 to 1.0).
    public init(phase: String, fraction: Double) {
        self.phase = phase
        self.fraction = fraction
    }
}

// MARK: - MemoryValidation

/// Result of validating whether the system has enough memory to run a model.
public enum MemoryValidation: Sendable {
    /// System memory is sufficient to run the model.
    case ok

    /// System memory may be marginal; generation might work but could be slow.
    case warning(message: String)

    /// System memory is insufficient to run the model.
    case insufficient(required: UInt64, available: UInt64)
}

// MARK: - EngineFeature

/// Features that an engine may or may not support.
///
/// Use ``ImageGenerationEngine/supports(_:)`` to check whether a specific
/// engine supports a given feature before attempting to use it.
public enum EngineFeature: Sendable, Hashable {
    /// Text-to-image generation from a prompt.
    case textToImage

    /// Image-to-image generation conditioned on reference images,
    /// with a maximum number of reference images.
    case imageToImage(maxReferenceImages: Int)

    /// LoRA adapter inference (applying a pre-trained LoRA at generation time).
    case loraInference

    /// LoRA adapter training (fine-tuning a LoRA on new data).
    case loraTraining

    /// Prompt upsampling (engine-side prompt enhancement).
    case promptUpsampling
}

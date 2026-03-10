import Foundation

/// Configuration for consistent visual style across generated panels.
public struct StyleConfig: Codable, Sendable {
    /// A description of the desired art style (e.g., "noir comic", "manga", "watercolor storyboard").
    public var stylePrompt: String

    /// Negative prompt to steer away from unwanted characteristics.
    public var negativePrompt: String?

    /// Number of inference steps (higher = more detail, slower).
    public var steps: Int

    /// Guidance scale for classifier-free guidance.
    public var guidanceScale: Float

    /// Random seed for reproducibility. Nil for random.
    public var seed: UInt64?

    /// Output image width in pixels.
    public var width: Int

    /// Output image height in pixels.
    public var height: Int

    /// Optional path to a LoRA safetensors file to apply during generation.
    public var loraPath: String?

    /// Scale for the LoRA adapter (0.0–1.0). Defaults to nil (uses LoRA default of 1.0).
    public var loraScale: Float?

    public init(
        stylePrompt: String = "",
        negativePrompt: String? = nil,
        steps: Int = 20,
        guidanceScale: Float = 3.5,
        seed: UInt64? = nil,
        width: Int = 1024,
        height: Int = 1024,
        loraPath: String? = nil,
        loraScale: Float? = nil
    ) {
        self.stylePrompt = stylePrompt
        self.negativePrompt = negativePrompt
        self.steps = steps
        self.guidanceScale = guidanceScale
        self.seed = seed
        self.width = width
        self.height = height
        self.loraPath = loraPath
        self.loraScale = loraScale
    }
}

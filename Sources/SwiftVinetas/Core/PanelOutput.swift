import CoreGraphics
import Foundation

/// Output from a single panel generation, including the image and metadata.
public struct PanelOutput: Sendable {
  /// The generated image.
  public let image: CGImage

  /// The prompt used to generate this panel.
  public let prompt: String

  /// The seed used (for reproducibility).
  public let seed: UInt64

  /// Generation duration in seconds.
  public let durationSeconds: Double

  /// Model used for generation.
  public let model: VinetasModel

  /// Image dimensions.
  public let width: Int
  public let height: Int

  public init(
    image: CGImage,
    prompt: String,
    seed: UInt64,
    durationSeconds: Double,
    model: VinetasModel,
    width: Int,
    height: Int
  ) {
    self.image = image
    self.prompt = prompt
    self.seed = seed
    self.durationSeconds = durationSeconds
    self.model = model
    self.width = width
    self.height = height
  }
}

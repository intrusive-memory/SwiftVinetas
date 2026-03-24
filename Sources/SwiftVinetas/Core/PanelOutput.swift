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

  /// The model ID used for generation (e.g., "flux2-klein-4b", "klein4b").
  public let modelID: String

  /// Image dimensions.
  public let width: Int
  public let height: Int

  public init(
    image: CGImage,
    prompt: String,
    seed: UInt64,
    durationSeconds: Double,
    modelID: String,
    width: Int,
    height: Int
  ) {
    self.image = image
    self.prompt = prompt
    self.seed = seed
    self.durationSeconds = durationSeconds
    self.modelID = modelID
    self.width = width
    self.height = height
  }

  // MARK: - Deprecated Compatibility

  /// Backward-compatible accessor for the model enum.
  ///
  /// Returns `nil` if the `modelID` does not correspond to a known `VinetasModel` case.
  @available(*, deprecated, message: "Use modelID instead")
  public var model: VinetasModel? {
    VinetasModel(rawValue: modelID)
  }

  /// Backward-compatible initializer accepting `VinetasModel`.
  @available(
    *, deprecated,
    message: "Use init(image:prompt:seed:durationSeconds:modelID:width:height:) instead"
  )
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
    self.modelID = model.rawValue
    self.width = width
    self.height = height
  }
}

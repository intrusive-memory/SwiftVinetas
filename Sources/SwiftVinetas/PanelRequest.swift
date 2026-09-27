import CoreGraphics
import Foundation

/// A single-panel generation request for ``VinetasClient/generate(_:)``.
///
/// With no `references` the panel is generated text-to-image. With one or
/// more references it is generated image-to-image; there is no silent
/// fallback to text-to-image when the engine cannot accept them — validation
/// throws before any model is loaded.
public struct PanelRequest: Sendable {

  /// The user's panel prompt (before style composition).
  public var prompt: String

  /// Style configuration (steps, guidance, size, seed, negative prompt, ...).
  public var style: StyleConfig

  /// The model to generate with.
  public var model: any ModelDescriptor

  /// Reference (conditioning) images, in the order supplied.
  public var references: [ReferenceImage]

  public init(
    prompt: String,
    style: StyleConfig = StyleConfig(),
    model: any ModelDescriptor = VinetasClient.defaultModel,
    references: [ReferenceImage] = []
  ) {
    self.prompt = prompt
    self.style = style
    self.model = model
    self.references = references
  }
}

/// The result of ``VinetasClient/generate(_:)``: the image plus the provenance
/// metadata describing exactly how it was produced.
public struct GeneratedPanel: Sendable {

  /// The generated image.
  public let image: CGImage

  /// What was actually used: actual seed, effective size, mode, references,
  /// negative-prompt handling, and so on.
  public let metadata: ImageOutput.PanelMetadata

  public init(image: CGImage, metadata: ImageOutput.PanelMetadata) {
    self.image = image
    self.metadata = metadata
  }
}

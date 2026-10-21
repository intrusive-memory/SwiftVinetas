import CoreGraphics
import Foundation
import GlosaCore

/// A single-panel generation request for ``VinetasClient/generate(_:characters:stepProgress:)``.
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

  /// The character the panel depicts, if any.
  ///
  /// On an engine that can apply the character's trained LoRA, the adapter
  /// is loaded and its trigger word prepended. Otherwise the character's
  /// description is composed into the prompt and, on a cloud engine with no
  /// explicit `references`, its reference sheets and photos are attached.
  public var character: Character?

  /// The effective GLOSA shot this panel renders; when set, the panel's
  /// metadata records it in `glosa`.
  public var shot: Shot?

  public init(
    prompt: String,
    style: StyleConfig = StyleConfig(),
    model: any ModelDescriptor = VinetasClient.defaultModel,
    references: [ReferenceImage] = [],
    character: Character? = nil,
    shot: Shot? = nil
  ) {
    self.prompt = prompt
    self.style = style
    self.model = model
    self.references = references
    self.character = character
    self.shot = shot
  }
}

/// The result of ``VinetasClient/generate(_:characters:stepProgress:)``: the image plus the provenance
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

/// A panel fully resolved by ``VinetasClient/prepare(_:characters:)``:
/// everything ``VinetasClient/generate(_:characters:stepProgress:)`` will do, decided before any model
/// loads or any vendor is contacted.
public struct PreparedPanel: Sendable {

  /// The model the panel will generate with.
  public let modelID: String

  /// The engine the model routes to.
  public let engineID: String

  /// The request the engine will receive, with ``GenerationRequest/bundle``
  /// attached.
  public let request: GenerationRequest

  /// The references that will be sent: the caller's, or the character's
  /// sheets and photos when the engine is a cloud engine that takes them.
  public let references: [ReferenceImage]

  /// The LoRA that will be applied, if any (the style's, or the
  /// character's own adapter on an engine that can apply it).
  public let lora: ImageOutput.LoRAEntry?

  /// Whether ``lora`` is the character's adapter (unloaded after the panel).
  public let isCharacterLoRA: Bool

  /// The structured description of the panel.
  public let bundle: PromptBundle

  /// The exact prompt text the engine will receive: the comma-joined prompt
  /// for an on-device engine, the rendered ``bundle`` for a cloud engine.
  public let promptSent: String
}

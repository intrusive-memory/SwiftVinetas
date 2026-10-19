// VinetasPromptDraft.swift
// VinetasUI
//
// Everything the storyboard panel editor edits, as one value a host can hold,
// bind to `VinetasPromptComposer`, and persist.

import Foundation
import VinetasVocabulary

/// The whole storyboard panel editor as one value: the prompts, an optional
/// caption, the model, and the generation settings.
///
/// ``VinetasPromptComposer`` edits a draft through one binding. "Default"
/// and "Randomize" are expressed as `nil`: a `nil` ``aspectRatio``,
/// ``steps`` or ``guidance`` means "use the selected model's default", and a
/// `nil` ``seed`` means "pick a new seed for each generation". The draft
/// never holds a model default the user did not choose; what `nil` means on
/// save is the host's decision (for example, omitting the attribute).
///
/// ## Persistence
///
/// A draft is `Codable` with stable keys: each key is the field's name
/// (`prompt`, `caption`, `stylePrompt`, `negativePrompt`, `modelID`,
/// `aspectRatio`, `steps`, `guidance`, `seed`). Hosts may persist encoded
/// drafts and expect them to decode across the next minor release's patch
/// line. `aspectRatio` is encoded as the ratio's `rawValue` string, because
/// `AspectRatio` is not itself `Codable`. A `nil` field is omitted, and a
/// missing key decodes to the field's default.
public struct VinetasPromptDraft: Hashable, Sendable, Codable {

  /// The primary prompt.
  public var prompt = ""

  /// The caption, or `nil` when there is no caption value.
  public var caption: String? = nil

  /// The style prompt: a preset's `promptText`, or free text.
  public var stylePrompt = ""

  /// The negative prompt.
  public var negativePrompt = ""

  /// The `ModelSummary.id` of the chosen model; ``model`` resolves it, and
  /// `model?.cliName` is the external name.
  public var modelID = ModelSummary.pixartSigmaXL.id

  /// The aspect ratio, or `nil` for Default: the selected model's default.
  public var aspectRatio: AspectRatio? = nil

  /// The inference steps, or `nil` for Default: the selected model's default.
  public var steps: Int? = nil

  /// The guidance scale, or `nil` for Default: the selected model's default.
  public var guidance: Float? = nil

  /// The seed, or `nil` for Randomize: a new seed for each generation.
  public var seed: UInt64? = nil

  /// Creates a draft; every parameter defaults to the value in ``empty``.
  ///
  /// - Parameters:
  ///   - prompt: The primary prompt.
  ///   - caption: The caption, or `nil` for none.
  ///   - stylePrompt: A preset's `promptText`, or free text.
  ///   - negativePrompt: The negative prompt.
  ///   - modelID: The `ModelSummary.id` of the chosen model.
  ///   - aspectRatio: The aspect ratio, or `nil` for Default.
  ///   - steps: The inference steps, or `nil` for Default.
  ///   - guidance: The guidance scale, or `nil` for Default.
  ///   - seed: The seed, or `nil` for Randomize.
  public init(
    prompt: String = "",
    caption: String? = nil,
    stylePrompt: String = "",
    negativePrompt: String = "",
    modelID: String = ModelSummary.pixartSigmaXL.id,
    aspectRatio: AspectRatio? = nil,
    steps: Int? = nil,
    guidance: Float? = nil,
    seed: UInt64? = nil
  ) {
    self.prompt = prompt
    self.caption = caption
    self.stylePrompt = stylePrompt
    self.negativePrompt = negativePrompt
    self.modelID = modelID
    self.aspectRatio = aspectRatio
    self.steps = steps
    self.guidance = guidance
    self.seed = seed
  }

  /// The shipped model whose `id` is ``modelID``, or `nil` if none matches.
  public var model: ModelSummary? {
    ModelSummary.all.first { $0.id == modelID }
  }

  /// The preset whose `promptText` is ``stylePrompt``, or `nil` for free
  /// text, the empty string and `StoryboardStyle.customTag`.
  public var style: StoryboardStyle? {
    StoryboardStyle.from(promptText: stylePrompt)
  }

  /// A draft with every field at its default: empty prompts, no caption,
  /// PixArt-Sigma XL, and Default / Randomize everywhere.
  public static let empty = VinetasPromptDraft()
}

// MARK: - Codable

extension VinetasPromptDraft {

  private enum CodingKeys: String, CodingKey {
    case prompt
    case caption
    case stylePrompt
    case negativePrompt
    case modelID
    case aspectRatio
    case steps
    case guidance
    case seed
  }

  /// Decodes a draft, reading ``aspectRatio`` as a `rawValue` string; a
  /// missing key leaves its field at the default.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = VinetasPromptDraft()
    prompt = try container.decodeIfPresent(String.self, forKey: .prompt) ?? defaults.prompt
    caption = try container.decodeIfPresent(String.self, forKey: .caption)
    stylePrompt =
      try container.decodeIfPresent(String.self, forKey: .stylePrompt) ?? defaults.stylePrompt
    negativePrompt =
      try container.decodeIfPresent(String.self, forKey: .negativePrompt)
      ?? defaults.negativePrompt
    modelID = try container.decodeIfPresent(String.self, forKey: .modelID) ?? defaults.modelID
    if let raw = try container.decodeIfPresent(String.self, forKey: .aspectRatio) {
      guard let ratio = AspectRatio(rawValue: raw) else {
        throw DecodingError.dataCorruptedError(
          forKey: .aspectRatio,
          in: container,
          debugDescription: "Unknown aspect ratio \"\(raw)\"."
        )
      }
      aspectRatio = ratio
    } else {
      aspectRatio = nil
    }
    steps = try container.decodeIfPresent(Int.self, forKey: .steps)
    guidance = try container.decodeIfPresent(Float.self, forKey: .guidance)
    seed = try container.decodeIfPresent(UInt64.self, forKey: .seed)
  }

  /// Encodes a draft, writing ``aspectRatio`` as its `rawValue` string and
  /// omitting every `nil` field.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(prompt, forKey: .prompt)
    try container.encodeIfPresent(caption, forKey: .caption)
    try container.encode(stylePrompt, forKey: .stylePrompt)
    try container.encode(negativePrompt, forKey: .negativePrompt)
    try container.encode(modelID, forKey: .modelID)
    try container.encodeIfPresent(aspectRatio?.rawValue, forKey: .aspectRatio)
    try container.encodeIfPresent(steps, forKey: .steps)
    try container.encodeIfPresent(guidance, forKey: .guidance)
    try container.encodeIfPresent(seed, forKey: .seed)
  }
}

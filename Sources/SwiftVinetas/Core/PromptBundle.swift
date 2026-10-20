import Foundation

/// Everything that describes one panel, kept structured until the last
/// moment so each engine can serialize it the way it understands best.
///
/// On-device engines take the short comma-joined ``GenerationRequest/prompt``
/// and read size, steps, guidance, and seed as sampler parameters. Cloud
/// models are instruction-following and ignore most sampler parameters, so
/// for them the bundle is rendered by ``rendered(nativeNegativePrompt:)``
/// into a prompt that spells out the style, frame size, aspect ratio,
/// character, and reference-image roles in words, in addition to whatever
/// native fields the vendor accepts.
///
/// The bundle is recorded in ``ImageOutput/PanelMetadata`` and printed by
/// `vinetas generate --dry-run`, so the exact text a vendor received is
/// always recoverable.
public struct PromptBundle: Codable, Sendable, Equatable {

  /// The character a panel depicts, as the prompt describes it.
  public struct CharacterBrief: Codable, Sendable, Equatable {
    public var name: String
    public var description: String

    public init(name: String, description: String) {
      self.name = name
      self.description = description
    }
  }

  /// The user's panel prompt, before any composition.
  public var panelPrompt: String

  /// The art-style prompt, if any.
  public var stylePrompt: String?

  /// What the image should avoid, if anything.
  public var negativePrompt: String?

  /// Requested output width in pixels.
  public var width: Int

  /// Requested output height in pixels.
  public var height: Int

  /// The character the panel depicts, if any.
  public var character: CharacterBrief?

  /// Number of reference images attached to the request.
  public var referenceCount: Int

  /// Requested inference steps. Recorded for provenance only; never rendered
  /// into prompt text.
  public var steps: Int

  /// Requested guidance scale. Recorded for provenance only.
  public var guidanceScale: Float

  /// Requested seed, if any. Recorded for provenance only.
  public var seed: UInt64?

  public init(
    panelPrompt: String,
    stylePrompt: String? = nil,
    negativePrompt: String? = nil,
    width: Int,
    height: Int,
    character: CharacterBrief? = nil,
    referenceCount: Int = 0,
    steps: Int,
    guidanceScale: Float,
    seed: UInt64? = nil
  ) {
    self.panelPrompt = panelPrompt
    self.stylePrompt = stylePrompt.flatMap { $0.isEmpty ? nil : $0 }
    self.negativePrompt = negativePrompt.flatMap { $0.isEmpty ? nil : $0 }
    self.width = width
    self.height = height
    self.character = character
    self.referenceCount = referenceCount
    self.steps = steps
    self.guidanceScale = guidanceScale
    self.seed = seed
  }

  // MARK: - Derived

  /// Ratios a reader (and a vendor) recognises by name.
  private static let namedRatios: [(w: Int, h: Int)] = [
    (1, 1), (5, 4), (4, 3), (3, 2), (16, 9), (2, 1), (21, 9), (4, 1),
  ]

  /// The aspect ratio as a `W:H` label. Sizes within 3% of a named ratio
  /// take its name (`2144×1200` → `16:9`), because clamping and snapping to
  /// a multiple of 16 or 32 rarely leaves an exact ratio. Other sizes reduce
  /// to lowest terms, or to a decimal (`1.33:1`) when those terms are large.
  public var aspectRatioLabel: String {
    guard width > 0, height > 0 else { return "1:1" }
    let target = Double(width) / Double(height)
    for named in Self.namedRatios {
      for (w, h) in [(named.w, named.h), (named.h, named.w)] {
        let ratio = Double(w) / Double(h)
        if abs(target - ratio) / ratio <= 0.03 { return "\(w):\(h)" }
      }
    }
    let divisor = Self.gcd(width, height)
    let w = width / divisor
    let h = height / divisor
    if w <= 32, h <= 32 { return "\(w):\(h)" }
    return target >= 1
      ? String(format: "%.2f:1", target)
      : String(format: "1:%.2f", 1 / target)
  }

  /// `landscape`, `portrait`, or `square`.
  public var orientation: String {
    if width == height { return "square" }
    return width > height ? "landscape" : "portrait"
  }

  // MARK: - Rendering

  /// The prompt text a cloud vendor receives.
  ///
  /// - Parameter nativeNegativePrompt: `true` when the vendor takes the
  ///   negative prompt as its own field, in which case it is not repeated in
  ///   the text.
  public func rendered(nativeNegativePrompt: Bool) -> String {
    var sections = [panelPrompt.trimmingCharacters(in: .whitespacesAndNewlines)]

    if let stylePrompt {
      sections.append("Art style: \(stylePrompt).")
    }

    sections.append(
      "Frame: \(width)×\(height) pixels, \(aspectRatioLabel) \(orientation) aspect ratio. "
        + "Compose for this frame and fill it edge to edge; no borders or letterboxing.")

    if let character {
      let description = character.description.trimmingCharacters(in: .whitespacesAndNewlines)
      sections.append(
        description.isEmpty
          ? "Character: \(character.name)."
          : "Character: \(character.name) — \(description)")
    }

    let noCopy =
      "Do not copy the references' pose, framing, lighting, or background; take those from "
      + "this prompt."
    if referenceCount > 0, let character {
      // The references are all one person: say whose they are.
      let images =
        referenceCount == 1
        ? "The attached image shows" : "The \(referenceCount) attached images show"
      sections.append(
        "Reference images: \(images) \(character.name). Keep \(character.name)'s identity "
          + "consistent with the references — face, hair, build, and costume. \(noCopy)")
    } else if referenceCount > 0 {
      // Caller-supplied references may each be a different person or place;
      // the panel prompt says which is which, so only number them.
      let images =
        referenceCount == 1
        ? "1 attached (image 1)"
        : "\(referenceCount) attached, in order (image 1 to image \(referenceCount))"
      sections.append(
        "Reference images: \(images). Use each one as this prompt describes, keeping the identity "
          + "of every person or place it shows consistent with it — face, hair, build, costume, "
          + "architecture. \(noCopy)")
    }

    if !nativeNegativePrompt, let negativePrompt {
      sections.append("Avoid: \(negativePrompt).")
    }

    return sections.joined(separator: "\n\n")
  }

  private static func gcd(_ a: Int, _ b: Int) -> Int {
    var (a, b) = (abs(a), abs(b))
    while b != 0 { (a, b) = (b, a % b) }
    return max(a, 1)
  }
}

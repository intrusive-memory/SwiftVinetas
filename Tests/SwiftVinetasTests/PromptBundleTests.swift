import Foundation
import Testing

@testable import SwiftVinetas

@Suite("PromptBundle")
struct PromptBundleTests {

  private func bundle(
    width: Int = 1344, height: Int = 768, style: String? = "ink wash noir",
    negative: String? = "text, watermark",
    character: PromptBundle.CharacterBrief? = nil, references: Int = 0
  ) -> PromptBundle {
    PromptBundle(
      panelPrompt: "Mara waits at the dock at dawn", stylePrompt: style, negativePrompt: negative,
      width: width, height: height, character: character, referenceCount: references,
      steps: 20, guidanceScale: 3.5, seed: 7)
  }

  @Test("aspect labels snap to named ratios, then reduce, then fall back to a decimal")
  func aspectLabels() {
    #expect(bundle(width: 2144, height: 1200).aspectRatioLabel == "16:9")
    #expect(bundle(width: 1344, height: 768).aspectRatioLabel == "16:9")
    #expect(bundle(width: 768, height: 1344).aspectRatioLabel == "9:16")
    #expect(bundle(width: 1024, height: 1024).aspectRatioLabel == "1:1")
    #expect(bundle(width: 2048, height: 512).aspectRatioLabel == "4:1")
    #expect(bundle(width: 1536, height: 640).aspectRatioLabel == "21:9")
    #expect(bundle(width: 700, height: 1000).aspectRatioLabel == "7:10")
    #expect(bundle(width: 1999, height: 1000).aspectRatioLabel == "2:1")
    #expect(bundle(width: 1171, height: 1000).aspectRatioLabel == "1.17:1")
  }

  @Test("rendering spells out style, frame, aspect, and orientation, then what to avoid")
  func renderedTextToImage() {
    let text = bundle().rendered(nativeNegativePrompt: false)
    #expect(text.hasPrefix("Mara waits at the dock at dawn\n\n"))
    #expect(text.contains("Art style: ink wash noir."))
    #expect(text.contains("Frame: 1344×768 pixels, 16:9 landscape aspect ratio."))
    #expect(text.hasSuffix("Avoid: text, watermark."))
    #expect(!text.contains("Reference images"))
    #expect(!text.contains("Character"))
    // Sampler parameters are provenance, never prompt text.
    #expect(!text.contains("3.5") && !text.contains("seed"))
  }

  @Test("a vendor that takes the negative prompt natively does not see it repeated")
  func nativeNegativeOmitted() {
    #expect(!bundle().rendered(nativeNegativePrompt: true).contains("Avoid"))
  }

  @Test("empty style and negative are dropped, not rendered as blanks")
  func emptyPartsDropped() {
    let text = bundle(style: "", negative: "").rendered(nativeNegativePrompt: false)
    #expect(!text.contains("Art style"))
    #expect(!text.contains("Avoid"))
  }

  @Test("a character with references is named, described, and held to the references")
  func renderedCharacterWithReferences() {
    let text = bundle(
      character: .init(name: "Mara", description: "a tall woman with a grey braid"),
      references: 3
    ).rendered(nativeNegativePrompt: false)
    #expect(text.contains("Character: Mara — a tall woman with a grey braid"))
    #expect(text.contains("Reference images: The 3 attached images show Mara."))
    #expect(text.contains("Do not copy the references' pose"))
  }

  @Test("references without a character refer to the subject")
  func renderedReferencesOnly() {
    let text = bundle(references: 1).rendered(nativeNegativePrompt: false)
    #expect(text.contains("Reference images: The attached image shows the subject."))
  }

  @Test("the bundle round-trips through JSON")
  func codableRoundTrip() throws {
    let original = bundle(character: .init(name: "Mara", description: "grey braid"), references: 2)
    let decoded = try JSONDecoder().decode(
      PromptBundle.self, from: JSONEncoder().encode(original))
    #expect(decoded == original)
  }
}

import Testing

@testable import VinetasVocabulary

@Suite
@MainActor
struct StoryboardStyleTests {

  // MARK: - R14.1: from(promptText:) returns correct style for every known prompt

  @Test
  func fromPromptText_returnsCorrectStyle_forAllCases() {
    for style in StoryboardStyle.allCases where style != .custom {
      let result = StoryboardStyle.from(promptText: style.promptText)
      #expect(result == style, "Expected \(style) for promptText: \(style.promptText)")
    }
  }

  @Test
  func fromPromptText_returnsNil_forCustom() {
    let result = StoryboardStyle.from(promptText: StoryboardStyle.custom.promptText)
    #expect(result == nil, ".custom has empty promptText so from(promptText:) should return nil")
  }

  // MARK: - R14.2: from(promptText:) returns nil for unknown prompt

  @Test
  func fromPromptText_returnsNil_forUnknownPrompt() {
    let result = StoryboardStyle.from(promptText: "nonexistent prompt")
    #expect(result == nil)
  }

  // MARK: - R14.3: All cases have non-empty displayName and promptText

  @Test
  func allCases_haveNonEmptyDisplayName() {
    for style in StoryboardStyle.allCases {
      #expect(!style.displayName.isEmpty, "\(style) has empty displayName")
    }
  }

  @Test
  func allPresetCases_haveNonEmptyPromptText() {
    for style in StoryboardStyle.allCases where style != .custom {
      #expect(!style.promptText.isEmpty, "\(style) has empty promptText")
    }
  }

  @Test
  func custom_hasEmptyPromptText() {
    #expect(StoryboardStyle.custom.promptText.isEmpty)
  }

  // MARK: - Default negative prompts

  @Test
  func allPresetCases_haveNonEmptyNegativePromptText() {
    for style in StoryboardStyle.allCases where style != .custom {
      #expect(!style.negativePromptText.isEmpty, "\(style) has empty negativePromptText")
    }
  }

  @Test
  func custom_hasEmptyNegativePromptText() {
    #expect(StoryboardStyle.custom.negativePromptText.isEmpty)
  }

  @Test
  func presetNegativePrompts_includeSharedQualityBase() {
    // Every preset's negative is the shared quality base plus tailored
    // additions, so the base terms must always be present.
    for style in StoryboardStyle.allCases where style != .custom {
      #expect(
        style.negativePromptText.contains("low quality"),
        "\(style) negativePromptText is missing the shared quality base"
      )
    }
  }
}

import Testing
import VinetasUI

@Suite struct AccessibilityIdentifierTests {

  /// The documented identifier contract: every constant and its string.
  static let contract: [(constant: String, expected: String)] = [
    (VinetasUIAccessibility.promptPrimary, "prompt.primary"),
    (VinetasUIAccessibility.promptCaption, "prompt.caption"),
    (VinetasUIAccessibility.promptStylePicker, "prompt.stylePicker"),
    (VinetasUIAccessibility.promptStyleCustom, "prompt.styleCustom"),
    (VinetasUIAccessibility.promptNegativeToggle, "prompt.negativeToggle"),
    (VinetasUIAccessibility.promptNegative, "prompt.negative"),
    (VinetasUIAccessibility.stylePickerList, "stylePicker.list"),
    (VinetasUIAccessibility.stylePickerRowPrefix, "stylePicker.row"),
    (
      VinetasUIAccessibility.stylePickerPromptTextDisclosure,
      "stylePicker.promptTextDisclosure"
    ),
    (VinetasUIAccessibility.generationModelPicker, "generation.modelPicker"),
    (
      VinetasUIAccessibility.generationAspectRatioSelection,
      "generation.aspectRatioSelection"
    ),
    (VinetasUIAccessibility.generationAspectRatioTilePrefix, "generation.aspectRatioTile"),
    (VinetasUIAccessibility.generationStepsSlider, "generation.stepsSlider"),
    (VinetasUIAccessibility.generationStepsUseDefault, "generation.stepsUseDefault"),
    (VinetasUIAccessibility.generationGuidanceSlider, "generation.guidanceSlider"),
    (VinetasUIAccessibility.generationGuidanceUseDefault, "generation.guidanceUseDefault"),
    (
      VinetasUIAccessibility.generationAspectRatioUseDefault,
      "generation.aspectRatioUseDefault"
    ),
    (VinetasUIAccessibility.generationSeedField, "generation.seedField"),
    (VinetasUIAccessibility.generationRandomizeSeed, "generation.randomizeSeed"),
    (VinetasUIAccessibility.generationMemoryWarning, "generation.memoryWarning"),
  ]

  @Test func contractHasTwentyIdentifiers() {
    #expect(Self.contract.count == 20)
    #expect(Set(Self.contract.map(\.expected)).count == 20)
  }

  @Test func everyConstantEqualsItsDocumentedString() {
    for entry in Self.contract {
      #expect(entry.constant == entry.expected)
    }
  }

  @Test func stylePickerRowJoinsPrefixAndRawValue() {
    #expect(VinetasUIAccessibility.stylePickerRow("custom") == "stylePicker.row.custom")
  }

  @Test func aspectRatioTileJoinsPrefixAndRawValue() {
    #expect(VinetasUIAccessibility.aspectRatioTile("wide") == "generation.aspectRatioTile.wide")
  }
}

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
    (
      VinetasUIAccessibility.promptNegativeUnsupportedNote,
      "prompt.negativeUnsupportedNote"
    ),
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
    (
      VinetasUIAccessibility.generationStepsUnsupportedNote,
      "generation.stepsUnsupportedNote"
    ),
    (
      VinetasUIAccessibility.generationGuidanceUnsupportedNote,
      "generation.guidanceUnsupportedNote"
    ),
    (VinetasUIAccessibility.generationSeedUnsupportedNote, "generation.seedUnsupportedNote"),
    (VinetasUIAccessibility.generationMemoryWarning, "generation.memoryWarning"),
    (VinetasUIAccessibility.referencesList, "references.list"),
    (VinetasUIAccessibility.referencesAdd, "references.add"),
    (VinetasUIAccessibility.referencesUnsupportedNote, "references.unsupportedNote"),
    (VinetasUIAccessibility.referencesItemPrefix, "references.item"),
    (VinetasUIAccessibility.referencesRemovePrefix, "references.remove"),
    (VinetasUIAccessibility.referencesMoveUpPrefix, "references.moveUp"),
    (VinetasUIAccessibility.referencesMoveDownPrefix, "references.moveDown"),
    (VinetasUIAccessibility.characterField, "character.field"),
  ]

  @Test func contractHasThirtyTwoIdentifiers() {
    #expect(Self.contract.count == 32)
    #expect(Set(Self.contract.map(\.expected)).count == 32)
  }

  @Test func everyConstantEqualsItsDocumentedString() {
    for entry in Self.contract {
      #expect(entry.constant == entry.expected)
    }
  }

  @Test func stylePickerRowJoinsPrefixAndRawValue() {
    #expect(VinetasUIAccessibility.stylePickerRow("custom") == "stylePicker.row.custom")
  }

  @Test func referenceBuildersJoinPrefixAndIndex() {
    #expect(VinetasUIAccessibility.referenceItem(2) == "references.item.2")
    #expect(VinetasUIAccessibility.referenceRemove(0) == "references.remove.0")
    #expect(VinetasUIAccessibility.referenceMoveUp(1) == "references.moveUp.1")
    #expect(VinetasUIAccessibility.referenceMoveDown(1) == "references.moveDown.1")
  }

  @Test func aspectRatioTileJoinsPrefixAndRawValue() {
    #expect(VinetasUIAccessibility.aspectRatioTile("wide") == "generation.aspectRatioTile.wide")
  }
}

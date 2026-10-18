import Foundation
import Testing

@testable import VinetasVocabulary

/// Guards the frozen `StoryboardStyle` vocabulary.
///
/// Hosts persist a style's `rawValue` and send its `promptText` and
/// `negativePromptText` to the model, so renaming a case, reordering the cases
/// or editing one word of a prompt silently changes what a saved storyboard
/// renders. `Fixtures/style-vocabulary.json` was generated from the enum once
/// and committed; this suite fails when any of the twenty cases drifts from it.
@Suite("Frozen vocabulary")
struct FrozenVocabularyTests {

  struct FrozenStyle: Codable, Equatable {
    var rawValue: String
    var promptText: String
    var negativePromptText: String
  }

  static func loadFixture() throws -> [FrozenStyle] {
    let url = try #require(
      Bundle.module.url(
        forResource: "style-vocabulary", withExtension: "json", subdirectory: "Fixtures"),
      "Fixtures/style-vocabulary.json is missing from the test bundle"
    )
    return try JSONDecoder().decode([FrozenStyle].self, from: Data(contentsOf: url))
  }

  @Test("There are twenty styles, in fixture order")
  func caseCountAndOrder() throws {
    let frozen = try Self.loadFixture()
    #expect(StoryboardStyle.allCases.count == 20)
    #expect(frozen.count == 20)
    #expect(StoryboardStyle.allCases.map(\.rawValue) == frozen.map(\.rawValue))
    #expect(StoryboardStyle.allCases.last == .custom)
  }

  @Test("Every style's rawValue, promptText and negativePromptText match the fixture byte for byte")
  func everyStyleMatchesFixture() throws {
    let frozen = try Self.loadFixture()
    try #require(frozen.count == StoryboardStyle.allCases.count)
    for (style, expected) in zip(StoryboardStyle.allCases, frozen) {
      #expect(
        Array(style.rawValue.utf8) == Array(expected.rawValue.utf8), "rawValue drifted for \(style)"
      )
      #expect(
        Array(style.promptText.utf8) == Array(expected.promptText.utf8),
        "promptText drifted for \(style)"
      )
      #expect(
        Array(style.negativePromptText.utf8) == Array(expected.negativePromptText.utf8),
        "negativePromptText drifted for \(style)"
      )
    }
  }

  @Test("Every style resolves from its rawValue")
  func rawValueRoundTrip() throws {
    for expected in try Self.loadFixture() {
      #expect(StoryboardStyle(rawValue: expected.rawValue)?.rawValue == expected.rawValue)
    }
  }
}

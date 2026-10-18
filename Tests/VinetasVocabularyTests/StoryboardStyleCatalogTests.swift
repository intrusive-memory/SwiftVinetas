import Foundation
import Testing

@testable import VinetasVocabulary

/// Guards the storyboard style catalog that leaves this repo.
///
/// `StoryboardStyle` is not purely internal any more: the `vinetas-skills`
/// repository vendors each style's display name, genre, prompt and negative so
/// that a storyboard rendered from an agent through `VinetasCLI` looks like the
/// one the app produces for the same named style. Nothing in the type system
/// connects those two copies, so a one-word edit to a prompt here would quietly
/// desynchronise them and the only symptom would be "the CLI gives me different
/// art than the app".
///
/// `Fixtures/storyboard-styles.json` is the canonical export, copied unchanged
/// from the Vinetas app, and this suite fails when the enum and the export
/// disagree. The Vinetas app's `Scripts/sync-storyboard-styles.sh` regenerates
/// it and pushes the result into a sibling `vinetas-skills` checkout.
///
/// The fixture is a test-target resource (`resources: [.copy("Fixtures")]`)
/// read through `Bundle.module`.
@Suite("StoryboardStyle — published catalog")
@MainActor
struct StoryboardStyleCatalogTests {

  struct ExportedStyle: Codable, Equatable {
    var id: String
    var displayName: String
    var genre: String?
    var prompt: String
    var negative: String
  }

  struct Catalog: Codable {
    var styles: [ExportedStyle]
  }

  static var fixtureURL: URL {
    get throws {
      try #require(
        Bundle.module.url(
          forResource: "storyboard-styles", withExtension: "json", subdirectory: "Fixtures"),
        "Fixtures/storyboard-styles.json is missing from the test bundle"
      )
    }
  }

  /// The catalog as the enum currently defines it.
  static var live: [ExportedStyle] {
    StoryboardStyle.allCases
      .filter { $0 != .custom }
      .map {
        ExportedStyle(
          id: $0.rawValue,
          displayName: $0.displayName,
          genre: $0.genre,
          prompt: $0.promptText,
          negative: $0.negativePromptText
        )
      }
  }

  static func loadFixture() throws -> [ExportedStyle] {
    let data = try Data(contentsOf: try fixtureURL)
    return try JSONDecoder().decode(Catalog.self, from: data).styles
  }

  // MARK: - Drift

  @Test("The exported catalog matches the enum")
  func exportMatchesEnum() throws {
    let exported = try Self.loadFixture()
    let live = Self.live

    // Compare per style so a failure names the offender instead of dumping
    // two 19-element arrays.
    let exportedByID = Dictionary(uniqueKeysWithValues: exported.map { ($0.id, $0) })
    let liveByID = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })

    let added = Set(liveByID.keys).subtracting(exportedByID.keys).sorted()
    let removed = Set(exportedByID.keys).subtracting(liveByID.keys).sorted()

    #expect(
      added.isEmpty,
      """
      New style(s) \(added) are not in the published catalog. \
      Run Scripts/sync-storyboard-styles.sh, and give each new style a \
      preferredEngine in vinetas-skills/…/data/styles.json.
      """
    )
    #expect(
      removed.isEmpty,
      """
      Style(s) \(removed) were removed from the enum but are still \
      published. Run Scripts/sync-storyboard-styles.sh — and note that \
      removing a style breaks any shotlist referencing it.
      """
    )

    for id in Set(liveByID.keys).intersection(exportedByID.keys).sorted() {
      #expect(
        liveByID[id] == exportedByID[id],
        """
        Style '\(id)' has drifted from the published catalog. \
        Run Scripts/sync-storyboard-styles.sh to republish.
        """
      )
    }
  }

  // MARK: - Invariants the published catalog relies on

  @Test("Every published style has usable prompt and negative text")
  func publishedStylesAreUsable() {
    for style in Self.live {
      #expect(!style.prompt.isEmpty, "\(style.id) has an empty prompt")
      #expect(!style.negative.isEmpty, "\(style.id) has an empty negative prompt")
      #expect(!style.displayName.isEmpty, "\(style.id) has an empty display name")
    }
  }

  @Test("Style ids and display names are unique")
  func identifiersAreUnique() {
    let live = Self.live
    #expect(Set(live.map(\.id)).count == live.count, "duplicate style id")
    #expect(
      Set(live.map(\.displayName)).count == live.count,
      "duplicate display name — the picker would show two identical rows"
    )
  }

  @Test("custom is deliberately excluded from the published catalog")
  func customIsNotPublished() throws {
    // `.custom` carries no prompt text — the user supplies it — so there is
    // nothing to vendor and shipping it would give agents an empty style.
    let exported = try Self.loadFixture()
    #expect(!exported.contains { $0.id == StoryboardStyle.custom.rawValue })
  }
}

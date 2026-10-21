import Foundation
import Testing
import VinetasVocabulary

@testable import VinetasUI

@Suite struct PromptDraftTests {

  /// The establishing shot as a fully populated draft, captioned with the
  /// scene heading.
  private func establishingDraft() throws -> VinetasPromptDraft {
    let panel = try GranvilleFixtures.establishingPanel
    return draft(from: panel, caption: GranvilleFixtures.sceneHeading)
  }

  private func draft(from panel: GranvillePanel, caption: String? = nil) -> VinetasPromptDraft {
    VinetasPromptDraft(
      prompt: panel.prompt,
      caption: caption,
      stylePrompt: panel.style,
      negativePrompt: panel.negative,
      modelID: panel.model,
      aspectRatio: .wide,
      steps: panel.steps,
      guidance: panel.guidance,
      seed: panel.seed
    )
  }

  private func roundTrip(_ draft: VinetasPromptDraft) throws -> VinetasPromptDraft {
    try JSONDecoder().decode(VinetasPromptDraft.self, from: JSONEncoder().encode(draft))
  }

  // MARK: - Defaults

  @Test func emptyEqualsADefaultInitialisedDraft() {
    #expect(VinetasPromptDraft.empty == VinetasPromptDraft())
  }

  @Test func defaultsMatchTheContract() {
    let draft = VinetasPromptDraft()
    #expect(draft.prompt == "")
    #expect(draft.caption == nil)
    #expect(draft.stylePrompt == "")
    #expect(draft.negativePrompt == "")
    #expect(draft.modelID == ModelSummary.pixartSigmaXL.id)
    #expect(draft.aspectRatio == nil)
    #expect(draft.steps == nil)
    #expect(draft.guidance == nil)
    #expect(draft.seed == nil)
  }

  // MARK: - Codable

  @Test func establishingDraftRoundTripsLosslessly() throws {
    let draft = try establishingDraft()
    #expect(draft.caption == GranvilleFixtures.sceneHeading)
    #expect(try roundTrip(draft) == draft)
  }

  @Test func emptyRoundTripsLosslessly() throws {
    #expect(try roundTrip(.empty) == .empty)
  }

  @Test func everyGranvillePanelRoundTripsAsKlein4B() throws {
    let panels = try GranvilleFixtures.panels()
    #expect(panels.count == 13)
    for panel in panels {
      let draft = draft(from: panel)
      #expect(try roundTrip(draft) == draft)
      #expect(draft.model == .klein4B)
    }
  }

  @Test func codingKeysAreTheFieldNames() throws {
    let data = try JSONEncoder().encode(try establishingDraft())
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(object.keys) == [
        "prompt", "caption", "stylePrompt", "negativePrompt", "modelID",
        "aspectRatio", "steps", "guidance", "seed",
      ])
    #expect(object["aspectRatio"] as? String == AspectRatio.wide.rawValue)
  }

  // MARK: - Computed

  @Test func unknownModelIDHasNoModel() {
    var draft = VinetasPromptDraft()
    draft.modelID = "klein9b"
    #expect(draft.model == nil)
  }

  @Test func styleRecoversEachPresetFromItsPromptText() {
    for style in StoryboardStyle.sortedPresets {
      var draft = VinetasPromptDraft()
      draft.stylePrompt = style.promptText
      #expect(draft.style == style)
    }
  }

  @Test func freeTextStyleIsNotAPreset() throws {
    var draft = VinetasPromptDraft()
    draft.stylePrompt = try GranvilleFixtures.establishingPanel.style
    #expect(draft.style == nil)
  }

  // MARK: - References and character

  @Test func testDraftRoundTripWithReferencesAndCharacter() throws {
    var draft = try establishingDraft()
    draft.references = ["a.png", "folder/b.png"]
    draft.character = "Ada"
    #expect(try roundTrip(draft) == draft)
    let json = try #require(
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
    #expect(json["references"] as? [String] == ["a.png", "folder/b.png"])
    #expect(json["character"] as? String == "Ada")
  }

  @Test func testDraftDecodesWithoutNewFields() throws {
    let data = Data(#"{"prompt":"p","modelID":"flux2-klein-4b"}"#.utf8)
    let draft = try JSONDecoder().decode(VinetasPromptDraft.self, from: data)
    #expect(draft.references.isEmpty)
    #expect(draft.character == nil)
    #expect(draft.prompt == "p")
  }

  @Test func cloudModelIDResolvesThroughTheDraft() throws {
    let cloud = try #require(ModelSummary.cloud.first)
    #expect(VinetasPromptDraft(modelID: cloud.id).model == cloud)
  }
}

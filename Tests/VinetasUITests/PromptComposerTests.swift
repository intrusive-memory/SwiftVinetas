import SwiftUI
import Testing
import VinetasVocabulary

@testable import VinetasUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

@Suite struct PromptComposerTests {

  /// Lays `view` out in a hosting controller so its body really runs.
  @MainActor private func render(_ view: some View) {
    #if os(macOS)
      let host = NSHostingController(rootView: view)
      host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
      host.view.layoutSubtreeIfNeeded()
    #elseif os(iOS)
      let host = UIHostingController(rootView: view)
      host.view.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
      host.view.layoutIfNeeded()
    #endif
  }

  /// The establishing shot as a fully populated draft.
  private func establishingDraft() throws -> VinetasPromptDraft {
    let panel = try GranvilleFixtures.establishingPanel
    return VinetasPromptDraft(
      prompt: panel.prompt,
      caption: GranvilleFixtures.sceneHeading,
      stylePrompt: panel.style,
      negativePrompt: panel.negative,
      modelID: panel.model,
      aspectRatio: .wide,
      steps: panel.steps,
      guidance: panel.guidance,
      seed: panel.seed
    )
  }

  // MARK: - setDefault

  @Test func defaultOnSetsEachFieldToNil() throws {
    var draft = try establishingDraft()
    let model = try #require(draft.model)
    VinetasPromptComposer.setDefault(.steps, on: true, in: &draft, model: model)
    #expect(draft.steps == nil)
    VinetasPromptComposer.setDefault(.guidance, on: true, in: &draft, model: model)
    #expect(draft.guidance == nil)
    VinetasPromptComposer.setDefault(.aspectRatio, on: true, in: &draft, model: model)
    #expect(draft.aspectRatio == nil)
  }

  @Test func defaultOffWritesTheModelDefaults() throws {
    for model in ModelSummary.all {
      var draft = try establishingDraft()
      draft.modelID = model.id
      for field in VinetasPromptComposer.DraftField.allCases {
        VinetasPromptComposer.setDefault(field, on: true, in: &draft, model: model)
        VinetasPromptComposer.setDefault(field, on: false, in: &draft, model: model)
      }
      #expect(draft.steps == model.defaultSteps)
      #expect(draft.guidance == model.defaultGuidance)
      #expect(draft.aspectRatio == model.supportedAspectRatios[0])
    }
  }

  @Test func defaultOffKeepsAValueTheDraftHolds() throws {
    var draft = try establishingDraft()
    VinetasPromptComposer.setDefault(.steps, on: false, in: &draft, model: .pixartSigmaXL)
    VinetasPromptComposer.setDefault(.guidance, on: false, in: &draft, model: .pixartSigmaXL)
    VinetasPromptComposer.setDefault(.aspectRatio, on: false, in: &draft, model: .pixartSigmaXL)
    #expect(draft == (try establishingDraft()))
  }

  // MARK: - setRandomize

  @Test func randomizeOnClearsTheSeed() throws {
    var draft = try establishingDraft()
    VinetasPromptComposer.setRandomize(true, in: &draft)
    #expect(draft.seed == nil)
  }

  @Test func randomizeOffKeepsTheEstablishingSeed() throws {
    var draft = try establishingDraft()
    VinetasPromptComposer.setRandomize(false, in: &draft)
    #expect(draft.seed == 22)
  }

  // MARK: - Instantiation

  @Test @MainActor func composerInstantiatesForEveryLayout() throws {
    let populated = try establishingDraft()
    for layout in VinetasPanelLayout.allCases {
      for showsCaption in [true, false] {
        for draft in [populated, VinetasPromptDraft.empty] {
          render(
            NavigationStack {
              VinetasPromptComposer(draft: .constant(draft), showsCaption: showsCaption)
            }
            .vinetasPanelLayout(layout))
        }
      }
    }
  }

  // MARK: - References, character, status section

  @Test @MainActor func testComposerHidesReferenceRowsByDefault() {
    let composer = VinetasPromptComposer(draft: .constant(.empty))
    #expect(composer.showsReferenceControls == false)
    let shown = VinetasPromptComposer(draft: .constant(.empty), showsReferenceControls: true)
    #expect(shown.showsReferenceControls == true)
    for layout in VinetasPanelLayout.allCases {
      render(NavigationStack { composer }.vinetasPanelLayout(layout))
      render(NavigationStack { shown }.vinetasPanelLayout(layout))
    }
  }

  @Test func testReferenceAddDisabledAtModelLimit() {
    let limit = VinetasPromptComposer.referenceLimit(for: .klein4B)
    #expect(limit == 3)
    #expect(VinetasPromptComposer.canAddReference(count: 2, limit: limit))
    #expect(!VinetasPromptComposer.canAddReference(count: 3, limit: limit))
    var draft = VinetasPromptDraft(modelID: ModelSummary.klein4B.id)
    for _ in 0..<5 { VinetasPromptComposer.addReference(in: &draft, limit: limit) }
    #expect(draft.references.count == 3)
  }

  @Test func testReferenceRowDisabledWhenLimitZero() {
    let limit = VinetasPromptComposer.referenceLimit(for: .pixartSigmaXL)
    #expect(limit == 0)
    #expect(!VinetasPromptComposer.canAddReference(count: 0, limit: limit))
    var draft = VinetasPromptDraft()
    VinetasPromptComposer.addReference(in: &draft, limit: limit)
    #expect(draft.references.isEmpty)
  }

  @Test func referenceRemoveAndReorder() {
    var draft = VinetasPromptDraft(references: ["a", "b", "c"])
    VinetasPromptComposer.moveReference(from: 0, by: 1, in: &draft)
    #expect(draft.references == ["b", "a", "c"])
    VinetasPromptComposer.moveReference(from: 2, by: 1, in: &draft)
    #expect(draft.references == ["b", "a", "c"])
    VinetasPromptComposer.removeReference(at: 1, in: &draft)
    #expect(draft.references == ["b", "c"])
    VinetasPromptComposer.removeReference(at: 9, in: &draft)
    #expect(draft.references == ["b", "c"])
  }

  @Test @MainActor func testStatusSectionRendersHostContent() {
    var built = 0
    let composer = VinetasPromptComposer(draft: .constant(.empty)) {
      Text("host status")
        .onAppear { built += 1 }
    }
    for layout in VinetasPanelLayout.allCases {
      render(NavigationStack { composer }.vinetasPanelLayout(layout))
    }
    // The slot type is the host's content, not EmptyView.
    #expect(type(of: composer) != VinetasPromptComposer<EmptyView>.self)
    #expect(String(describing: type(of: composer)).contains("Text"))
    _ = built
  }
}

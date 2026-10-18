// HostRecipeTests.swift
// VinetasUITests
//
// Recipes 1 and 2 of docs/VinetasUI.md, verbatim, so the host guide cannot
// show code that no longer compiles. `HostRecipeDocSyncTests` asserts the
// text between each pair of markers is byte-identical to the guide's code
// block. The sample draft is granville episode 1's establishing shot
// (Fixtures/granville/ep1_sc1_01_establishing.json) with its scene heading as
// the caption.

import SwiftUI
import Testing
import VinetasUI
import VinetasVocabulary

// recipe-1:begin
struct ContentView: View {
  @State private var draft = VinetasPromptDraft(
    prompt:
      "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame.",
    caption: "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET",
    stylePrompt:
      "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light",
    negativePrompt:
      "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry",
    modelID: ModelSummary.klein4B.id,
    aspectRatio: .wide,
    steps: 8,
    guidance: 3.5,
    seed: 22
  )
  @State private var showsInspector = true

  var body: some View {
    NavigationStack {
      Text(draft.caption ?? draft.prompt)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
          Button("Prompt", systemImage: "sidebar.trailing") { showsInspector.toggle() }
        }
        .vinetasPromptInspector(isPresented: $showsInspector, draft: $draft) {
          Button("Save") { save(draft) }
            .padding()
        }
    }
  }

  /// The host's own save: write the `<shot>`, the file, the record.
  func save(_ draft: VinetasPromptDraft) {}
}
// recipe-1:end

// recipe-2:begin
struct ShotListView: View {
  @State private var draft = VinetasPromptDraft(
    prompt:
      "Wide establishing shot at sunset in the flat middle of the country: a dust-caked SUV towing a U-Haul trailer down an empty two-lane road, a low plume of dust behind it; a small-town water tower reading GRANVILLE and a cluster of grain silos on the far horizon; the road bending toward a tree-lined gravel driveway; long shadows across the fields, deep blue dusk gathering at the tree line. No people visible anywhere in the frame.",
    caption: "EST. SOMEWHERE IN THE MIDDLE OF THE COUNTRY - SUNSET",
    stylePrompt:
      "photorealistic, cinematic film still, 35mm, natural color grading, soft magic-hour light",
    negativePrompt:
      "text, lettering, watermark, logo, cartoon, illustration, extra limbs, deformed hands, blurry",
    modelID: ModelSummary.klein4B.id,
    aspectRatio: .wide,
    steps: 8,
    guidance: 3.5,
    seed: 22
  )

  var body: some View {
    NavigationStack {
      List {
        NavigationLink {
          ShotPromptScreen(draft: $draft, save: save)
        } label: {
          Text(draft.caption ?? draft.prompt)
            .lineLimit(2)
        }
      }
      .navigationTitle("Cold Open")
    }
  }

  /// The host's own save: write the `<shot>`, the file, the record.
  func save(_ draft: VinetasPromptDraft) {}
}

struct ShotPromptScreen: View {
  @Binding var draft: VinetasPromptDraft
  let save: (VinetasPromptDraft) -> Void

  var body: some View {
    VinetasPromptComposer(draft: $draft, showsCaption: true)
      .navigationTitle("Storyboard Prompt")
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") { save(draft) }
        }
      }
  }
}
// recipe-2:end

@Suite struct HostRecipeTests {

  /// Recipe 1 builds as written. Construction only: `body` is never
  /// evaluated, so the inspector's iPhone assertion never runs on the iPhone
  /// simulator pass.
  @MainActor @Test func inspectorRecipeConstructsWithoutAWindow() {
    let view = ContentView()
    #expect(String(describing: type(of: view)) == "ContentView")
  }

  /// Recipe 2 builds as written: the shot list and the pushed screen it
  /// opens, constructed without a window and without evaluating `body`.
  @MainActor @Test func pushedScreenRecipeConstructsWithoutAWindow() {
    let list = ShotListView()
    var draft = VinetasPromptDraft()
    var saved: [VinetasPromptDraft] = []
    let screen = ShotPromptScreen(
      draft: Binding(get: { draft }, set: { draft = $0 }),
      save: { saved.append($0) }
    )
    screen.save(.empty)
    #expect(String(describing: type(of: list)) == "ShotListView")
    #expect(saved == [.empty])
  }
}

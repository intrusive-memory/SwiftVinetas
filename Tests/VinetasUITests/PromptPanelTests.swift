import SwiftUI
import Testing
import VinetasVocabulary

@testable import VinetasUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

@Suite struct PromptPanelTests {

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

  // MARK: - applyPreset

  @Test func presetWritesItsNegativePrompt() throws {
    var negative = try GranvilleFixtures.establishingPanel.negative
    VinetasPromptPanel.applyPreset(StoryboardStyle.noirGraphicNovel.promptText, to: &negative)
    #expect(negative == StoryboardStyle.noirGraphicNovel.negativePromptText)
  }

  @Test func customTagLeavesTheNegativeUnchanged() throws {
    let original = try GranvilleFixtures.establishingPanel.negative
    var negative = original
    VinetasPromptPanel.applyPreset(StoryboardStyle.customTag, to: &negative)
    #expect(negative == original)
  }

  @Test func freeTextStyleLeavesTheNegativeUnchanged() throws {
    let panel = try GranvilleFixtures.establishingPanel
    var negative = panel.negative
    VinetasPromptPanel.applyPreset(panel.style, to: &negative)
    #expect(negative == panel.negative)
  }

  // MARK: - Picker form

  @Test func automaticFormIsAButtonInSidebarAndRegular() {
    for layout in [VinetasPanelLayout.sidebar, .regular] {
      for available in [true, false] {
        #expect(
          VinetasStylePicker.form(layout: layout, style: .automatic, navigationAvailable: available)
            == .button)
      }
    }
  }

  @Test func compactFormFollowsNavigationAvailability() {
    #expect(
      VinetasStylePicker.form(layout: .compact, style: .automatic, navigationAvailable: true)
        == .navigationRow)
    #expect(
      VinetasStylePicker.form(layout: .compact, style: .automatic, navigationAvailable: false)
        == .button)
  }

  @Test func listStyleIsInlineOnEveryLayout() {
    for layout in VinetasPanelLayout.allCases {
      for available in [true, false] {
        #expect(
          VinetasStylePicker.form(layout: layout, style: .list, navigationAvailable: available)
            == .inlineList)
      }
    }
  }

  // MARK: - Instantiation

  @Test @MainActor func viewsInstantiateForEveryLayout() throws {
    let panel = try GranvilleFixtures.establishingPanel
    for layout in VinetasPanelLayout.allCases {
      for style in [VinetasStylePickerStyle.automatic, .list] {
        render(
          VinetasStylePicker(selection: .constant(panel.style))
            .vinetasPanelLayout(layout)
            .vinetasStylePickerStyle(style))
        render(
          VinetasStylePicker(selection: .constant(StoryboardStyle.noirGraphicNovel.promptText))
            .vinetasPanelLayout(layout)
            .vinetasStylePickerStyle(style))
      }
      render(
        VinetasPromptPanel(
          prompt: .constant(panel.prompt),
          stylePrompt: .constant(panel.style),
          negativePrompt: .constant(panel.negative),
          selectedModel: .klein4B
        )
        .vinetasPanelLayout(layout))
      render(
        VinetasPromptPanel(
          prompt: .constant(panel.prompt),
          stylePrompt: .constant(StoryboardStyle.noirGraphicNovel.promptText),
          negativePrompt: .constant(panel.negative),
          selectedModel: .pixartSigmaXL,
          caption: .constant(GranvilleFixtures.sceneHeading)
        )
        .vinetasPanelLayout(layout))
    }
  }

  @Test func promptEditorIsTallerAtRegularWidth() {
    #expect(VinetasPromptPanel.promptEditorMinHeight(for: .regular) == 140)
    #expect(VinetasPromptPanel.promptEditorMinHeight(for: .compact) == 100)
    #expect(VinetasPromptPanel.promptEditorMinHeight(for: .sidebar) == 100)
  }
}

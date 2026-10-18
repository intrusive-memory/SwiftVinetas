import SwiftUI
import Testing
import VinetasVocabulary

@testable import VinetasUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

@Suite struct StyleListTests {

  /// Every selection value the list must accept: each style's `promptText`,
  /// the *Other* sentinel, and the granville establishing panel's free-text style.
  private func selections() throws -> [String] {
    StoryboardStyle.allCases.map(\.promptText)
      + [StoryboardStyle.customTag, try GranvilleFixtures.establishingPanel.style]
  }

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

  @Test @MainActor func instantiatesForEverySelectionAndLayout() throws {
    for selection in try selections() {
      let list = VinetasStyleList(selection: .constant(selection))
      for layout in VinetasPanelLayout.allCases {
        render(list.vinetasPanelLayout(layout))
      }
    }
  }

  @Test func rowIdentifierIsTheStylePickerRowForEachCase() {
    for style in StoryboardStyle.allCases {
      #expect(VinetasStyleList.rowIdentifier(for: style) == "stylePicker.row.\(style.rawValue)")
    }
  }

  @Test func rowsArePresetsThenOtherLast() {
    #expect(VinetasStyleList.rowStyles.count == StoryboardStyle.allCases.count)
    #expect(VinetasStyleList.rowStyles.last == .custom)
    #expect(Set(VinetasStyleList.rowStyles) == Set(StoryboardStyle.allCases))
  }

  @Test func otherRowWritesTheCustomTag() {
    #expect(VinetasStyleList.tag(for: .custom) == StoryboardStyle.customTag)
    #expect(
      VinetasStyleList.tag(for: .noirGraphicNovel) == StoryboardStyle.noirGraphicNovel.promptText)
  }

  @Test func freeTextSelectsOther() throws {
    let style = try GranvilleFixtures.establishingPanel.style
    #expect(VinetasStyleList.selectedStyle(for: style) == .custom)
    #expect(VinetasStyleList.selectedStyle(for: StoryboardStyle.customTag) == .custom)
    #expect(
      VinetasStyleList.selectedStyle(for: StoryboardStyle.photoRealistic.promptText)
        == .photoRealistic)
  }

  @Test func popoverFormIsFiveAndAHalfRowsOf340Points() {
    #expect(VinetasStyleList.popoverWidth == 340)
    #expect(VinetasStyleList.visibleRows == 5.5)
    #expect(VinetasStyleList.rowSpacing == 6)
    #expect(VinetasStyleList.rowMinHeight == 56)
    #expect(VinetasStyleList.rowCornerRadius == 7)
  }
}

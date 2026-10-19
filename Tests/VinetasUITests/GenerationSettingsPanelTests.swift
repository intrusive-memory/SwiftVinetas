import SwiftUI
import Testing
import VinetasVocabulary

@testable import VinetasUI

#if os(macOS)
  import AppKit
#elseif os(iOS)
  import UIKit
#endif

@Suite struct GenerationSettingsPanelTests {

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

  // MARK: - groupedByEngine

  @Test func groupingKeepsFirstSeenEngineOrder() {
    let groups = VinetasGenerationSettingsPanel.groupedByEngine(ModelSummary.all)
    #expect(groups.map(\.engineID) == ["flux2", "pixart-sigma"])
    #expect(groups.map(\.models) == [[.klein4B], [.pixartSigmaXL]])
  }

  @Test func oneModelIsOneGroup() {
    let groups = VinetasGenerationSettingsPanel.groupedByEngine([.klein4B])
    #expect(groups.count == 1)
    #expect(groups.first?.engineID == "flux2")
    #expect(groups.first?.models == [.klein4B])
  }

  @Test func groupsAreNamedByEngine() {
    #expect(VinetasGenerationSettingsPanel<EmptyView>.engineName(of: [.klein4B]) == "FLUX.2")
    #expect(VinetasGenerationSettingsPanel<EmptyView>.engineName(of: [.pixartSigmaXL]) == "PixArt")
  }

  // MARK: - Aspect-ratio tile

  @Test func tileShapeKeepsTheRatioWithinItsBox() {
    for ratio in AspectRatio.allCases {
      let size = AspectRatioTile.shapeSize(for: ratio)
      #expect(max(size.width, size.height) == AspectRatioTile.maximumShapeSide)
    }
    #expect(AspectRatioTile.label(for: .wide) == "16:9")
  }

  // MARK: - Instantiation

  @Test func defaultsShotAspectIsWide() throws {
    let aspect = try #require(try GranvilleFixtures.defaultsShot["aspect"])
    #expect(AspectRatio(rawValue: aspect) == .wide)
  }

  @Test @MainActor func panelInstantiatesForEveryLayout() throws {
    let panel = try GranvilleFixtures.establishingPanel
    let aspectValue = try #require(try GranvilleFixtures.defaultsShot["aspect"])
    let aspect = try #require(AspectRatio(rawValue: aspectValue))
    #expect(aspect == .wide)
    for layout in VinetasPanelLayout.allCases {
      render(
        VinetasGenerationSettingsPanel(
          models: ModelSummary.all,
          selectedModel: .constant(.klein4B),
          aspectRatio: .constant(aspect),
          steps: .constant(panel.steps),
          guidance: .constant(panel.guidance),
          seed: .constant(panel.seed),
          randomizeSeed: .constant(false)
        )
        .vinetasPanelLayout(layout))
      render(
        VinetasGenerationSettingsPanel(
          models: ModelSummary.all,
          selectedModel: .constant(.klein4B),
          aspectRatio: .constant(aspect),
          steps: .constant(panel.steps),
          guidance: .constant(panel.guidance),
          seed: .constant(panel.seed),
          randomizeSeed: .constant(true),
          useDefaultSteps: .constant(true),
          useDefaultGuidance: .constant(false),
          useDefaultAspectRatio: .constant(true)
        ) {
          Text(verbatim: GranvilleFixtures.sceneHeading)
        }
        .vinetasPanelLayout(layout))
    }
  }
}

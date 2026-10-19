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

  /// A cloud-shaped summary: no steps, guidance or seed, and vendor names.
  static let cloudModel = ModelSummary(
    id: "openai-gpt-image-2.5-flare",
    displayName: "GPT Image 2.5 Flare",
    engineID: "cloud-openai",
    cliName: "openai-gpt-image-2.5-flare",
    minimumMemoryGB: 0,
    approximateDownloadSize: "Cloud",
    defaultSteps: 1,
    defaultGuidance: 1.0,
    supportedAspectRatios: [.square, .wide],
    supportsSteps: false,
    supportsGuidance: false,
    supportsSeed: false,
    supportsNegativePrompt: false,
    engineName: "OpenAI",
    subtitle: "OpenAI · ~$0.03–0.25/image"
  )

  typealias Panel = VinetasGenerationSettingsPanel<EmptyView>

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

  @Test func cloudGroupIsNamedByItsEngineName() {
    #expect(Panel.engineName(of: [Self.cloudModel]) == "OpenAI")
    let groups = Panel.groupedByEngine(ModelSummary.all + [Self.cloudModel])
    #expect(groups.map { Panel.engineName(of: $0.models) } == ["FLUX.2", "PixArt", "OpenAI"])
  }

  // MARK: - Capabilities

  @Test(arguments: Panel.Control.allCases)
  func onDeviceModelsUseEveryControl(control: Panel.Control) {
    for model in ModelSummary.all {
      #expect(Panel.supports(control, model: model))
      #expect(Panel.unsupportedNote(for: control, model: model) == nil)
    }
  }

  @Test(arguments: Panel.Control.allCases)
  func unsupportedControlIsDisabledWithANote(control: Panel.Control) throws {
    #expect(!Panel.supports(control, model: Self.cloudModel))
    let note = try #require(Panel.unsupportedNote(for: control, model: Self.cloudModel))
    #expect(note.hasSuffix("is not used by GPT Image 2.5 Flare."))
  }

  @Test func eachFlagGatesOnlyItsOwnControl() {
    let stepsOnly = ModelSummary(
      id: "x", displayName: "X", engineID: "cloud-x", cliName: "x",
      minimumMemoryGB: 0, approximateDownloadSize: "Cloud",
      defaultSteps: 1, defaultGuidance: 1, supportedAspectRatios: [.square],
      supportsSteps: false
    )
    #expect(!Panel.supports(.steps, model: stepsOnly))
    #expect(Panel.supports(.guidance, model: stepsOnly))
    #expect(Panel.supports(.seed, model: stepsOnly))
  }

  @Test func notesHaveDistinctIdentifiers() {
    let ids = Panel.Control.allCases.map(\.noteIdentifier)
    #expect(
      ids == [
        VinetasUIAccessibility.generationStepsUnsupportedNote,
        VinetasUIAccessibility.generationGuidanceUnsupportedNote,
        VinetasUIAccessibility.generationSeedUnsupportedNote,
      ])
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
      render(
        VinetasGenerationSettingsPanel(
          models: ModelSummary.all + [Self.cloudModel],
          selectedModel: .constant(Self.cloudModel),
          aspectRatio: .constant(.wide),
          steps: .constant(1),
          guidance: .constant(1.0),
          seed: .constant(0),
          randomizeSeed: .constant(false),
          useDefaultSteps: .constant(false),
          useDefaultGuidance: .constant(false)
        )
        .vinetasPanelLayout(layout))
    }
  }
}

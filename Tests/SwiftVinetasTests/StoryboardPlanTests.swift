import Foundation
import GlosaCore
import SwiftVinetas
import Testing

@testable import VinetasCLICore

// MARK: - StoryboardPlanTests
//
// `ShotResolver` (defaults folding) and `ScreenplayShots` (parsing) already have
// suites. The step between them — turning a resolved `Shot` into the concrete
// model + StyleConfig + output path that actually drives generation — had none:
// a test audit measured `StoryboardCommand.swift` at 0% line coverage.
//
// `resolvePlan` and `outputURL` are pure and cheap to test, and they are where
// the silent-fallback behaviour lives: an unrecognised model or aspect warns and
// falls back rather than aborting the run, which is exactly the kind of thing
// that should not change unnoticed.

@Suite("Storyboard — plan resolution")
struct StoryboardPlanTests {

  private func makeCommand() -> Storyboard { Storyboard() }

  private func shot(
    _ prompt: String = "a rain-slicked alley",
    model: String? = nil,
    aspect: String? = nil,
    steps: Int? = nil,
    guidance: Double? = nil,
    seed: UInt64? = nil,
    negative: String? = nil,
    style: String? = nil,
    width: Int? = nil,
    height: Int? = nil,
    lora: String? = nil,
    loraScale: Double? = nil,
    preview: Bool? = nil,
    output: String? = nil
  ) -> Shot {
    Shot(
      documentIndex: 0,
      prompt: prompt,
      style: style,
      model: model,
      aspect: aspect,
      width: width,
      height: height,
      steps: steps,
      guidance: guidance,
      seed: seed,
      negative: negative,
      lora: lora,
      loraScale: loraScale,
      output: output,
      preview: preview
    )
  }

  // MARK: Model resolution

  @Test("A shot with no model inherits the fleet default")
  func inheritsFleetModel() {
    let plan = makeCommand().resolvePlan(
      for: shot(), panelNumber: 1, fleetModel: .pixartSigma)
    #expect(plan.model == .pixartSigma)
  }

  @Test("A shot's own model wins over the fleet default")
  func shotModelWins() {
    let plan = makeCommand().resolvePlan(
      for: shot(model: "klein9b"), panelNumber: 1, fleetModel: .pixartSigma)
    #expect(plan.model == .klein9b)
  }

  @Test("An unrecognised model falls back to the fleet default rather than aborting")
  func unknownModelFallsBack() {
    // A typo in a fleet-default <shot> would otherwise kill a whole board
    // mid-run; the command warns per panel and carries on.
    let plan = makeCommand().resolvePlan(
      for: shot(model: "kleinFourB"), panelNumber: 3, fleetModel: .klein4b)
    #expect(plan.model == .klein4b)
  }

  // MARK: Style + per-engine defaults

  @Test("StyleConfig is seeded from the resolved model's descriptor defaults")
  func seedsEngineDefaults() {
    // PixArt needs its full 20 steps; inheriting FLUX's 8 would under-denoise.
    let pixart = makeCommand().resolvePlan(
      for: shot(), panelNumber: 1, fleetModel: .pixartSigma)
    #expect(pixart.style.steps == PixArtModelDescriptor.sigmaXL.defaultSteps)
    #expect(pixart.style.guidanceScale == PixArtModelDescriptor.sigmaXL.defaultGuidance)

    let flux = makeCommand().resolvePlan(
      for: shot(), panelNumber: 1, fleetModel: .klein4b)
    #expect(flux.style.steps == Flux2ModelDescriptor.klein4B.defaultSteps)
  }

  @Test("Per-shot overrides replace the descriptor defaults")
  func shotOverridesApplied() {
    let plan = makeCommand().resolvePlan(
      for: shot(steps: 33, guidance: 9.5, seed: 4412, negative: "text", style: "noir"),
      panelNumber: 1,
      fleetModel: .pixartSigma
    )
    #expect(plan.style.steps == 33)
    #expect(plan.style.guidanceScale == 9.5)
    #expect(plan.style.seed == 4412)
    #expect(plan.style.negativePrompt == "text")
    #expect(plan.style.stylePrompt == "noir")
  }

  // MARK: Aspect and dimensions

  @Test("A known aspect preset sets width and height")
  func aspectPresetApplied() {
    let plan = makeCommand().resolvePlan(
      for: shot(aspect: "wide"), panelNumber: 1, fleetModel: .pixartSigma)
    #expect(plan.style.width == AspectRatio.wide.width)
    #expect(plan.style.height == AspectRatio.wide.height)
  }

  @Test("An unrecognised aspect is ignored rather than aborting")
  func unknownAspectIgnored() {
    let plan = makeCommand().resolvePlan(
      for: shot(aspect: "cinemascope"), panelNumber: 1, fleetModel: .pixartSigma)
    // Falls through to whatever the engine default is — no crash, no bogus size.
    #expect(plan.model == .pixartSigma)
  }

  @Test("Explicit width and height beat the aspect preset")
  func explicitDimensionsWin() {
    let plan = makeCommand().resolvePlan(
      for: shot(aspect: "wide", width: 1024, height: 576),
      panelNumber: 1,
      fleetModel: .pixartSigma
    )
    #expect(plan.style.width == 1024)
    #expect(plan.style.height == 576)
  }

  // MARK: Preview

  @Test("Preview is honoured on Klein 4B and forces its fixed geometry")
  func previewOnKlein4b() {
    let plan = makeCommand().resolvePlan(
      for: shot(preview: true), panelNumber: 1, fleetModel: .klein4b)
    #expect(plan.usePreview)
    #expect(plan.style.steps == 4)
    #expect(plan.style.width == 512)
    #expect(plan.style.height == 512)
  }

  @Test("Preview is dropped on non-Klein-4B models rather than silently ignoring --model")
  func previewDroppedElsewhere() {
    let plan = makeCommand().resolvePlan(
      for: shot(preview: true), panelNumber: 1, fleetModel: .pixartSigma)
    #expect(!plan.usePreview)
    #expect(plan.model == .pixartSigma)
    // The PixArt descriptor default must survive — not be clobbered to 4.
    #expect(plan.style.steps == PixArtModelDescriptor.sigmaXL.defaultSteps)
  }

  // MARK: LoRA

  @Test("LoRA path and scale are carried through")
  func loraCarriedThrough() {
    let plan = makeCommand().resolvePlan(
      for: shot(lora: "/tmp/x.safetensors", loraScale: 0.55),
      panelNumber: 1,
      fleetModel: .klein4b
    )
    #expect(plan.style.loraPath == "/tmp/x.safetensors")
    #expect(plan.style.loraScale == 0.55)
  }

  // MARK: Output naming

  @Test("Panels are auto-named panel-NNN.png, zero-padded and ordered")
  func autoNaming() {
    let cmd = makeCommand()
    let dir = URL(fileURLWithPath: "/panels")
    let plan = cmd.resolvePlan(for: shot(), panelNumber: 7, fleetModel: .pixartSigma)
    #expect(cmd.outputURL(for: plan, in: dir).lastPathComponent == "panel-007.png")
  }

  @Test("A relative output name resolves under the output directory")
  func relativeOutputResolved() {
    let cmd = makeCommand()
    let dir = URL(fileURLWithPath: "/panels")
    let plan = cmd.resolvePlan(
      for: shot(output: "sc01_02.png"), panelNumber: 1, fleetModel: .pixartSigma)
    #expect(cmd.outputURL(for: plan, in: dir).path == "/panels/sc01_02.png")
  }

  @Test("An absolute output path is honoured verbatim")
  func absoluteOutputHonoured() {
    let cmd = makeCommand()
    let dir = URL(fileURLWithPath: "/panels")
    let plan = cmd.resolvePlan(
      for: shot(output: "/elsewhere/final.png"), panelNumber: 1, fleetModel: .pixartSigma)
    #expect(cmd.outputURL(for: plan, in: dir).path == "/elsewhere/final.png")
  }

  @Test(
    "An empty output string falls back to auto-naming instead of writing to the directory itself")
  func emptyOutputFallsBack() {
    let cmd = makeCommand()
    let dir = URL(fileURLWithPath: "/panels")
    let plan = cmd.resolvePlan(
      for: shot(output: ""), panelNumber: 2, fleetModel: .pixartSigma)
    #expect(cmd.outputURL(for: plan, in: dir).lastPathComponent == "panel-002.png")
  }
}

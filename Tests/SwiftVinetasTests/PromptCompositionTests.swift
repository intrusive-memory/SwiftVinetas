import Foundation
import Testing

@testable import SwiftVinetas

/// Tests verifying how style prompts, panel prompts, and LoRA activation keywords
/// are composed into the final prompt string sent to the FLUX.2 pipeline.
///
/// The composition rules (as implemented in `VinetasPipeline`) are:
///   1. If a LoRA activation keyword is present: `"<keyword>, <stylePrompt>, <panelPrompt>"`
///   2. If only a style prompt is present:       `"<stylePrompt>, <panelPrompt>"`
///   3. If only a panel prompt is present:       `"<panelPrompt>"`
///
/// These tests exercise the composition logic independently of the pipeline
/// by replicating the composition logic and verifying string invariants.
@Suite("Prompt Composition Tests")
struct PromptCompositionTests {

  // MARK: - Helper: compose prompt (mirrors VinetasPipeline logic)

  /// Mirrors the prompt composition logic used in `VinetasPipeline.generateSequence`.
  private func compose(
    panelPrompt: String,
    stylePrompt: String = "",
    activationKeyword: String? = nil
  ) -> String {
    var composed = ""
    if let keyword = activationKeyword, !keyword.isEmpty {
      composed += "\(keyword), "
    }
    if !stylePrompt.isEmpty {
      composed += "\(stylePrompt), "
    }
    composed += panelPrompt
    return composed
  }

  // MARK: - Basic composition

  @Test("panel prompt alone with no style or keyword")
  func panelPromptAlone() {
    let result = compose(panelPrompt: "a detective in the rain")
    #expect(result == "a detective in the rain")
  }

  @Test("style prompt is prepended to panel prompt")
  func stylePromptPrepended() {
    let result = compose(
      panelPrompt: "a detective in the rain",
      stylePrompt: "noir comic, high contrast"
    )
    #expect(result.hasPrefix("noir comic, high contrast,"))
    #expect(result.contains("a detective in the rain"))
  }

  @Test("style and panel are separated by comma-space")
  func styleAndPanelSeparation() {
    let result = compose(
      panelPrompt: "cityscape at night",
      stylePrompt: "watercolor storyboard"
    )
    #expect(result == "watercolor storyboard, cityscape at night")
  }

  // MARK: - LoRA activation keyword injection

  @Test("activation keyword is prepended before style prompt")
  func activationKeywordFirst() {
    let result = compose(
      panelPrompt: "close-up portrait",
      stylePrompt: "manga",
      activationKeyword: "sks_vale"
    )
    #expect(result.hasPrefix("sks_vale,"))
    #expect(result.contains("manga"))
    #expect(result.contains("close-up portrait"))
  }

  @Test("activation keyword ordering: keyword then style then panel")
  func activationKeywordOrdering() {
    let result = compose(
      panelPrompt: "panel prompt",
      stylePrompt: "style prompt",
      activationKeyword: "trigger_word"
    )
    #expect(result == "trigger_word, style prompt, panel prompt")
  }

  @Test("nil activation keyword does not add prefix")
  func nilActivationKeyword() {
    let result = compose(
      panelPrompt: "a scene",
      stylePrompt: "oil painting",
      activationKeyword: nil
    )
    #expect(!result.hasPrefix(","))
    #expect(result == "oil painting, a scene")
  }

  @Test("empty activation keyword does not add prefix")
  func emptyActivationKeyword() {
    let result = compose(
      panelPrompt: "a scene",
      stylePrompt: "oil painting",
      activationKeyword: ""
    )
    #expect(result == "oil painting, a scene")
  }

  @Test("activation keyword with no style prompt")
  func activationKeywordWithoutStyle() {
    let result = compose(
      panelPrompt: "a scene",
      stylePrompt: "",
      activationKeyword: "sks_vale"
    )
    #expect(result == "sks_vale, a scene")
  }

  // MARK: - StyleConfig integration

  @Test("StyleConfig.stylePrompt is used as style part")
  func styleConfigIntegration() {
    let style = StyleConfig(stylePrompt: "pencil sketch, clean lines")
    let result = compose(
      panelPrompt: "front view character",
      stylePrompt: style.stylePrompt
    )
    #expect(result == "pencil sketch, clean lines, front view character")
  }

  @Test("empty StyleConfig.stylePrompt produces panel prompt only")
  func emptyStyleConfigPrompt() {
    let style = StyleConfig()  // default: stylePrompt = ""
    let result = compose(
      panelPrompt: "hero standing on rooftop",
      stylePrompt: style.stylePrompt
    )
    #expect(result == "hero standing on rooftop")
  }

  // MARK: - PromptFile style resolution

  @Test("resolvedStyle stylePrompt is propagated to panels")
  func promptFileStylePropagation() throws {
    let yaml = """
      version: 1
      project:
        title: "Test Comic"
        style:
          prompt: "noir comic"
          steps: 20
          guidance: 3.5
      panels:
        - prompt: "panel one"
        - prompt: "panel two"
      """

    let promptFile = try PromptFile.parse(yaml: yaml)
    let panel0Style = promptFile.resolvedStyle(for: 0)
    let panel1Style = promptFile.resolvedStyle(for: 1)

    // Style prompt propagates from project to all panels
    #expect(panel0Style.stylePrompt == "noir comic")
    #expect(panel1Style.stylePrompt == "noir comic")

    // Panels inherit project steps and guidance
    #expect(panel0Style.steps == 20)
    #expect(panel0Style.guidanceScale == 3.5)
  }

  @Test("panel prompt composition uses resolvedStyle stylePrompt")
  func promptFileComposedPrompt() throws {
    let yaml = """
      version: 1
      project:
        title: "Style Test"
        style:
          prompt: "watercolor storyboard"
      panels:
        - prompt: "a hero walks into a storm"
      """

    let promptFile = try PromptFile.parse(yaml: yaml)
    let style = promptFile.resolvedStyle(for: 0)
    let panelPrompt = promptFile.panels[0].prompt

    let result = compose(panelPrompt: panelPrompt, stylePrompt: style.stylePrompt)
    #expect(result == "watercolor storyboard, a hero walks into a storm")
  }

  // MARK: - Trigger word in LoRA context

  @Test("trigger word is detectable in composed prompt")
  func triggerWordDetectable() {
    let triggerWord = "sks_detective"
    let result = compose(
      panelPrompt: "interrogation scene",
      stylePrompt: "noir comic",
      activationKeyword: triggerWord
    )
    #expect(result.contains(triggerWord))
  }

  @Test("trigger word appears before panel content")
  func triggerWordBeforePanel() {
    let result = compose(
      panelPrompt: "the panel content",
      activationKeyword: "sks_character"
    )
    let keywordRange = result.range(of: "sks_character")
    let panelRange = result.range(of: "the panel content")
    #expect(keywordRange != nil)
    #expect(panelRange != nil)
    if let kr = keywordRange, let pr = panelRange {
      #expect(kr.lowerBound < pr.lowerBound)
    }
  }
}

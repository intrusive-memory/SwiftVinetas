import Foundation
import Testing

@testable import SwiftVinetas

@Suite("PromptFile Tests")
struct PromptFileTests {

  // MARK: - Valid YAML Parsing

  @Test("Parse valid prompt file with 3 panels")
  func parseValidPromptFile() throws {
    let yaml = """
      version: 1
      project:
        title: "Scene Title"
        style:
          prompt: "noir comic book style, heavy inks, dramatic shadows"
          negative: "blurry, low quality, photorealistic"
          steps: 20
          guidance: 3.5
          width: 1024
          height: 1024

      panels:
        - prompt: "Wide establishing shot of a rain-soaked city at night."
          seed: 42
        - prompt: "Close-up of a detective lighting a cigarette under a streetlamp."
        - prompt: "Over-the-shoulder shot looking down a dark alley."
          width: 1536
          height: 640
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    #expect(promptFile.version == 1)
    #expect(promptFile.project.title == "Scene Title")
    #expect(promptFile.panels.count == 3)

    // Panel 1
    #expect(promptFile.panels[0].prompt == "Wide establishing shot of a rain-soaked city at night.")
    #expect(promptFile.panels[0].seed == 42)
    #expect(promptFile.panels[0].width == nil)
    #expect(promptFile.panels[0].height == nil)

    // Panel 2
    #expect(
      promptFile.panels[1].prompt
        == "Close-up of a detective lighting a cigarette under a streetlamp.")
    #expect(promptFile.panels[1].seed == nil)

    // Panel 3
    #expect(promptFile.panels[2].prompt == "Over-the-shoulder shot looking down a dark alley.")
    #expect(promptFile.panels[2].width == 1536)
    #expect(promptFile.panels[2].height == 640)
  }

  // MARK: - Project Style Parsing

  @Test("Parse project-level style configuration")
  func parseProjectStyle() throws {
    let yaml = """
      version: 1
      project:
        title: "Test"
        style:
          prompt: "watercolor style"
          negative: "ugly"
          steps: 25
          guidance: 4.0
          width: 768
          height: 512

      panels:
        - prompt: "A landscape."
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    let style = promptFile.project.style
    #expect(style != nil)
    #expect(style?.prompt == "watercolor style")
    #expect(style?.negative == "ugly")
    #expect(style?.steps == 25)
    #expect(style?.guidance == 4.0)
    #expect(style?.width == 768)
    #expect(style?.height == 512)
  }

  // MARK: - Invalid YAML

  @Test("Reject completely invalid YAML")
  func rejectInvalidYAML() {
    let yaml = "{{{{not valid yaml at all::::"

    #expect(throws: VinetasError.self) {
      try PromptFile.parse(yaml: yaml)
    }
  }

  // MARK: - Missing Required Fields

  @Test("Reject YAML missing version")
  func rejectMissingVersion() {
    let yaml = """
      project:
        title: "Test"
      panels:
        - prompt: "A panel."
      """

    #expect(throws: VinetasError.self) {
      try PromptFile.parse(yaml: yaml)
    }
  }

  @Test("Reject YAML missing project")
  func rejectMissingProject() {
    let yaml = """
      version: 1
      panels:
        - prompt: "A panel."
      """

    #expect(throws: VinetasError.self) {
      try PromptFile.parse(yaml: yaml)
    }
  }

  @Test("Reject YAML missing project title")
  func rejectMissingTitle() {
    let yaml = """
      version: 1
      project:
        style:
          prompt: "test"
      panels:
        - prompt: "A panel."
      """

    #expect(throws: VinetasError.self) {
      try PromptFile.parse(yaml: yaml)
    }
  }

  @Test("Reject YAML missing panels")
  func rejectMissingPanels() {
    let yaml = """
      version: 1
      project:
        title: "Test"
      """

    #expect(throws: VinetasError.self) {
      try PromptFile.parse(yaml: yaml)
    }
  }

  @Test("Reject panel missing prompt")
  func rejectPanelMissingPrompt() {
    let yaml = """
      version: 1
      project:
        title: "Test"
      panels:
        - seed: 42
      """

    #expect(throws: VinetasError.self) {
      try PromptFile.parse(yaml: yaml)
    }
  }

  // MARK: - Per-Panel Dimension Overrides

  @Test("Per-panel dimensions override project defaults")
  func perPanelDimensionOverrides() throws {
    let yaml = """
      version: 1
      project:
        title: "Dimension Test"
        style:
          width: 1024
          height: 1024

      panels:
        - prompt: "Default dimensions panel."
        - prompt: "Custom wide panel."
          width: 1536
          height: 640
        - prompt: "Custom portrait panel."
          width: 768
          height: 1344
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    // Panel 1: should use project defaults
    let style0 = promptFile.resolvedStyle(for: 0)
    #expect(style0.width == 1024)
    #expect(style0.height == 1024)

    // Panel 2: should override with per-panel values
    let style1 = promptFile.resolvedStyle(for: 1)
    #expect(style1.width == 1536)
    #expect(style1.height == 640)

    // Panel 3: should override with per-panel values
    let style2 = promptFile.resolvedStyle(for: 2)
    #expect(style2.width == 768)
    #expect(style2.height == 1344)
  }

  // MARK: - Style Inheritance

  @Test("Panel inherits project-level style settings")
  func styleInheritance() throws {
    let yaml = """
      version: 1
      project:
        title: "Style Inheritance Test"
        style:
          prompt: "noir comic book style"
          negative: "blurry, low quality"
          steps: 25
          guidance: 4.0
          width: 1024
          height: 1024

      panels:
        - prompt: "A detective in an alley."
          seed: 42
      """

    let promptFile = try PromptFile.parse(yaml: yaml)
    let resolved = promptFile.resolvedStyle(for: 0)

    // Inherited from project style
    #expect(resolved.stylePrompt == "noir comic book style")
    #expect(resolved.negativePrompt == "blurry, low quality")
    #expect(resolved.steps == 25)
    #expect(resolved.guidanceScale == 4.0)
    #expect(resolved.width == 1024)
    #expect(resolved.height == 1024)

    // Panel-specific
    #expect(resolved.seed == 42)
  }

  @Test("Panel dimensions override project style dimensions")
  func panelOverridesProjectStyle() throws {
    let yaml = """
      version: 1
      project:
        title: "Override Test"
        style:
          prompt: "comic style"
          steps: 20
          guidance: 3.5
          width: 1024
          height: 1024

      panels:
        - prompt: "Wide shot."
          width: 1536
          height: 640
      """

    let promptFile = try PromptFile.parse(yaml: yaml)
    let resolved = promptFile.resolvedStyle(for: 0)

    // Inherited
    #expect(resolved.stylePrompt == "comic style")
    #expect(resolved.steps == 20)
    #expect(resolved.guidanceScale == 3.5)

    // Overridden
    #expect(resolved.width == 1536)
    #expect(resolved.height == 640)
  }

  @Test("Missing project style uses StyleConfig defaults")
  func missingProjectStyleUsesDefaults() throws {
    let yaml = """
      version: 1
      project:
        title: "No Style"

      panels:
        - prompt: "A simple panel."
      """

    let promptFile = try PromptFile.parse(yaml: yaml)
    let resolved = promptFile.resolvedStyle(for: 0)

    // Should use StyleConfig() defaults
    #expect(resolved.stylePrompt == "")
    #expect(resolved.negativePrompt == nil)
    #expect(resolved.steps == 20)
    #expect(resolved.guidanceScale == 3.5)
    #expect(resolved.width == 1024)
    #expect(resolved.height == 1024)
    #expect(resolved.seed == nil)
  }
}

import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - Character Trigger Word Injection Tests

@Suite("Character Trigger Word Injection")
struct CharacterTriggerWordInjectionTests {

  @Test("Trigger word sks_vale is prepended to prompt when character is provided")
  func triggerWordPrependedToPrompt() {
    let character = Character(name: "Detective Vale", slug: "vale")
    let style = StyleConfig()

    let composed = VinetasPipeline.composeCharacterPrompt(
      panelPrompt: "A detective in a dark alley",
      character: character,
      style: style
    )

    #expect(composed.hasPrefix("sks_vale, "))
    #expect(composed == "sks_vale, A detective in a dark alley")
  }

  @Test("Trigger word appears before style prompt and panel prompt")
  func triggerWordBeforeStyleAndPanel() {
    let character = Character(name: "Detective Vale", slug: "vale")
    let style = StyleConfig(stylePrompt: "noir comic")

    let composed = VinetasPipeline.composeCharacterPrompt(
      panelPrompt: "A detective in a dark alley",
      character: character,
      style: style
    )

    #expect(composed == "sks_vale, noir comic, A detective in a dark alley")
  }

  @Test("Custom trigger word is used when provided")
  func customTriggerWord() {
    let character = Character(
      name: "Alice",
      slug: "alice",
      triggerWord: "sks_custom_alice"
    )
    let style = StyleConfig()

    let composed = VinetasPipeline.composeCharacterPrompt(
      panelPrompt: "A woman at a cafe",
      character: character,
      style: style
    )

    #expect(composed.hasPrefix("sks_custom_alice, "))
    #expect(composed == "sks_custom_alice, A woman at a cafe")
  }

  @Test("Empty style prompt produces trigger word and panel prompt only")
  func emptyStylePrompt() {
    let character = Character(name: "Vale", slug: "vale")
    let style = StyleConfig(stylePrompt: "")

    let composed = VinetasPipeline.composeCharacterPrompt(
      panelPrompt: "standing in rain",
      character: character,
      style: style
    )

    #expect(composed == "sks_vale, standing in rain")
  }

  @Test("Trigger word with style and panel: full ordering")
  func fullOrdering() {
    let character = Character(name: "Vale", slug: "vale")
    let style = StyleConfig(stylePrompt: "watercolor storyboard")

    let composed = VinetasPipeline.composeCharacterPrompt(
      panelPrompt: "close-up portrait",
      character: character,
      style: style
    )

    // Order: trigger word, style, panel
    let parts = composed.components(separatedBy: ", ")
    #expect(parts.count == 3)
    #expect(parts[0] == "sks_vale")
    #expect(parts[1] == "watercolor storyboard")
    #expect(parts[2] == "close-up portrait")
  }
}

// MARK: - PromptFile v2 Parsing Tests

@Suite("PromptFile v2 Character Parsing")
struct PromptFileV2Tests {

  @Test("Parse v2 prompt file with characters section")
  func parseV2WithCharacters() throws {
    let yaml = """
      version: 2
      project:
        title: "My Story"
        characters:
          - slug: detective-vale
          - slug: alice
        style:
          prompt: "noir comic"
      panels:
        - prompt: "A detective in a dark alley"
          character: detective-vale
        - prompt: "A woman at a cafe"
          character: alice
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    #expect(promptFile.version == 2)
    #expect(promptFile.project.title == "My Story")

    // Characters
    #expect(promptFile.project.characters != nil)
    #expect(promptFile.project.characters?.count == 2)
    #expect(promptFile.project.characters?[0].slug == "detective-vale")
    #expect(promptFile.project.characters?[1].slug == "alice")

    // Panels with character refs
    #expect(promptFile.panels.count == 2)
    #expect(promptFile.panels[0].character == "detective-vale")
    #expect(promptFile.panels[1].character == "alice")
  }

  @Test("Parse v2 with mixed panels: some with character, some without")
  func parseV2MixedPanels() throws {
    let yaml = """
      version: 2
      project:
        title: "Mixed Story"
        characters:
          - slug: vale
        style:
          prompt: "comic style"
      panels:
        - prompt: "Establishing shot of the city"
        - prompt: "Vale walks down the street"
          character: vale
        - prompt: "Close-up of a clue on the ground"
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    #expect(promptFile.panels.count == 3)
    #expect(promptFile.panels[0].character == nil)
    #expect(promptFile.panels[1].character == "vale")
    #expect(promptFile.panels[2].character == nil)
  }

  @Test("v1 format without characters still parses correctly")
  func v1BackwardsCompatible() throws {
    let yaml = """
      version: 1
      project:
        title: "Old Format"
        style:
          prompt: "noir comic"
          steps: 20
          guidance: 3.5
      panels:
        - prompt: "A detective in the rain"
          seed: 42
        - prompt: "A dark alley"
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    #expect(promptFile.version == 1)
    #expect(promptFile.project.title == "Old Format")
    #expect(promptFile.project.characters == nil)
    #expect(promptFile.panels.count == 2)
    #expect(promptFile.panels[0].character == nil)
    #expect(promptFile.panels[1].character == nil)
    #expect(promptFile.panels[0].seed == 42)
  }

  @Test("v1 format with no style and no characters parses correctly")
  func v1MinimalBackwardsCompatible() throws {
    let yaml = """
      version: 1
      project:
        title: "Minimal"
      panels:
        - prompt: "A simple panel."
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    #expect(promptFile.version == 1)
    #expect(promptFile.project.characters == nil)
    #expect(promptFile.panels[0].character == nil)
  }

  @Test("v2 with characters section but no character on panels")
  func v2CharactersButNoPanelRefs() throws {
    let yaml = """
      version: 2
      project:
        title: "Characters Defined"
        characters:
          - slug: vale
          - slug: bob
      panels:
        - prompt: "An empty room"
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    #expect(promptFile.project.characters?.count == 2)
    #expect(promptFile.panels[0].character == nil)
  }

  @Test("Panel character slug associates with correct character")
  func panelCharacterAssociation() throws {
    let yaml = """
      version: 2
      project:
        title: "Association Test"
        characters:
          - slug: vale
          - slug: alice
      panels:
        - prompt: "Vale investigates"
          character: vale
        - prompt: "Alice arrives"
          character: alice
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    // Verify panel character slugs match project character slugs
    let projectSlugs = promptFile.project.characters?.map(\.slug) ?? []
    #expect(projectSlugs.contains(promptFile.panels[0].character!))
    #expect(projectSlugs.contains(promptFile.panels[1].character!))
    #expect(promptFile.panels[0].character == "vale")
    #expect(promptFile.panels[1].character == "alice")
  }

  @Test("v2 style is still parsed correctly with characters")
  func v2StyleParsedWithCharacters() throws {
    let yaml = """
      version: 2
      project:
        title: "Style + Characters"
        characters:
          - slug: vale
        style:
          prompt: "pencil sketch"
          steps: 25
          guidance: 4.0
          width: 768
          height: 512
      panels:
        - prompt: "A scene"
          character: vale
      """

    let promptFile = try PromptFile.parse(yaml: yaml)

    #expect(promptFile.project.style?.prompt == "pencil sketch")
    #expect(promptFile.project.style?.steps == 25)
    #expect(promptFile.project.style?.guidance == 4.0)
    #expect(promptFile.project.style?.width == 768)
    #expect(promptFile.project.style?.height == 512)
  }
}

// MARK: - Vinetas Character-Aware API Compilation Tests

@Suite("Vinetas Character-Aware Generation API")
struct VinetasCharacterAwareAPITests {

  @Test("Vinetas.generate(prompt:character:style:model:) symbol exists")
  func generateWithCharacterSymbolExists() {
    // Verify the method reference compiles — actual execution requires GPU/model
    let _fn: (String, Character, StyleConfig?, VinetasModel) async throws -> CGImage =
      Vinetas.generate(prompt:character:style:model:)
    _ = _fn
  }

  @Test("PromptFile.Panel has character property")
  func panelHasCharacterProperty() throws {
    let yaml = """
      version: 2
      project:
        title: "API Test"
        characters:
          - slug: vale
      panels:
        - prompt: "A panel"
          character: vale
      """

    let promptFile = try PromptFile.parse(yaml: yaml)
    let panel = promptFile.panels[0]

    // Verify the character property is accessible
    let charSlug: String? = panel.character
    #expect(charSlug == "vale")
  }

  @Test("PromptFile.CharacterRef has slug property")
  func characterRefHasSlug() throws {
    let yaml = """
      version: 2
      project:
        title: "Ref Test"
        characters:
          - slug: detective-vale
      panels:
        - prompt: "A panel"
      """

    let promptFile = try PromptFile.parse(yaml: yaml)
    let charRef = promptFile.project.characters!.first!

    #expect(charRef.slug == "detective-vale")
  }
}

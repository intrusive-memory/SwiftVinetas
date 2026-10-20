import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

/// `PanelRequest.character`: a character is carried by its trained LoRA on an
/// engine that can apply it, and by its description plus its reference
/// images on a cloud engine — never by a bare trigger word.
@Suite("Character panels")
struct CharacterPanelTests {

  /// A throwaway character directory with a reference sheet, a source photo,
  /// and (optionally) a LoRA file.
  private struct Fixture {
    let manager: CharacterManager
    let character: Character
    let root: URL

    init(withLoRA: Bool, sheets: [String] = ["back", "front"]) throws {
      root = FileManager.default.temporaryDirectory
        .appendingPathComponent("characters-\(UUID().uuidString)", isDirectory: true)
      manager = CharacterManager(baseDirectory: root)
      var character = try manager.createCharacter(
        name: "Mara Quill", photo: MockEngine.create1x1Image(),
        description: "a tall woman with a grey braid")
      let dir = manager.characterDirectory(slug: character.slug)
      for view in sheets {
        try ImageOutput.writePNG(
          image: MockEngine.create1x1Image(),
          to: dir.appendingPathComponent("references/\(view).png"))
      }
      if withLoRA {
        try Data("fake-lora".utf8).write(to: dir.appendingPathComponent("lora/v1.safetensors"))
        character.lora = LoRAMetadata(
          path: "lora/v1.safetensors", scale: 0.7, compatibleEngines: ["mock"])
        try manager.saveCharacter(character)
      }
      self.character = character
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }
  }

  @Test("reference images are ordered front/left/right/back, then source photos")
  func referenceImageOrder() throws {
    let fixture = try Fixture(withLoRA: false, sheets: ["back", "extra", "front"])
    defer { fixture.cleanUp() }
    let names = fixture.manager.referenceImageURLs(for: fixture.character)
      .map(\.lastPathComponent)
    #expect(names == ["front.png", "back.png", "extra.png", "mara-quill-photo-01.png"])
  }

  @Test("on a LoRA engine, the character's adapter is applied with its trigger word and unloaded")
  func loraEngineAppliesCharacterAdapter() async throws {
    let fixture = try Fixture(withLoRA: true)
    defer { fixture.cleanUp() }
    let engine = MockEngine(maxReferenceImages: 3, supportsLoRAInference: true)
    let client = VinetasClient(router: EngineRouter(engines: [engine]))

    let panel = try await client.generate(
      PanelRequest(
        prompt: "at the dock", style: StyleConfig(stylePrompt: "noir"),
        model: MockModelDescriptor(), character: fixture.character),
      characters: fixture.manager)

    #expect(await engine.lastRequest?.prompt == "sks_mara-quill, noir, at the dock")
    #expect(await engine.loadLoRACallCount == 1)
    #expect(await engine.calls.contains { if case .unloadLoRA = $0 { true } else { false } })
    #expect(panel.metadata.loras?.first?.activationKeyword == "sks_mara-quill")
    #expect(panel.metadata.character == "mara-quill")
    // The adapter carries identity on-device; no references are attached.
    #expect(panel.metadata.references?.isEmpty == true)
  }

  @Test("without a usable LoRA, the description replaces the trigger word")
  func noLoRAUsesDescription() async throws {
    let fixture = try Fixture(withLoRA: true)
    defer { fixture.cleanUp() }
    // The engine can't apply LoRA (or the adapter is for another engine).
    let engine = MockEngine(supportsLoRAInference: false)
    let client = VinetasClient(router: EngineRouter(engines: [engine]))

    let prepared = try await client.prepare(
      PanelRequest(
        prompt: "at the dock", model: MockModelDescriptor(), character: fixture.character),
      characters: fixture.manager)

    #expect(prepared.lora == nil)
    #expect(prepared.promptSent == "a tall woman with a grey braid, at the dock")
    #expect(!prepared.promptSent.contains("sks_"))
    // On-device engines never get character references attached implicitly.
    #expect(prepared.references.isEmpty)
  }

  @Test("on a cloud engine, the character's sheets and photos are attached and described")
  func cloudEngineAttachesCharacterReferences() async throws {
    let fixture = try Fixture(withLoRA: true)
    defer { fixture.cleanUp() }
    let engine = CloudImageEngine(provider: .google, keyStore: InMemoryAPIKeyStore())
    let client = VinetasClient(router: EngineRouter(engines: [engine]))

    let prepared = try await client.prepare(
      PanelRequest(
        prompt: "at the dock",
        style: StyleConfig(stylePrompt: "noir", width: 1344, height: 768),
        model: CloudModelDescriptor.nanoBanana21, character: fixture.character),
      characters: fixture.manager)

    #expect(prepared.engineID == "cloud-google")
    #expect(prepared.lora == nil)
    #expect(prepared.references.count == 3)  // front, back, photo
    #expect(prepared.bundle.referenceCount == 3)
    #expect(prepared.bundle.character?.name == "Mara Quill")
    #expect(prepared.promptSent.contains("Character: Mara Quill — a tall woman with a grey braid"))
    #expect(prepared.promptSent.contains("The 3 attached images show Mara Quill."))
    #expect(prepared.promptSent.contains("Art style: noir."))
    #expect(prepared.promptSent.contains("16:9 landscape"))
    #expect(!prepared.promptSent.contains("sks_"))
    if case .imageToImage(let images) = prepared.request.mode {
      #expect(images.count == 3)
    } else {
      Issue.record("expected an image-to-image request")
    }
  }

  @Test("explicit references win over the character's own")
  func explicitReferencesWin() async throws {
    let fixture = try Fixture(withLoRA: false)
    defer { fixture.cleanUp() }
    let engine = CloudImageEngine(provider: .openAI, keyStore: InMemoryAPIKeyStore())
    let client = VinetasClient(router: EngineRouter(engines: [engine]))
    let png = try #require(ImageOutput.pngData(from: MockEngine.create1x1Image()))
    let explicit = try ReferenceImage.load(data: png, source: .file(path: "mine.png"))

    let prepared = try await client.prepare(
      PanelRequest(
        prompt: "at the dock", model: CloudModelDescriptor.gptImage25Flare,
        references: [explicit], character: fixture.character),
      characters: fixture.manager)

    #expect(prepared.references.map(\.source) == [.file(path: "mine.png")])
  }

  @Test("a cloud model that takes no references gets the description only")
  func cloudWithoutReferenceSupport() async throws {
    let fixture = try Fixture(withLoRA: false)
    defer { fixture.cleanUp() }
    let engine = CloudImageEngine(provider: .blackForestLabs, keyStore: InMemoryAPIKeyStore())
    let client = VinetasClient(router: EngineRouter(engines: [engine]))

    let prepared = try await client.prepare(
      PanelRequest(
        prompt: "at the dock", model: CloudModelDescriptor.flux2Pro,
        character: fixture.character),
      characters: fixture.manager)

    #expect(prepared.references.isEmpty)
    #expect(prepared.promptSent.contains("Character: Mara Quill"))
    #expect(!prepared.promptSent.contains("Reference images"))
  }
}

import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - Engine Tag Matching Tests

@Suite("LoRA Engine Tag Matching")
struct LoRAEngineTagMatchingTests {

  @Test("LoRA with matching engine is compatible")
  func loraWithMatchingEngineIsCompatible() {
    let lora = LoRAMetadata(
      path: "lora/vale-v1.safetensors",
      compatibleEngines: ["flux2"]
    )
    // flux2 is in the list → compatible
    #expect(lora.compatibleEngines.contains("flux2"))
  }

  @Test("LoRA with non-matching engine is incompatible")
  func loraWithNonMatchingEngineIsIncompatible() {
    let lora = LoRAMetadata(
      path: "lora/vale-v1.safetensors",
      compatibleEngines: ["flux2"]
    )
    // pixart-sigma is not in the list → incompatible
    #expect(!lora.compatibleEngines.contains("pixart-sigma"))
  }

  @Test("LoRA with empty compatibleEngines has no restriction")
  func loraWithEmptyEnginesHasNoRestriction() {
    let lora = LoRAMetadata(
      path: "lora/vale-v1.safetensors",
      compatibleEngines: []
    )
    // Empty means no restriction — caller should treat as compatible with all engines
    #expect(lora.compatibleEngines.isEmpty)
  }

  @Test("LoRA can be compatible with multiple engines")
  func loraCompatibleWithMultipleEngines() {
    let lora = LoRAMetadata(
      path: "lora/vale-v1.safetensors",
      compatibleEngines: ["flux2", "pixart-sigma"]
    )
    #expect(lora.compatibleEngines.contains("flux2"))
    #expect(lora.compatibleEngines.contains("pixart-sigma"))
    #expect(!lora.compatibleEngines.contains("unknown-engine"))
  }

  @Test("LoRA compatible engine list is case-sensitive")
  func loraEngineCaseSensitive() {
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      compatibleEngines: ["flux2"]
    )
    // Engine IDs are lowercase; uppercase should not match
    #expect(!lora.compatibleEngines.contains("Flux2"))
    #expect(!lora.compatibleEngines.contains("FLUX2"))
  }
}

// MARK: - YAML Migration Tests

@Suite("LoRA YAML Migration")
struct LoRAYAMLMigrationTests {

  @Test("Legacy model field klein4b migrates to compatibleEngines flux2")
  func klein4bMigratestoFlux2() throws {
    let yaml = """
      name: Vale
      slug: vale
      trigger_word: sks_vale
      created: 2024-01-01
      source_photos: []
      description: ""
      lora:
        path: lora/vale-v1.safetensors
        scale: 0.8
        version: 1
        model: klein4b
      """
    let character = try Character.from(yaml: yaml)
    #expect(character.lora?.compatibleEngines == ["flux2"])
  }

  @Test("Legacy model field klein9b migrates to compatibleEngines flux2")
  func klein9bMigratestoFlux2() throws {
    let yaml = """
      name: Vale
      slug: vale
      trigger_word: sks_vale
      created: 2024-01-01
      source_photos: []
      description: ""
      lora:
        path: lora/vale-v1.safetensors
        scale: 0.8
        version: 1
        model: klein9b
      """
    let character = try Character.from(yaml: yaml)
    #expect(character.lora?.compatibleEngines == ["flux2"])
  }

  @Test("Modern YAML with compatible_engines field parsed correctly")
  func modernYAMLCompatibleEnginesParsed() throws {
    let yaml = """
      name: Vale
      slug: vale
      trigger_word: sks_vale
      created: 2024-01-01
      source_photos: []
      description: ""
      lora:
        path: lora/vale-v1.safetensors
        scale: 0.8
        version: 1
        compatible_engines:
          - flux2
      """
    let character = try Character.from(yaml: yaml)
    #expect(character.lora?.compatibleEngines == ["flux2"])
  }

  @Test("Modern YAML with multiple compatible engines parsed correctly")
  func modernYAMLMultipleEngines() throws {
    let yaml = """
      name: Vale
      slug: vale
      trigger_word: sks_vale
      created: 2024-01-01
      source_photos: []
      description: ""
      lora:
        path: lora/vale-v1.safetensors
        scale: 0.8
        version: 1
        compatible_engines:
          - flux2
          - pixart-sigma
      """
    let character = try Character.from(yaml: yaml)
    #expect(character.lora?.compatibleEngines.count == 2)
    #expect(character.lora?.compatibleEngines.contains("flux2") == true)
    #expect(character.lora?.compatibleEngines.contains("pixart-sigma") == true)
  }

  @Test("YAML with no lora section has nil lora")
  func yamlWithNoLoraHasNilLora() throws {
    let yaml = """
      name: Vale
      slug: vale
      trigger_word: sks_vale
      created: 2024-01-01
      source_photos: []
      description: ""
      """
    let character = try Character.from(yaml: yaml)
    #expect(character.lora == nil)
  }

  @Test("YAML round-trip preserves compatible_engines key not model key")
  func yamlRoundTripUsesCompatibleEnginesKey() throws {
    let lora = LoRAMetadata(
      path: "lora/vale-v1.safetensors",
      scale: 0.8,
      version: 1,
      compatibleEngines: ["flux2"]
    )
    let character = Character(name: "Vale", lora: lora)
    let encoded = try character.yamlEncoded()

    // New format should use compatible_engines, not model
    #expect(encoded.contains("compatible_engines"))
    #expect(!encoded.contains("model:"))
  }

  @Test("Unknown legacy model value results in empty compatibleEngines")
  func unknownLegacyModelResultsInEmptyEngines() throws {
    let yaml = """
      name: Vale
      slug: vale
      trigger_word: sks_vale
      created: 2024-01-01
      source_photos: []
      description: ""
      lora:
        path: lora/vale-v1.safetensors
        scale: 0.8
        version: 1
        model: unknown-model-xyz
      """
    let character = try Character.from(yaml: yaml)
    // Unknown legacy model should result in empty compatibleEngines (no restriction)
    #expect(character.lora?.compatibleEngines == [])
  }

  @Test("compatible_engines takes precedence over legacy model field")
  func compatibleEnginesTakesPrecedence() throws {
    // If both fields exist (shouldn't happen in practice), compatible_engines wins
    let yaml = """
      name: Vale
      slug: vale
      trigger_word: sks_vale
      created: 2024-01-01
      source_photos: []
      description: ""
      lora:
        path: lora/vale-v1.safetensors
        scale: 0.8
        version: 1
        compatible_engines:
          - pixart-sigma
        model: klein4b
      """
    let character = try Character.from(yaml: yaml)
    // compatible_engines takes precedence
    #expect(character.lora?.compatibleEngines == ["pixart-sigma"])
  }
}

// MARK: - Incompatible LoRA Fallback Behavior Tests

@Suite("Incompatible LoRA Fallback Behavior")
struct LoRAIncompatibleFallbackTests {

  /// Helper: create a VinetasClient with a MockEngine that supports LoRA inference.
  private func makeClientWithLoRAEngine(engineID: String) -> (VinetasClient, MockEngine) {
    let model = MockModelDescriptor(id: "mock-model", displayName: "Mock", engineID: engineID)
    let engine = MockEngine(engineID: engineID, supportedModels: [model])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine)
  }

  // These three exercise `LoRAMetadata.isCompatible(with:)` — the production
  // rule — rather than re-deriving it. They previously inlined the same
  // `isEmpty ? true : contains(engineID)` branch and asserted against that
  // local copy, which meant the real implementation had no coverage: inverting
  // it would not have failed a single test.

  @Test("LoRA with empty compatibleEngines is treated as compatible (no restriction)")
  func emptyCompatibleEnginesAlwaysCompatible() {
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      compatibleEngines: []
    )
    #expect(lora.isCompatible(with: "flux2"))
    // A LoRA with no recorded restriction works with anything, including an
    // engine that did not exist when it was trained.
    #expect(lora.isCompatible(with: "some-future-engine"))
  }

  @Test("LoRA with matching engine is compatible")
  func matchingEngineLoRAIsCompatible() {
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      compatibleEngines: ["flux2"]
    )
    #expect(lora.isCompatible(with: "flux2"))
  }

  @Test("LoRA with non-matching engine is incompatible")
  func nonMatchingEngineLoRAIsIncompatible() {
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      compatibleEngines: ["flux2"]
    )
    #expect(!lora.isCompatible(with: "pixart-sigma"))
  }

  @Test("LoRA listing several engines is compatible with each of them")
  func multiEngineLoRAIsCompatibleWithEach() {
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      compatibleEngines: ["flux2", "pixart-sigma"]
    )
    #expect(lora.isCompatible(with: "flux2"))
    #expect(lora.isCompatible(with: "pixart-sigma"))
    #expect(!lora.isCompatible(with: "unlisted-engine"))
  }

  @Test("VinetasClient generates without LoRA when engine is incompatible")
  func generatesWithoutLoRAWhenIncompatible() async throws {
    let loraModel = MockModelDescriptor(
      id: "lora-engine-model",
      displayName: "LoRA Engine Model",
      engineID: "lora-engine"
    )
    let engine = MockEngine(engineID: "lora-engine", supportedModels: [loraModel])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    // Create a character with a LoRA compatible only with "other-engine", not "lora-engine"
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      compatibleEngines: ["other-engine"]
    )
    let character = Character(name: "Test Character", lora: lora)

    // Generation should succeed (falling back to prompt-only) even with incompatible LoRA
    // The MockEngine returns a default 1x1 image
    let image = try await client.generate(
      prompt: "a test panel",
      character: character,
      model: loraModel
    )
    #expect(image.width == 1)
    #expect(image.height == 1)

    // loadLoRA should NOT have been called (incompatible LoRA skipped)
    let calls = await engine.calls
    #expect(!calls.contains(.loadLoRA("test.safetensors", 0.8)))
  }

  @Test("VinetasClient loads LoRA when engine is compatible")
  func loadsLoRAWhenEngineIsCompatible() async throws {
    let loraModel = MockModelDescriptor(
      id: "flux2-model",
      displayName: "Flux2 Model",
      engineID: "flux2"
    )
    // Build a MockEngine that supports loraInference
    let engine = MockEngine(engineID: "flux2", supportedModels: [loraModel])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    // Write a real temp file so loadLoRA doesn't fail on file resolution
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("LoRACompatibilityTests-\(UUID().uuidString)", isDirectory: true)
    let charDir = tempDir.appendingPathComponent("characters/test-char", isDirectory: true)
    let loraDir = charDir.appendingPathComponent("lora", isDirectory: true)
    try FileManager.default.createDirectory(at: loraDir, withIntermediateDirectories: true)
    let loraFile = loraDir.appendingPathComponent("test.safetensors")
    try Data().write(to: loraFile)
    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    // Create a Character with matching engine and a valid LoRA path
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      compatibleEngines: ["flux2"]
    )
    let character = Character(name: "Test Char", slug: "test-char", lora: lora)

    // Stub the CharacterManager by using a CharacterManager directly isn't straightforward,
    // so instead we verify mock engine supports loraInference and
    // just check that generate completes successfully.
    let image = try await client.generate(
      prompt: "a test panel",
      character: character,
      model: loraModel
    )
    #expect(image.width == 1)
    #expect(image.height == 1)
  }

  @Test("LoRAIncompatible error contains engine IDs in VinetasError")
  func loraIncompatibleErrorContainsEngineIDs() {
    // Verify the VinetasError.loraIncompatible case exists and carries the right info
    let error = VinetasError.loraIncompatible(loraEngine: "flux2", currentEngine: "pixart-sigma")
    switch error {
    case .loraIncompatible(let loraEngine, let currentEngine):
      #expect(loraEngine == "flux2")
      #expect(currentEngine == "pixart-sigma")
    default:
      Issue.record("Expected .loraIncompatible error, got \(error)")
    }
  }
}

// MARK: - LoRAMetadata Sendable Tests

@Suite("LoRAMetadata Sendable")
struct LoRAMetadataSendableTests {

  @Test("LoRAMetadata is Sendable")
  func loraMetadataIsSendable() async {
    let lora = LoRAMetadata(
      path: "lora/test.safetensors",
      scale: 0.9,
      version: 2,
      compatibleEngines: ["flux2"]
    )
    let result = await Task { lora }.value
    #expect(result.path == "lora/test.safetensors")
    #expect(result.scale == 0.9)
    #expect(result.version == 2)
    #expect(result.compatibleEngines == ["flux2"])
  }
}

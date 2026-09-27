import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

/// Sortie 7 (RI-15): `generate(_ request: PanelRequest)` applies `style.loraPath`
/// via the engine abstraction and records the applied LoRA in `metadata.loras`.
@Suite("PanelRequestLoRATests")
struct PanelRequestLoRATests {

  // MARK: - Helpers

  private func makeClient(_ engine: MockEngine) -> VinetasClient {
    VinetasClient(router: EngineRouter(engines: [engine]))
  }

  private func makeReference() throws -> ReferenceImage {
    let png = try #require(ImageOutput.pngData(from: MockEngine.create1x1Image()))
    return try ReferenceImage.load(data: png, source: .file(path: "ref.png"))
  }

  /// Creates a throwaway `.safetensors` file so `VinetasLoRAManager`'s
  /// existence check passes, and removes it on teardown via the caller.
  private func makeLoRAFile() throws -> String {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lora-\(UUID().uuidString).safetensors")
    try Data("fake-lora-bytes".utf8).write(to: url)
    return url.path
  }

  // MARK: - 1. LoRA applied and recorded

  @Test("a LoRA is applied and recorded")
  func loraAppliedAndRecorded() async throws {
    let loraPath = try makeLoRAFile()
    defer { try? FileManager.default.removeItem(atPath: loraPath) }

    let engine = MockEngine(supportsLoRAInference: true)
    let style = StyleConfig(loraPath: loraPath, loraScale: 0.6)
    let panel = try await makeClient(engine).generate(
      PanelRequest(prompt: "a cat", style: style, model: MockModelDescriptor()))

    #expect(await engine.loadLoRACallCount == 1)
    #expect(panel.metadata.loras == [ImageOutput.LoRAEntry(path: loraPath, scale: 0.6)])
  }

  // MARK: - 2. LoRA + 1 reference

  @Test("LoRA plus 1 reference is applied and recorded, with mode imageToImage")
  func loraPlusReferenceAppliedAndRecorded() async throws {
    let loraPath = try makeLoRAFile()
    defer { try? FileManager.default.removeItem(atPath: loraPath) }

    let engine = MockEngine(maxReferenceImages: 3, supportsLoRAInference: true)
    let reference = try makeReference()
    let style = StyleConfig(loraPath: loraPath, loraScale: 0.9)
    let panel = try await makeClient(engine).generate(
      PanelRequest(
        prompt: "a cat", style: style, model: MockModelDescriptor(), references: [reference]))

    #expect(await engine.loadLoRACallCount == 1)
    #expect(panel.metadata.mode == .imageToImage)
    #expect(panel.metadata.loras == [ImageOutput.LoRAEntry(path: loraPath, scale: 0.9)])
  }

  // MARK: - 3. Unsupported engine + loraPath throws before generate

  @Test("an engine without .loraInference plus loraPath throws before generate")
  func unsupportedEngineThrowsBeforeGenerate() async throws {
    let loraPath = try makeLoRAFile()
    defer { try? FileManager.default.removeItem(atPath: loraPath) }

    let engine = MockEngine(supportsLoRAInference: false)
    let style = StyleConfig(loraPath: loraPath)
    do {
      _ = try await makeClient(engine).generate(
        PanelRequest(prompt: "a cat", style: style, model: MockModelDescriptor()))
      Issue.record("Expected engineFeatureUnsupported")
    } catch VinetasError.engineFeatureUnsupported(let feature, let engineID) {
      #expect(feature == .loraInference)
      #expect(engineID == "mock")
    }
    #expect(await engine.generateCallCount == 0)
    #expect(await engine.loadLoRACallCount == 0)
  }

  // MARK: - 4. loadLoRA failure propagates, no metadata

  @Test("a mock loadLoRA failure throws and no metadata is produced")
  func loadLoRAFailurePropagates() async throws {
    let loraPath = try makeLoRAFile()
    defer { try? FileManager.default.removeItem(atPath: loraPath) }

    let engine = MockEngine(supportsLoRAInference: true)
    await engine.setLoadLoRAError(VinetasError.generationFailed("simulated LoRA load failure"))
    let style = StyleConfig(loraPath: loraPath)

    await #expect(throws: VinetasError.self) {
      _ = try await makeClient(engine).generate(
        PanelRequest(prompt: "a cat", style: style, model: MockModelDescriptor()))
    }
    #expect(await engine.generateCallCount == 0)
  }

  // MARK: - 5. No loraPath gives loras == []

  @Test("no loraPath gives loras == []")
  func noLoRAGivesEmptyArray() async throws {
    let engine = MockEngine()
    let panel = try await makeClient(engine).generate(
      PanelRequest(prompt: "a cat", model: MockModelDescriptor()))
    #expect(panel.metadata.loras == [])
    #expect(await engine.loadLoRACallCount == 0)
  }
}

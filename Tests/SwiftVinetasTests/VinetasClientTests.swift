import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

@Suite("VinetasClient")
struct VinetasClientTests {

  // MARK: - Shared Helpers

  /// Creates a default mock engine and descriptor pair for routing tests.
  private func makeMockClient() -> (client: VinetasClient, engine: MockEngine, descriptor: MockModelDescriptor) {
    let engine = MockEngine()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine, descriptor)
  }

  // MARK: - Tests

  @Test func generateRoutesToCorrectEngine() async throws {
    let (client, engine, descriptor) = makeMockClient()

    _ = try await client.generate(prompt: "test", model: descriptor)

    let calls = await engine.calls
    #expect(calls.contains(.loadModel("mock-model")))
    #expect(calls.contains(.generate("test")))
  }

  @Test func generateWithWhitespaceOnlyPromptThrows() async throws {
    let (client, _, descriptor) = makeMockClient()

    await #expect(throws: VinetasError.self) {
      _ = try await client.generate(prompt: "   ", model: descriptor)
    }
  }

  @Test func isAvailableDelegatesToEngine() async throws {
    let engine = MockEngine()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    engine.isAvailableResult = true
    let resultTrue = try await client.isAvailable(descriptor)
    #expect(resultTrue == true)

    engine.isAvailableResult = false
    let resultFalse = try await client.isAvailable(descriptor)
    #expect(resultFalse == false)
  }

  @Test func validateMemoryDelegatesToEngine() async throws {
    let engine = MockEngine()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)

    // Test .ok
    engine.validateMemoryResult = .ok
    let resultOK = try await client.validateMemory(for: descriptor)
    if case .ok = resultOK {
      // pass
    } else {
      Issue.record("Expected .ok but got \(resultOK)")
    }

    // Test .insufficient
    let requiredBytes: UInt64 = 16 * 1_073_741_824
    let availableBytes: UInt64 = 8 * 1_073_741_824
    engine.validateMemoryResult = .insufficient(required: requiredBytes, available: availableBytes)
    let resultInsufficient = try await client.validateMemory(for: descriptor)
    if case .insufficient(let required, let available) = resultInsufficient {
      #expect(required == requiredBytes)
      #expect(available == availableBytes)
    } else {
      Issue.record("Expected .insufficient but got \(resultInsufficient)")
    }
  }

  @Test func previewRoutesToFlux2Engine() async throws {
    let flux2Engine = MockEngine(
      engineID: "flux2",
      supportedModels: [Flux2ModelDescriptor.klein4B]
    )
    let router = EngineRouter(engines: [flux2Engine])
    let client = VinetasClient(router: router)

    _ = try await client.preview(prompt: "test")

    let calls = await flux2Engine.calls
    #expect(calls.contains(.loadModel("flux2-klein-4b")))
  }
}

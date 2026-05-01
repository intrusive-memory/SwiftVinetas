import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

@Suite("VinetasClient")
struct VinetasClientTests {

  // MARK: - Shared Helpers

  /// Creates a default mock engine and descriptor pair for routing tests.
  private func makeMockClient() -> (
    client: VinetasClient, engine: MockEngine, descriptor: MockModelDescriptor
  ) {
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

  #if !VINETAS_FLUX2_DISABLED
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
  #endif
}

// MARK: - generateSequence Tests

/// Concurrency-safe collector for (current, total) panel-progress tuples.
/// `@unchecked Sendable` is safe here because all mutations happen serially
/// within the single async task that drives `generateSequence`.
private final class PanelProgressCollector: @unchecked Sendable {
  private(set) var records: [(current: Int, total: Int)] = []
  func record(current: Int, total: Int) { records.append((current, total)) }
}

/// Concurrency-safe collector for (step, totalSteps) step-progress tuples.
/// `@unchecked Sendable` is safe here because `MockEngine.generate` fires
/// callbacks synchronously before returning, so all appends complete before
/// the outer `generateSequence` call returns.
private final class StepProgressCollector: @unchecked Sendable {
  private(set) var records: [(step: Int, totalSteps: Int)] = []
  func record(step: Int, totalSteps: Int) { records.append((step: step, totalSteps: totalSteps)) }
}

@Suite("VinetasClient.generateSequence")
struct VinetasClientGenerateSequenceTests {

  private func makeMockClient() -> (client: VinetasClient, engine: MockEngine) {
    let engine = MockEngine()
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine)
  }

  @Test func generateSequenceCallsEngineOncePerPrompt() async throws {
    let (client, engine) = makeMockClient()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")

    _ = try await client.generateSequence(prompts: ["a", "b", "c"], model: descriptor)

    let calls = await engine.calls
    let generateCalls = calls.filter {
      if case .generate = $0 { return true }
      return false
    }
    #expect(generateCalls.count == 3)
  }

  @Test func generateSequenceDeliversPanelProgressCallbacks() async throws {
    let (client, _) = makeMockClient()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")

    let collector = PanelProgressCollector()
    _ = try await client.generateSequence(
      prompts: ["a", "b", "c"],
      model: descriptor,
      progress: { current, total in
        collector.record(current: current, total: total)
      }
    )

    let records = collector.records
    let expectedCurrents = [1, 2, 3]
    let expectedTotal = 3
    #expect(records.count == expectedCurrents.count)
    for (idx, record) in records.enumerated() {
      #expect(record.current == expectedCurrents[idx])
      #expect(record.total == expectedTotal)
    }
  }

  @Test func generateSequenceDeliversStepProgressCallbacks() async throws {
    let (client, engine) = makeMockClient()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")
    await engine.setGenerateStepCount(4)

    let collector = StepProgressCollector()
    _ = try await client.generateSequence(
      prompts: ["a", "b", "c"],
      model: descriptor,
      stepProgress: { step, totalSteps, _ in
        collector.record(step: step, totalSteps: totalSteps)
      }
    )

    let records = collector.records
    // 3 prompts × 4 steps each = 12 callbacks
    #expect(records.count == 12)
    // Verify steps increment from 1 to 4 for each panel
    for panelIndex in 0..<3 {
      let base = panelIndex * 4
      #expect(records[base + 0].step == 1)
      #expect(records[base + 1].step == 2)
      #expect(records[base + 2].step == 3)
      #expect(records[base + 3].step == 4)
      for i in 0..<4 {
        #expect(records[base + i].totalSteps == 4)
      }
    }
  }

  @Test func generateSequenceWithEmptyPromptsReturnsEmptyArray() async throws {
    let (client, engine) = makeMockClient()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")

    let result = try await client.generateSequence(prompts: [], model: descriptor)

    #expect(result.isEmpty)
    let calls = await engine.calls
    let generateCalls = calls.filter {
      if case .generate = $0 { return true }
      return false
    }
    #expect(generateCalls.isEmpty)
  }
}

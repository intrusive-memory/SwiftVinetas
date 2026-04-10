// These tests validate actor isolation on EngineRouter and @unchecked Sendable discipline on MockEngine under Swift 6 strict concurrency.

import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

@Suite("VinetasClient Concurrency")
struct ConcurrentClientTests {

  // MARK: - Helpers

  private func makeClient() -> (client: VinetasClient, engine: MockEngine) {
    let engine = MockEngine()
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine)
  }

  // MARK: - Tests

  /// Two independent clients backed by separate MockEngines run generateSequence
  /// concurrently. Actor isolation prevents any state leakage between the two
  /// EngineRouter actors.
  @Test func concurrentGenerateSequenceCallsDoNotRace() async throws {
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")

    let (client1, _) = makeClient()
    let (client2, _) = makeClient()

    async let images1 = client1.generateSequence(prompts: ["a", "b", "c"], model: descriptor)
    async let images2 = client2.generateSequence(prompts: ["a", "b", "c"], model: descriptor)

    let (result1, result2) = try await (images1, images2)

    #expect(result1.count == 3)
    #expect(result2.count == 3)
  }

  /// Five concurrent generate() calls on the same VinetasClient are serialized
  /// through the actor-isolated EngineRouter and MockEngine. All five calls must
  /// complete without throwing, and the engine's call log must record exactly
  /// five .generate entries.
  @Test func concurrentGenerateCallsOnSameClientAreSerializedByActor() async throws {
    let (client, engine) = makeClient()
    let descriptor = MockModelDescriptor(id: "mock-model", engineID: "mock")

    try await withThrowingTaskGroup(of: CGImage.self) { group in
      for i in 0..<5 {
        group.addTask {
          try await client.generate(prompt: "prompt-\(i)", model: descriptor)
        }
      }
      // Collect all results to ensure all tasks complete without throwing.
      var completedCount = 0
      for try await _ in group {
        completedCount += 1
      }
      #expect(completedCount == 5)
    }

    let calls = await engine.calls
    let generateCalls = calls.filter {
      if case .generate = $0 { return true }
      return false
    }
    #expect(generateCalls.count == 5)
  }
}

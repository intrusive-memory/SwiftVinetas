import Foundation
import Testing

@testable import SwiftVinetas

/// Tests for the engine-eviction primitives added for SwiftVinetas#41:
/// `EngineRouter.unloadAllEngines()` / `evictEngine(forEngineID:)` and the
/// `VinetasClient.unloadAll()` / `evictEngine(forEngineID:)` convenience.
@Suite("Engine Eviction")
struct EngineEvictionTests {

  /// Build two mock engines with distinct IDs and a client wrapping them.
  private func makeClient() -> (VinetasClient, MockEngine, MockEngine) {
    let modelA = MockModelDescriptor(id: "model-a", displayName: "Alpha", engineID: "engine-a")
    let modelB = MockModelDescriptor(id: "model-b", displayName: "Beta", engineID: "engine-b")
    let engineA = MockEngine(engineID: "engine-a", supportedModels: [modelA])
    let engineB = MockEngine(engineID: "engine-b", supportedModels: [modelB])
    let router = EngineRouter(engines: [engineA, engineB])
    let client = VinetasClient(router: router)
    return (client, engineA, engineB)
  }

  // MARK: - unloadAll fan-out

  @Test("unloadAll() fans out unloadModel to every registered engine")
  func unloadAllFansOut() async throws {
    let (client, engineA, engineB) = makeClient()

    await client.unloadAll()

    let callsA = await engineA.calls
    let callsB = await engineB.calls
    #expect(callsA.contains(.unloadModel))
    #expect(callsB.contains(.unloadModel))
  }

  @Test("router.unloadAllEngines() fans out unloadModel to every engine")
  func routerUnloadAllFansOut() async throws {
    let modelA = MockModelDescriptor(id: "model-a", displayName: "Alpha", engineID: "engine-a")
    let modelB = MockModelDescriptor(id: "model-b", displayName: "Beta", engineID: "engine-b")
    let engineA = MockEngine(engineID: "engine-a", supportedModels: [modelA])
    let engineB = MockEngine(engineID: "engine-b", supportedModels: [modelB])
    let router = EngineRouter(engines: [engineA, engineB])

    await router.unloadAllEngines()

    let callsA = await engineA.calls
    let callsB = await engineB.calls
    #expect(callsA.filter { $0 == .unloadModel }.count == 1)
    #expect(callsB.filter { $0 == .unloadModel }.count == 1)
  }

  // MARK: - evictEngine targeting

  @Test("evictEngine(forEngineID:) unloads only the targeted engine")
  func evictTargetsSingleEngine() async throws {
    let (client, engineA, engineB) = makeClient()

    await client.evictEngine(forEngineID: "engine-a")

    let callsA = await engineA.calls
    let callsB = await engineB.calls
    #expect(callsA.contains(.unloadModel))
    #expect(!callsB.contains(.unloadModel))
  }

  @Test("evictEngine(forEngineID:) is a no-op for an unknown engine ID")
  func evictUnknownIsNoOp() async throws {
    let (client, engineA, engineB) = makeClient()

    // Must not throw and must not unload any registered engine.
    await client.evictEngine(forEngineID: "does-not-exist")

    let callsA = await engineA.calls
    let callsB = await engineB.calls
    #expect(!callsA.contains(.unloadModel))
    #expect(!callsB.contains(.unloadModel))
  }

  // MARK: - Idempotency

  @Test("unloadAll() is safe to call repeatedly")
  func unloadAllIdempotent() async throws {
    let (client, engineA, engineB) = makeClient()

    await client.unloadAll()
    await client.unloadAll()

    // Second call still safe; each engine records a second unloadModel.
    let callsA = await engineA.calls
    let callsB = await engineB.calls
    #expect(callsA.filter { $0 == .unloadModel }.count == 2)
    #expect(callsB.filter { $0 == .unloadModel }.count == 2)
  }

  @Test("unloadAllEngines() over an empty router is safe")
  func unloadAllEmptyRouter() async throws {
    let router = EngineRouter(engines: [])
    // Should complete without throwing or trapping.
    await router.unloadAllEngines()
  }
}

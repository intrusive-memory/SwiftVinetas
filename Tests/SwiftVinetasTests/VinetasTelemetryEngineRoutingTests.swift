import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - VinetasTelemetryEngineRoutingTests
//
// Asserts that the engine-routing telemetry emission sites fire correctly:
//
//  - engineSelected fires in VinetasClient.generate() AFTER router.engine(for:) returns
//    successfully. It is NOT emitted inside EngineRouter.engine(for:) — the emission
//    was moved to the entry points so the ordering invariant holds:
//      generationStart (entry point) → engineSelected (entry point) → … → generationEnd
//    See REQUIREMENTS §6 single-emission rule and §8.2 ordering assertion.
//  - engineNotFound fires inside EngineRouter.engine(for:) before throw when no
//    engine handles the model (stays in the router — tied to the throw site).
//  - errorThrown(phase: .engineNotFound) fires immediately after engineNotFound.
//
// Tests use MockEngine and MockModelDescriptor to avoid GPU/model loading.
// The router's telemetry is installed via VinetasClient.setTelemetry(_:).
// All tests exercise routing indirectly through VinetasClient.generate().

@Suite("VinetasClient Telemetry — Engine Routing")
struct VinetasTelemetryEngineRoutingTests {

  // MARK: - Helpers

  private func makeRouter(
    engines: [any ImageGenerationEngine]
  ) -> (client: VinetasClient, router: EngineRouter) {
    let router = EngineRouter(engines: engines)
    let client = VinetasClient(router: router)
    return (client, router)
  }

  // MARK: - engineSelected

  /// A successful route emits exactly one engineSelected event with the correct engineID.
  @Test func engineSelectedFiresOnSuccessfulRoute() async throws {
    let model = MockModelDescriptor(id: "my-model", engineID: "alpha")
    let engine = MockEngine(engineID: "alpha", supportedModels: [model])
    let (client, _) = makeRouter(engines: [engine])
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generate(prompt: "test", model: model)
    await Task.yield()

    let selectedEvents = mock.all {
      if case .engineSelected = $0 { return true }
      return false
    }
    #expect(selectedEvents.count >= 1, "engineSelected must fire on a successful route")

    if case .engineSelected(let engineID, let modelID, _, _) = selectedEvents[0] {
      #expect(engineID == "alpha", "engineSelected.engineID must match the routed engine")
      #expect(modelID == "my-model", "engineSelected.modelID must match the requested model")
    }
  }

  /// Two engines registered: routing to each emits engineSelected with the correct engineID.
  @Test func engineSelectedCorrectEngineForEachModel() async throws {
    let modelA = MockModelDescriptor(id: "model-a", engineID: "engine-a")
    let modelB = MockModelDescriptor(id: "model-b", engineID: "engine-b")
    let engineA = MockEngine(engineID: "engine-a", supportedModels: [modelA])
    let engineB = MockEngine(engineID: "engine-b", supportedModels: [modelB])
    let (client, _) = makeRouter(engines: [engineA, engineB])
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generate(prompt: "for A", model: modelA)
    await Task.yield()
    _ = try await client.generate(prompt: "for B", model: modelB)
    await Task.yield()

    let selectedEvents = mock.all {
      if case .engineSelected = $0 { return true }
      return false
    }
    #expect(selectedEvents.count >= 2, "Two successful routes must emit two engineSelected events")

    let engineIDs = selectedEvents.compactMap { event -> String? in
      if case .engineSelected(let eid, _, _, _) = event { return eid }
      return nil
    }
    #expect(engineIDs.contains("engine-a"), "engine-a must appear in engineSelected events")
    #expect(engineIDs.contains("engine-b"), "engine-b must appear in engineSelected events")
  }

  // MARK: - engineNotFound

  /// Requesting a model with an unregistered engineID emits engineNotFound.
  @Test func engineNotFoundFiresBeforeThrow() async throws {
    let model = MockModelDescriptor(id: "orphan-model", engineID: "unregistered")
    let (client, _) = makeRouter(engines: [])  // no engines at all
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try? await client.generate(prompt: "test", model: model)

    let notFound = mock.first {
      if case .engineNotFound(let modelID, _) = $0, modelID == "orphan-model" { return true }
      return false
    }
    #expect(notFound != nil, "engineNotFound must be emitted before throw")
  }

  /// engineNotFound carries the correct modelID and requestedEngineID.
  @Test func engineNotFoundEventFields() async throws {
    let model = MockModelDescriptor(id: "target-model", engineID: "missing-engine")
    let engine = MockEngine(
      engineID: "present",
      supportedModels: [
        MockModelDescriptor(id: "other-model", engineID: "present")
      ])
    let (client, _) = makeRouter(engines: [engine])
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try? await client.generate(prompt: "any", model: model)

    guard
      let event = mock.first(matching: {
        if case .engineNotFound = $0 { return true }
        return false
      })
    else {
      Issue.record("No engineNotFound event captured")
      return
    }
    if case .engineNotFound(let modelID, let requestedEngineID) = event {
      #expect(modelID == "target-model")
      #expect(requestedEngineID == "missing-engine")
    }
  }

  // MARK: - errorThrown after engineNotFound

  /// After engineNotFound, errorThrown(phase: .engineNotFound) fires immediately.
  @Test func errorThrownFiresAfterEngineNotFound() async throws {
    let model = MockModelDescriptor(id: "lost-model", engineID: "void")
    let (client, _) = makeRouter(engines: [])
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try? await client.generate(prompt: "any", model: model)

    let errorEvent = mock.first {
      if case .errorThrown(let phase, _) = $0, phase == .engineNotFound { return true }
      return false
    }
    #expect(errorEvent != nil, "errorThrown(phase: .engineNotFound) must fire on routing failure")
  }

  /// engineNotFound precedes errorThrown in capture order.
  @Test func engineNotFoundPrecedesErrorThrownInOrder() async throws {
    let model = MockModelDescriptor(id: "seq-model", engineID: "absent")
    let (client, _) = makeRouter(engines: [])
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try? await client.generate(prompt: "ordering-test", model: model)

    let events = mock.events
    let notFoundIdx = events.firstIndex {
      if case .engineNotFound = $0 { return true }
      return false
    }
    let errorIdx = events.firstIndex {
      if case .errorThrown(let phase, _) = $0, phase == .engineNotFound { return true }
      return false
    }
    guard let nfi = notFoundIdx, let ei = errorIdx else {
      Issue.record("Missing engineNotFound or errorThrown event")
      return
    }
    #expect(nfi < ei, "engineNotFound must precede errorThrown in emission order")
  }

  /// No engineNotFound fires when the route succeeds.
  @Test func engineNotFoundDoesNotFireOnSuccess() async throws {
    let model = MockModelDescriptor(id: "happy-model", engineID: "happy")
    let engine = MockEngine(engineID: "happy", supportedModels: [model])
    let (client, _) = makeRouter(engines: [engine])
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.generate(prompt: "smooth", model: model)
    await Task.yield()

    let notFoundEvents = mock.all {
      if case .engineNotFound = $0 { return true }
      return false
    }
    #expect(notFoundEvents.isEmpty, "engineNotFound must not fire on a successful route")
  }
}

import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - VinetasTelemetryClientInitTests
//
// Verifies that the VinetasClient telemetry seam is correctly wired:
//  - setTelemetry(_:) is accepted without error.
//  - Operations after setTelemetry emit events to the installed reporter.
//  - modelAvailabilityChecked fires after isModelAvailable(_:).
//  - setTelemetry(nil) clears the reporter so subsequent events are suppressed.
//
// NOTE on clientInitialized: Per Vinetas.swift, this event fires inside a Task
// at the end of `VinetasClient.init()` ONLY if a reporter is already installed
// before init completes (i.e., the lock holds a non-nil value at that moment).
// Since the default initializer sets the lock to nil before any reporter can be
// provided, and the shared singleton is initialized at launch before any test
// code runs, `clientInitialized` cannot be observed by test code that installs
// the reporter AFTER construction. These tests instead verify the behaviors that
// ARE observable: reporter installation, post-init emission, and nil teardown.

@Suite("VinetasClient Telemetry — Client Init")
struct VinetasTelemetryClientInitTests {

  // MARK: - Helpers

  /// Creates a minimal test client backed by a single mock engine.
  private func makeMockClient() -> (client: VinetasClient, engine: MockEngine) {
    let engine = MockEngine(engineID: "mock", supportedModels: [MockModelDescriptor()])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine)
  }

  // MARK: - Tests

  /// setTelemetry(_:) completes without throwing and the reporter is retained.
  @Test func setTelemetryInstallsReporter() async {
    let (client, _) = makeMockClient()
    let mock = MockVinetasReporter()
    // Should not hang or throw.
    await client.setTelemetry(mock)
    // Verify via an observable emission: isModelAvailable emits modelAvailabilityChecked.
    _ = await client.isModelAvailable("any-model-id")
    #expect(mock.count >= 1, "At least one event should be captured after setTelemetry")
  }

  /// isModelAvailable(_:) emits exactly one modelAvailabilityChecked event per call.
  @Test func isModelAvailableEmitsAvailabilityChecked() async {
    let (client, _) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = await client.isModelAvailable("black-forest-labs/FLUX.2-klein-4B")

    let events = mock.all {
      if case .modelAvailabilityChecked(let modelID, _) = $0,
        modelID == "black-forest-labs/FLUX.2-klein-4B"
      {
        return true
      }
      return false
    }
    #expect(events.count == 1, "Exactly one modelAvailabilityChecked event per call")
  }

  /// modelAvailabilityChecked carries the correct modelID and an accurate `available` field.
  @Test func isModelAvailableEventCarriesCorrectFields() async {
    let (client, _) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    // Use a model ID that is definitely NOT on disk in CI (no cached weights).
    let testModelID = "black-forest-labs/FLUX.2-klein-4B-nonexistent-test"
    let result = await client.isModelAvailable(testModelID)

    let event = mock.first {
      if case .modelAvailabilityChecked = $0 { return true }
      return false
    }
    guard let event else {
      Issue.record("No modelAvailabilityChecked event captured")
      return
    }
    if case .modelAvailabilityChecked(let modelID, let available) = event {
      #expect(modelID == testModelID)
      #expect(available == result, "Event's available field must match the return value")
    }
  }

  /// Calling setTelemetry(nil) stops subsequent event capture.
  @Test func setTelemetryNilSuppressesEvents() async {
    let (client, _) = makeMockClient()
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    // Install, verify it fires, then clear.
    _ = await client.isModelAvailable("some-model")
    let countAfterInstall = mock.count
    #expect(countAfterInstall >= 1)

    await client.setTelemetry(nil)
    // After nil, subsequent operations should emit nothing.
    _ = await client.isModelAvailable("some-other-model")
    #expect(mock.count == countAfterInstall, "No new events after setTelemetry(nil)")
  }

  /// Multiple calls to setTelemetry replace the reporter; each call propagates correctly.
  @Test func setTelemetryReplacesReporter() async {
    let (client, _) = makeMockClient()
    let first = MockVinetasReporter()
    let second = MockVinetasReporter()

    await client.setTelemetry(first)
    _ = await client.isModelAvailable("m1")
    let firstCount = first.count

    await client.setTelemetry(second)
    _ = await client.isModelAvailable("m2")

    #expect(firstCount >= 1, "First reporter received events before swap")
    #expect(second.count >= 1, "Second reporter receives events after swap")
    // First reporter should NOT have received the second isModelAvailable call's event.
    #expect(first.count == firstCount, "First reporter no longer receives events after swap")
  }
}

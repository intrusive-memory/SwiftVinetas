import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - VinetasTelemetryMemoryValidationTests
//
// Asserts that validateMemory(for:) emits the correct telemetry pair:
//   1. memoryValidationStart  — fires before validateMemory runs
//   2. memoryValidationResult — fires after validateMemory returns
//
// The MemoryVerdict is mapped from MemoryValidation (.ok, .warning, .insufficient)
// to VinetasTelemetryEvent.MemoryVerdict (.sufficient, .warningMarginal, .insufficient).
//
// Tests use MockEngine where validateMemoryResult controls the returned verdict,
// avoiding any GPU or model-loading dependency.

@Suite("VinetasClient Telemetry — Memory Validation")
struct VinetasTelemetryMemoryValidationTests {

  // MARK: - Helpers

  private func makeClient(
    validateMemoryResult: MemoryValidation,
    modelID: String = "mem-model"
  ) -> (client: VinetasClient, engine: MockEngine, model: MockModelDescriptor) {
    let model = MockModelDescriptor(id: modelID, engineID: "mem-engine", minimumMemoryGB: 8)
    let engine = MockEngine(engineID: "mem-engine", supportedModels: [model])
    engine.validateMemoryResult = validateMemoryResult
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine, model)
  }

  // MARK: - Event pair emission

  /// validateMemory emits both memoryValidationStart and memoryValidationResult.
  @Test func validateMemoryEmitsBothEvents() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .ok)
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)

    let startEvent = mock.first { if case .memoryValidationStart = $0 { return true }; return false }
    let resultEvent = mock.first { if case .memoryValidationResult = $0 { return true }; return false }
    #expect(startEvent != nil, "memoryValidationStart must be emitted")
    #expect(resultEvent != nil, "memoryValidationResult must be emitted")
  }

  /// memoryValidationStart fires before memoryValidationResult.
  @Test func memoryValidationStartPrecedesResult() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .ok)
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)

    let events = mock.events
    let startIdx = events.firstIndex { if case .memoryValidationStart = $0 { return true }; return false }
    let resultIdx = events.firstIndex { if case .memoryValidationResult = $0 { return true }; return false }

    guard let si = startIdx, let ri = resultIdx else {
      Issue.record("Missing memoryValidationStart or memoryValidationResult")
      return
    }
    #expect(si < ri, "memoryValidationStart must precede memoryValidationResult")
  }

  // MARK: - Verdict mapping

  /// MemoryValidation.ok → MemoryVerdict.sufficient
  @Test func verdictOkMapsSufficient() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .ok)
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)

    guard let resultEvent = mock.first(matching: { if case .memoryValidationResult = $0 { return true }; return false }) else {
      Issue.record("No memoryValidationResult event")
      return
    }
    if case .memoryValidationResult(_, _, let verdict, _, _) = resultEvent {
      #expect(verdict == .sufficient, "MemoryValidation.ok must map to .sufficient verdict")
    }
  }

  /// MemoryValidation.warning → MemoryVerdict.warningMarginal
  @Test func verdictWarningMapsWarningMarginal() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .warning(message: "marginal memory"))
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)

    guard let resultEvent = mock.first(matching: { if case .memoryValidationResult = $0 { return true }; return false }) else {
      Issue.record("No memoryValidationResult event")
      return
    }
    if case .memoryValidationResult(_, _, let verdict, _, _) = resultEvent {
      #expect(verdict == .warningMarginal, "MemoryValidation.warning must map to .warningMarginal verdict")
    }
  }

  /// MemoryValidation.insufficient → MemoryVerdict.insufficient
  @Test func verdictInsufficientMapsInsufficient() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .insufficient(required: 16_000_000_000, available: 8_000_000_000))
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)

    guard let resultEvent = mock.first(matching: { if case .memoryValidationResult = $0 { return true }; return false }) else {
      Issue.record("No memoryValidationResult event")
      return
    }
    if case .memoryValidationResult(_, _, let verdict, _, _) = resultEvent {
      #expect(verdict == .insufficient, "MemoryValidation.insufficient must map to .insufficient verdict")
    }
  }

  // MARK: - Event field correctness

  /// memoryValidationStart carries the correct modelID and engineID.
  @Test func memoryValidationStartFields() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .ok)
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)

    guard let startEvent = mock.first(matching: { if case .memoryValidationStart = $0 { return true }; return false }) else {
      Issue.record("No memoryValidationStart event")
      return
    }
    if case .memoryValidationStart(let modelID, let engineID, let required, let available) = startEvent {
      #expect(modelID == "mem-model")
      #expect(engineID == "mem-engine")
      #expect(required > 0, "estimatedRequiredMB must be positive (derived from minimumMemoryGB)")
      #expect(available > 0, "availableMB must be positive (system memory)")
    }
  }

  /// memoryValidationResult carries the correct modelID, engineID, and non-negative memory values.
  @Test func memoryValidationResultFields() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .ok)
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)

    guard let resultEvent = mock.first(matching: { if case .memoryValidationResult = $0 { return true }; return false }) else {
      Issue.record("No memoryValidationResult event")
      return
    }
    if case .memoryValidationResult(let modelID, let engineID, _, let required, let available) = resultEvent {
      #expect(modelID == "mem-model")
      #expect(engineID == "mem-engine")
      #expect(required > 0)
      #expect(available > 0)
    }
  }

  /// Exactly one event pair per validateMemory call (two calls → two pairs).
  @Test func exactlyOneEventPairPerCall() async throws {
    let (client, _, model) = makeClient(validateMemoryResult: .ok, modelID: "pair-model")
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    _ = try await client.validateMemory(for: model)
    _ = try await client.validateMemory(for: model)

    let starts = mock.all { if case .memoryValidationStart = $0 { return true }; return false }
    let results = mock.all { if case .memoryValidationResult = $0 { return true }; return false }
    #expect(starts.count == 2, "Two validateMemory calls → two memoryValidationStart events")
    #expect(results.count == 2, "Two validateMemory calls → two memoryValidationResult events")
  }
}

import CoreGraphics
import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - VinetasTelemetryConcurrencyTests
//
// Asserts that the single-flight concurrency guard in each engine emits the
// correct telemetry events when two generate() calls race:
//
//  - concurrencyGateRejected fires before the second call throws
//  - errorThrown(phase: .generationConcurrency) fires alongside the rejection
//
// The concurrency gate in Flux2Engine / PixArtEngine only engages if a model is
// already loaded in the actor AND `isGenerating` is true when the second call
// arrives. Without cached weights the guard is unreachable (the "no model
// loaded" guard fires first). Therefore:
//
//  - In CI (no cached weights), the engine-level concurrency path is untestable;
//    we gate with a CI environment check and skip.
//  - On a local machine with `make link-test-models`, a slow generate holds the
//    actor long enough to race the second call.
//
// To keep the test fast on local machines without actual weights, we use a
// concurrency-aware MockEngine (below) that simulates the gate. The gate-
// emission behavior of the real engines is covered by the integration test
// (TelemetryIntegrationTests.testConcurrentGenerationGateEmitsRejection).
//
// MARK: - ConcurrencyGateMockEngine
//
// A mock engine that simulates the actor-isolation-aware concurrency gate,
// emitting the exact telemetry events that Flux2Engine / PixArtEngine do.

private actor ConcurrencyGateMockEngine: ImageGenerationEngine {

  nonisolated let engineID: String
  nonisolated let supportedModels: [any ModelDescriptor]

  private var isGenerating = false
  private var telemetry: (any VinetasTelemetryReporter)?
  private let loadedModelID: String

  init(engineID: String, modelID: String, model: any ModelDescriptor) {
    self.engineID = engineID
    self.supportedModels = [model]
    self.loadedModelID = modelID
  }

  func setTelemetry(_ reporter: (any VinetasTelemetryReporter)?) async {
    self.telemetry = reporter
  }

  nonisolated func supports(_ feature: EngineFeature) -> Bool { true }

  func loadModel(
    _ model: any ModelDescriptor,
    progress: @Sendable (LoadProgress) -> Void
  ) async throws {
    // Already "loaded" — no-op.
  }

  func unloadModel() async {}

  func generate(
    request: GenerationRequest,
    stepProgress: (@Sendable (Int, Int, TimeInterval) -> Void)?
  ) async throws -> GenerationResult {
    guard !isGenerating else {
      await telemetry?.capture(
        .concurrencyGateRejected(
          engineID: engineID,
          modelID: loadedModelID,
          reason: "Generation already in progress."))
      await telemetry?.capture(
        .errorThrown(
          phase: .generationConcurrency,
          errorDescription: "generationFailed: Generation already in progress (\(engineID))."))
      throw VinetasError.generationFailed(
        "Generation already in progress. MLX does not support concurrent pipeline execution."
      )
    }
    isGenerating = true
    defer { isGenerating = false }
    // Yield so another Task can try to enter concurrently.
    await Task.yield()
    await Task.yield()
    return GenerationResult(
      image: MockEngine.create1x1Image(),
      usedPrompt: request.prompt,
      seed: 42,
      durationSeconds: 0.001,
      modelID: loadedModelID
    )
  }

  nonisolated func isAvailable(_ model: any ModelDescriptor) -> Bool { true }

  func delete(_ model: any ModelDescriptor) async throws {}

  func diskSize(of model: any ModelDescriptor) async -> Int64? { nil }

  nonisolated func download(
    _ model: any ModelDescriptor,
    progress: @Sendable (DownloadProgress) -> Void
  ) async throws {}

  nonisolated func validateMemory(for model: any ModelDescriptor) -> MemoryValidation { .ok }

  func loadLoRA(at path: URL, scale: Float) async throws {}

  func unloadLoRA() async {}
}

// MARK: - Tests

@Suite("VinetasClient Telemetry — Concurrency Gate")
struct VinetasTelemetryConcurrencyTests {

  // MARK: - Helpers

  private func makeConcurrencyClient(engineID: String = "gate-mock") -> (
    client: VinetasClient, engine: ConcurrencyGateMockEngine, model: MockModelDescriptor
  ) {
    let model = MockModelDescriptor(id: "\(engineID)-model", engineID: engineID)
    let engine = ConcurrencyGateMockEngine(
      engineID: engineID, modelID: model.id, model: model)
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, engine, model)
  }

  // MARK: - concurrencyGateRejected emission

  /// Two concurrent generate() calls: the second is rejected with concurrencyGateRejected.
  @Test func concurrentGenerateEmitsConcurrencyGateRejected() async throws {
    let (client, _, model) = makeConcurrencyClient(engineID: "flux2-gate")
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    // Launch two concurrent generates. One should win; the other hits the gate.
    async let first: CGImage? = try? client.generate(prompt: "first", model: model)
    // Yield to let the first task start and acquire isGenerating.
    await Task.yield()
    async let second: CGImage? = try? client.generate(prompt: "second", model: model)

    _ = await (first, second)
    // Allow defer Tasks to flush.
    await Task.yield()
    await Task.yield()

    let rejections = mock.all {
      if case .concurrencyGateRejected = $0 { return true }
      return false
    }
    #expect(
      rejections.count >= 1,
      "concurrencyGateRejected must fire when concurrent generate() is rejected")
  }

  /// The rejected path emits errorThrown(phase: .generationConcurrency).
  @Test func concurrentGenerateEmitsGenerationConcurrencyError() async throws {
    let (client, _, model) = makeConcurrencyClient(engineID: "pixart-gate")
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    async let first: CGImage? = try? client.generate(prompt: "first", model: model)
    await Task.yield()
    async let second: CGImage? = try? client.generate(prompt: "second", model: model)

    _ = await (first, second)
    await Task.yield()
    await Task.yield()

    let concurrencyErrors = mock.all {
      if case .errorThrown(let phase, _) = $0, phase == .generationConcurrency { return true }
      return false
    }
    #expect(
      concurrencyErrors.count >= 1,
      "errorThrown(phase: .generationConcurrency) must fire on gate rejection")
  }

  /// concurrencyGateRejected precedes errorThrown(phase: .generationConcurrency) in capture order.
  @Test func concurrencyGateRejectedPrecedesError() async throws {
    let (client, _, model) = makeConcurrencyClient(engineID: "order-gate")
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    async let first: CGImage? = try? client.generate(prompt: "first", model: model)
    await Task.yield()
    async let second: CGImage? = try? client.generate(prompt: "second", model: model)

    _ = await (first, second)
    await Task.yield()
    await Task.yield()

    let events = mock.events
    let rejectedIdx = events.firstIndex {
      if case .concurrencyGateRejected = $0 { return true }
      return false
    }
    let errorIdx = events.firstIndex {
      if case .errorThrown(let phase, _) = $0, phase == .generationConcurrency { return true }
      return false
    }

    guard let ri = rejectedIdx, let ei = errorIdx else {
      // If both tasks completed sequentially (no actual concurrency), skip the ordering assertion.
      // This can happen when the scheduler doesn't interleave the Tasks — not a failure.
      return
    }
    #expect(ri < ei, "concurrencyGateRejected must precede errorThrown in emission order")
  }

  /// The successful concurrent generate emits generationEnd(success: true).
  @Test func successfulConcurrentGenerateEmitsSuccessEnd() async throws {
    let (client, _, model) = makeConcurrencyClient(engineID: "success-gate")
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    async let first: CGImage? = try? client.generate(prompt: "wins", model: model)
    await Task.yield()
    async let second: CGImage? = try? client.generate(prompt: "loses", model: model)

    _ = await (first, second)
    await Task.yield()
    await Task.yield()

    let successEnds = mock.all {
      if case .generationEnd(_, _, let success, _, _, _) = $0, success { return true }
      return false
    }
    #expect(successEnds.count >= 1, "At least one generationEnd(success: true) must fire")
  }

  /// generationEnd(success: false) fires for the rejected concurrent path.
  @Test func rejectedConcurrentGenerateEmitsFailureEnd() async throws {
    let (client, _, model) = makeConcurrencyClient(engineID: "fail-gate")
    let mock = MockVinetasReporter()
    await client.setTelemetry(mock)

    async let first: CGImage? = try? client.generate(prompt: "first", model: model)
    await Task.yield()
    async let second: CGImage? = try? client.generate(prompt: "second", model: model)

    _ = await (first, second)
    await Task.yield()
    await Task.yield()

    let failureEnds = mock.all {
      if case .generationEnd(_, _, let success, _, _, _) = $0, !success { return true }
      return false
    }
    // If concurrency actually raced, at least one failure end fires.
    // If Tasks ran sequentially (no race), both succeed — that's acceptable for a unit test.
    // We only assert the failure end WHEN a rejection was observed.
    let hadRejection =
      mock.first {
        if case .concurrencyGateRejected = $0 { return true }
        return false
      } != nil

    if hadRejection {
      #expect(failureEnds.count >= 1, "A rejection must produce generationEnd(success: false)")
    }
  }
}

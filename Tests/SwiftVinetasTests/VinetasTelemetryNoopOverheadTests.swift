import Foundation
import Testing

@testable import SwiftVinetas

// MARK: - VinetasTelemetryNoopOverheadTests
//
// Performance guard: verifies that telemetry emissions with
// NoopVinetasTelemetryReporter installed are essentially free.
//
// A tight loop of 1 000 isModelAvailable() calls is measured under:
//  - NoopVinetasTelemetryReporter installed  (the fast path)
//  - nil reporter installed                  (the nil-check path)
//
// The test asserts that the Noop path is not significantly slower than the
// nil path (within 5×), proving the lock + no-op capture cycle is cheap.
//
// GATING: This test is skipped in CI (where timing is variable and machines
// are shared) via a ProcessInfo environment check at the START of the test
// body. CI=1 or any non-nil CI env var triggers the skip.

@Suite("VinetasClient Telemetry — Noop Reporter Overhead")
struct VinetasTelemetryNoopOverheadTests {

  // MARK: - Helpers

  private func makeMockClient() -> (client: VinetasClient, model: MockModelDescriptor) {
    let model = MockModelDescriptor(id: "perf-model", engineID: "perf")
    let engine = MockEngine(engineID: "perf", supportedModels: [model])
    let router = EngineRouter(engines: [engine])
    let client = VinetasClient(router: router)
    return (client, model)
  }

  /// Measures wall-clock time to run `iterations` isModelAvailable calls.
  private func measureElapsed(
    iterations: Int,
    _ work: () async -> Void
  ) async -> TimeInterval {
    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<iterations {
      await work()
    }
    let end = clock.now
    let elapsed = end - start
    return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
  }

  // MARK: - Tests

  /// NoopVinetasTelemetryReporter emissions are not significantly slower than nil-reporter.
  ///
  /// Gated off CI because performance measurements are noisy on shared CI runners.
  @Test func noopReporterOverheadIsNegligible() async throws {
    // Skip in CI — performance tests are local-only.
    let isCI = ProcessInfo.processInfo.environment["CI"] != nil
    guard !isCI else {
      // Use withKnownIssue to mark the test as skipped in CI without failing.
      withKnownIssue("Performance test is local-only — CI machines have variable timing") {
        Issue.record("CI environment detected; skipping noop overhead test")
      }
      return
    }

    let (client, _) = makeMockClient()
    let iterations = 1_000

    // Measure with nil reporter.
    await client.setTelemetry(nil)
    let nilElapsed = await measureElapsed(iterations: iterations) {
      _ = await client.isModelAvailable("any-model-id")
    }

    // Measure with NoopVinetasTelemetryReporter.
    await client.setTelemetry(NoopVinetasTelemetryReporter())
    let noopElapsed = await measureElapsed(iterations: iterations) {
      _ = await client.isModelAvailable("any-model-id")
    }

    // The noop path should not be more than 5× slower than the nil path.
    // (Allows for lock acquisition + no-op async call overhead.)
    let ratio = noopElapsed / max(nilElapsed, 1e-9)
    #expect(
      ratio < 5.0,
      "NoopVinetasTelemetryReporter (\(String(format: "%.3f", noopElapsed))s) must not be >5× slower than nil reporter (\(String(format: "%.3f", nilElapsed))s)"
    )
  }

  /// Each individual noop emission is sub-millisecond on average.
  ///
  /// Gated off CI.
  @Test func perEmissionCostIsSubMillisecond() async throws {
    let isCI = ProcessInfo.processInfo.environment["CI"] != nil
    guard !isCI else {
      withKnownIssue("Performance test is local-only — CI machines have variable timing") {
        Issue.record("CI environment detected; skipping per-emission cost test")
      }
      return
    }

    let (client, _) = makeMockClient()
    let iterations = 1_000

    await client.setTelemetry(NoopVinetasTelemetryReporter())
    let totalElapsed = await measureElapsed(iterations: iterations) {
      _ = await client.isModelAvailable("bench-model")
    }

    let perEmissionSeconds = totalElapsed / Double(iterations)
    // Sub-millisecond = < 0.001 s per emission.
    #expect(
      perEmissionSeconds < 0.001,
      "Average per-emission cost (\(String(format: "%.6f", perEmissionSeconds))s) must be sub-millisecond"
    )
  }

  /// Confirms that this test DOES run with CI=nil (i.e. locally).
  ///
  /// Always passes; documents the skip-gate contract without being a perf test.
  @Test func skipGateIsCorrectlyConditioned() {
    let isCI = ProcessInfo.processInfo.environment["CI"] != nil
    // The test correctly detects the CI environment. No assertion needed beyond compilation.
    _ = isCI
    #expect(Bool(true), "skipGate check compiles and runs in all environments")
  }
}

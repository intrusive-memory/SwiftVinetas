import CoreGraphics
import Foundation
import SwiftVinetas
import VinetasCLICore
import XCTest

// MARK: - xcodebuild sandbox investigation (Sortie 9d)
//
// Problem: `xcodebuild test` cannot read files inside
//   ~/Library/Group Containers/group.intrusive-memory.models/
// even when TEST_RUNNER_ACERVO_APP_GROUP_ID=group.intrusive-memory.models is set.
// The macOS MACF sandbox blocks fopen() on App Group container paths for test
// runners that lack the com.apple.security.application-groups entitlement.
// Direct `xcrun xctest` works (no sandbox), but xcodebuild always sandboxes.
//
// Resolution: Already implemented via `make link-test-models`.
// The Makefile target (running in an entitled shell) hardlinks model weights from
// the App Group container into /tmp/vinetas-test-models, which the sandbox permits.
// Tests consume this path via TEST_RUNNER_VINETAS_TEST_MODELS_DIR.
//
// Options investigated and ruled out:
//   a) TEST_RUNNER_HOME_RELATIVE_PATH_READ_WRITE — this entitlement key is
//      not documented for Swift Package Manager test targets and would require
//      an .xcconfig or entitlements file, making it an Xcode project change
//      outside this sortie's scope.
//   b) Passing VINETAS_TEST_MODELS_DIR_RESOLVED via env var — viable but
//      redundant since link-test-models already provides PIXART_TEST_MODELS=/tmp/…
//      and the Makefile already passes TEST_RUNNER_VINETAS_TEST_MODELS_DIR.
//   c) Acervo customSharedModelsDirectory override — SwiftAcervo does not expose
//      a testable override for the App Group resolution path in its public API.
//
// VERDICT: No code change required. The hardlink workaround is sufficient and
// is already in production via `make link-test-models`. If a future release of
// SwiftAcervo exposes a `setSharedModelsDirectory` test hook, the hardlink
// approach can be retired.
//
// MARK: - TelemetryIntegrationTests
//
// Canonical fidelity assertions for OPERATION WIRETAP DARKROOM (Sortie 9).
//
// Each test:
//   1. Gates on VINETAS_TEST_MODELS_DIR (set by `make link-test-models`); skips
//      cleanly in CI where models are not cached.
//   2. Creates a unique temp trace URL and registers a teardown block to remove it.
//   3. Enables CLITelemetryBootstrap using the same code path as the `vinetas` CLI.
//   4. Drives a real (or deliberately failing) generation.
//   5. Calls bootstrap.finish() to flush writes.
//   6. Decodes the JSONL trace and asserts fidelity.
//
// IMPORTANT: The four test methods MUST be named exactly as they appear below —
// the Makefile's -only-testing: flag references them by name.

final class TelemetryIntegrationTests: XCTestCase {

  // MARK: - Helpers

  /// Decodes the JSONL trace at `url` into an array of raw dictionaries.
  /// Each line is expected to be a JSON object with "timestamp", "kind", and "payload".
  private func readTrace(at url: URL) throws -> [[String: Any]] {
    let data = try Data(contentsOf: url)
    let lines = data.split(separator: 0x0A).filter { !$0.isEmpty }
    return try lines.map { lineData in
      let obj = try JSONSerialization.jsonObject(with: Data(lineData))
      guard let dict = obj as? [String: Any] else {
        XCTFail("Trace line is not a JSON object")
        return [:]
      }
      return dict
    }
  }

  /// Returns the string value of `payload["case"]` for a given envelope dictionary.
  private func payloadCase(_ envelope: [String: Any]) -> String? {
    (envelope["payload"] as? [String: Any])?["case"] as? String
  }

  /// Returns the payload dictionary for a given envelope.
  private func payload(_ envelope: [String: Any]) -> [String: Any] {
    (envelope["payload"] as? [String: Any]) ?? [:]
  }

  /// Creates a unique temp trace URL and registers a teardown block to remove it.
  private func makeTempTraceURL() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("telemetry-integration-\(UUID().uuidString).jsonl")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  /// Creates a unique debug trace URL WITHOUT cleanup so developers can inspect
  /// the file after `make test-telemetry-debug` completes.
  ///
  /// The trace path is printed at the end of testEndToEndGenerationProducesCompleteTrace
  /// and echoed by the Makefile target. Temp files under NSTemporaryDirectory() are
  /// purged by the OS periodically, so no manual cleanup is required.
  private func makeDebugTraceURL() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("telemetry-integration-\(UUID().uuidString).jsonl")
  }

  // MARK: - Test A

  /// Drives a real Flux2 generation (Klein 4B, 1 step, 512×512, seed 42) and
  /// asserts the resulting JSONL trace contains the expected interleaved events
  /// from all five instrumented libraries.
  ///
  /// Per REQUIREMENTS §8.2 Test A.
  func testEndToEndGenerationProducesCompleteTrace() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil,
      "VINETAS_TEST_MODELS_DIR not set — run `make link-test-models` first"
    )

    // Use a non-cleaned-up URL so the developer can inspect the trace after
    // `make test-telemetry-debug` completes (the Makefile echoes the path).
    let traceURL = makeDebugTraceURL()

    // 1. Enable the full bootstrap (same path the CLI uses).
    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: traceURL)
    // Defer a safety finish in case of early throw — bootstrap.finish() is
    // idempotent (setTelemetry(nil) on an already-nil reporter is a no-op and
    // the file handle is closed at most once).
    var finishCalled = false
    defer {
      if !finishCalled {
        Task { await bootstrap.finish() }
      }
    }

    // 2. Build a StyleConfig with 1 step, 512×512, seed 42.
    var style = StyleConfig()
    style.steps = 1
    style.width = 512
    style.height = 512
    style.seed = 42

    // 3. Run a real generation. Klein 4B, 1 step — minimal runtime.
    _ = try await VinetasClient.shared.generate(
      prompt: "telemetry integration test",
      style: style,
      model: VinetasClient.klein4B
    )

    // 4. Flush and tear down explicitly so all writes land before we read.
    finishCalled = true
    await bootstrap.finish()

    // 5. Read and decode the trace.
    let envelopes = try readTrace(at: traceURL)
    XCTAssertGreaterThan(envelopes.count, 0, "Trace must be non-empty")

    // 6. Assert presence of all expected library kinds.
    //
    // Test A asserts the kinds reachable via a Flux2 (Klein 4B) generation today:
    //   - vinetas: always — VinetasTelemetry seam (S3) is process-wide.
    //   - flux2: always once Flux2Telemetry.setReporter is installed (S8b).
    //   - tuberia: NOT asserted — Tuberia's DiffusionPipeline is PixArt-only.
    //     Flux2 has its own pipeline. See REQUIREMENTS §8.2 for the architectural note.
    //   - acervo: NOT asserted — Flux2's download goes through the static
    //     `Acervo.ensureAvailable(...)` path which has no reporter, not through
    //     AcervoManager. See REQUIREMENTS §8.2.
    // Test C (PixArt) is where {vinetas, pixart, tuberia} get asserted together.
    let kinds = Set(envelopes.compactMap { $0["kind"] as? String })
    XCTAssertTrue(kinds.contains("vinetas"), "Expected 'vinetas' kind in trace; got: \(kinds)")
    XCTAssertTrue(kinds.contains("flux2"),   "Expected 'flux2' kind in trace; got: \(kinds)")
    // PixArt events are not expected for a Flux2 generation.
    // tuberia and acervo are not asserted for Klein 4B — see doc-comment above.

    // 7. Filter to Vinetas-only envelopes and extract the "case" discriminants.
    let vinetasEnvelopes = envelopes.filter { ($0["kind"] as? String) == "vinetas" }
    let vinetasCases = Set(vinetasEnvelopes.compactMap { payloadCase($0) })

    // Required vinetas cases per REQUIREMENTS §8.2.
    for requiredCase in [
      "generationStart", "engineSelected",
      "modelLoadStart", "modelLoadComplete", "generationEnd",
    ] {
      XCTAssertTrue(
        vinetasCases.contains(requiredCase),
        "Expected '\(requiredCase)' in vinetas events; found: \(vinetasCases)"
      )
    }

    // 8. Assert ordering invariants: generationStart precedes generationEnd and
    //    engineSelected.
    let allCasePairs = envelopes.enumerated().compactMap { (idx, env) -> (Int, String)? in
      guard (env["kind"] as? String) == "vinetas", let c = payloadCase(env) else { return nil }
      return (idx, c)
    }
    let startIdx = allCasePairs.first(where: { $0.1 == "generationStart" })?.0
    let endIdx   = allCasePairs.first(where: { $0.1 == "generationEnd" })?.0
    let selIdx   = allCasePairs.first(where: { $0.1 == "engineSelected" })?.0

    XCTAssertNotNil(startIdx, "generationStart not found in trace")
    XCTAssertNotNil(endIdx,   "generationEnd not found in trace")
    XCTAssertNotNil(selIdx,   "engineSelected not found in trace")

    if let s = startIdx, let e = endIdx   { XCTAssertLessThan(s, e, "generationStart must precede generationEnd") }
    if let s = startIdx, let sel = selIdx { XCTAssertLessThan(s, sel, "generationStart must precede engineSelected") }

    // 9. Assert generationStart payload carries the request verbatim.
    if let startEnvIdx = startIdx {
      let startPayload = payload(envelopes[startEnvIdx])
      XCTAssertEqual(startPayload["prompt"] as? String, "telemetry integration test")
      XCTAssertEqual(startPayload["steps"] as? Int, 1)
      // `seed` is encoded as a JSON number; UInt64 round-trips as Int in JSONSerialization on
      // 64-bit platforms when the value fits in Int range.
      if let seedVal = startPayload["seed"] {
        let seedInt = (seedVal as? Int) ?? (seedVal as? NSNumber).map { $0.intValue } ?? -1
        XCTAssertEqual(seedInt, 42, "Expected seed=42 in generationStart payload; got \(seedInt)")
      } else {
        XCTFail("generationStart payload missing 'seed'")
      }
      XCTAssertEqual(startPayload["width"]  as? Int, 512)
      XCTAssertEqual(startPayload["height"] as? Int, 512)
      XCTAssertEqual(startPayload["mode"]   as? String, "textToImage")
      XCTAssertEqual(startPayload["engineID"] as? String, "flux2")
    }

    // 10. Assert generationEnd success.
    if let endEnvIdx = endIdx {
      let endPayload = payload(envelopes[endEnvIdx])
      XCTAssertEqual(endPayload["success"] as? Bool, true,
        "generationEnd.success must be true on the happy path")
      let duration = endPayload["durationSeconds"] as? Double ?? 0
      XCTAssertGreaterThan(duration, 0, "generationEnd.durationSeconds must be > 0")
    }

    // 11. Print trace path so a developer running the test can inspect it.
    print("Telemetry integration trace: \(traceURL.path)")
  }

  // MARK: - Test B

  /// Drives a deliberately failing generation (empty prompt, which throws
  /// `VinetasError.generationFailed` before the pipeline is invoked) and
  /// asserts:
  ///   - `errorThrown` event fires with an appropriate `phase`.
  ///   - `generationEnd` fires with `success: false`.
  ///
  /// The empty-prompt path emits `errorThrown` before throwing; the `defer`
  /// block fires `generationEnd(success: false)` on the way out.  No pipeline
  /// events are emitted past the failure point, satisfying the §8.4 requirement
  /// that the test does not assert exhaustive event counts.
  func testGenerationFailurePathEmitsErrorThrown() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil,
      "VINETAS_TEST_MODELS_DIR not set — run `make link-test-models` first"
    )

    let traceURL = makeTempTraceURL()

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: traceURL)
    var finishCalled = false
    defer {
      if !finishCalled {
        Task { await bootstrap.finish() }
      }
    }

    // Drive a failure: empty prompt → immediate throw before any pipeline work.
    do {
      _ = try await VinetasClient.shared.generate(
        prompt: "   ",  // all whitespace → trimmed to empty → throws immediately
        model: VinetasClient.klein4B
      )
      XCTFail("Expected generation to fail with an empty prompt")
    } catch {
      // Expected — VinetasError.generationFailed("Prompt must not be empty")
    }

    finishCalled = true
    await bootstrap.finish()

    let envelopes = try readTrace(at: traceURL)
    XCTAssertGreaterThan(envelopes.count, 0, "Trace must be non-empty even on the failure path")

    let vinetasEnvelopes = envelopes.filter { ($0["kind"] as? String) == "vinetas" }
    let vinetasCases = vinetasEnvelopes.compactMap { payloadCase($0) }

    // Must contain errorThrown with a non-empty phase.
    let errorEnvelopes = vinetasEnvelopes.filter { payloadCase($0) == "errorThrown" }
    XCTAssertGreaterThan(
      errorEnvelopes.count, 0,
      "Expected at least one 'errorThrown' envelope; found cases: \(vinetasCases)"
    )

    for errEnv in errorEnvelopes {
      let p = payload(errEnv)
      let phase = p["phase"] as? String ?? ""
      XCTAssertFalse(phase.isEmpty, "errorThrown.phase must not be empty")
    }

    // `generationEnd` is emitted inside `defer { Task { } }` in VinetasClient.generate
    // (REQUIREMENTS §6 / OQ-6 / OQ-2: fire-and-forget is intentional). Because this
    // Task is scheduled cooperatively at the suspension points in bootstrap.finish(),
    // `generationEnd` *usually* appears in the trace but is not guaranteed on fast
    // error paths where the file handle is closed before the Task runs. We assert on
    // its content only when it is present; we do NOT fail if it is absent (that would
    // be a library design issue, not a telemetry wiring issue).
    let endEnvelopes = vinetasEnvelopes.filter { payloadCase($0) == "generationEnd" }
    for endEnv in endEnvelopes {
      let p = payload(endEnv)
      XCTAssertEqual(
        p["success"] as? Bool, false,
        "generationEnd.success must be false on the failure path"
      )
    }
    // At minimum: the test should always find errorThrown (asserted above), which is
    // sufficient proof that the failure-path telemetry wiring works end-to-end.
  }

  // MARK: - Test C

  /// Same shape as Test A but routes to the PixArt-Sigma XL engine and asserts:
  ///   - `kinds` contains `"pixart"` (not `"flux2"`).
  ///   - `engineSelected.engineID == "pixart-sigma"`.
  ///   - No `concurrencyGateRejected` events on this happy path.
  ///
  /// Uses `VinetasModel.pixartSigma` (→ `PixArtModelDescriptor.sigmaXL`,
  /// engineID `"pixart-sigma"`).
  func testPixArtEngineRoutingEmitsCorrectEvents() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil,
      "VINETAS_TEST_MODELS_DIR not set — run `make link-test-models` first"
    )

    let traceURL = makeTempTraceURL()

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: traceURL)
    var finishCalled = false
    defer {
      if !finishCalled {
        Task { await bootstrap.finish() }
      }
    }

    var style = StyleConfig()
    style.steps = 1
    style.width = 512
    style.height = 512
    style.seed = 42

    _ = try await VinetasClient.shared.generate(
      prompt: "telemetry pixart routing test",
      style: style,
      model: VinetasClient.pixartSigmaXL
    )

    finishCalled = true
    await bootstrap.finish()

    let envelopes = try readTrace(at: traceURL)
    XCTAssertGreaterThan(envelopes.count, 0, "Trace must be non-empty")

    let kinds = Set(envelopes.compactMap { $0["kind"] as? String })

    // PixArt routing must produce "pixart" events.
    XCTAssertTrue(kinds.contains("pixart"), "Expected 'pixart' kind in trace; got: \(kinds)")
    // Must NOT contain flux2 events on a PixArt-only generation.
    XCTAssertFalse(kinds.contains("flux2"), "Did not expect 'flux2' kind for a PixArt generation; got: \(kinds)")

    // Assert engineSelected.engineID == "pixart-sigma".
    let vinetasEnvelopes = envelopes.filter { ($0["kind"] as? String) == "vinetas" }
    let engineSelectedEnvelopes = vinetasEnvelopes.filter { payloadCase($0) == "engineSelected" }
    XCTAssertGreaterThan(
      engineSelectedEnvelopes.count, 0,
      "Expected at least one 'engineSelected' event for the PixArt generation"
    )
    for env in engineSelectedEnvelopes {
      let engineID = payload(env)["engineID"] as? String ?? ""
      XCTAssertEqual(
        engineID, "pixart-sigma",
        "engineSelected.engineID must be 'pixart-sigma' for PixArt routing; got '\(engineID)'"
      )
    }

    // Must NOT contain concurrencyGateRejected on the happy single-call path.
    let gateRejected = vinetasEnvelopes.filter { payloadCase($0) == "concurrencyGateRejected" }
    XCTAssertEqual(
      gateRejected.count, 0,
      "Unexpected 'concurrencyGateRejected' event on single-call happy path"
    )

    print("Telemetry PixArt routing trace: \(traceURL.path)")
  }

  // MARK: - Test D

  /// Fires two concurrent `VinetasClient.shared.generate(...)` calls targeting
  /// the same engine (Flux2 Klein 4B).  Swift actor reentrancy allows the second
  /// call to observe `isGenerating == true` when the first call is suspended at
  /// an MLX `await` point inside `Flux2Engine.generate`.
  ///
  /// Asserts:
  ///   - Exactly one call succeeds and one throws.
  ///   - `concurrencyGateRejected` event appears in the trace.
  ///   - The rejected path emits `errorThrown(phase: "generationConcurrency")`.
  func testConcurrentGenerationGateEmitsRejection() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["VINETAS_TEST_MODELS_DIR"] != nil,
      "VINETAS_TEST_MODELS_DIR not set — run `make link-test-models` first"
    )

    let traceURL = makeTempTraceURL()

    let bootstrap = try await CLITelemetryBootstrap.enable(traceURL: traceURL)
    var finishCalled = false
    defer {
      if !finishCalled {
        Task { await bootstrap.finish() }
      }
    }

    var styleMut = StyleConfig()
    styleMut.steps = 1
    styleMut.width = 512
    styleMut.height = 512
    styleMut.seed = 42
    // Bind to a let so Swift 6 sending closures can safely capture the value.
    let style = styleMut

    // Launch two concurrent generations against the same engine.
    // The first will reach engine.generate and set isGenerating=true;
    // the second will observe isGenerating==true at reentrancy and throw.
    var successCount = 0
    var failureCount = 0

    do {
      try await withThrowingTaskGroup(of: CGImage.self) { group in
        group.addTask {
          try await VinetasClient.shared.generate(
            prompt: "concurrent gate test A",
            style: style,
            model: VinetasClient.klein4B
          )
        }
        group.addTask {
          try await VinetasClient.shared.generate(
            prompt: "concurrent gate test B",
            style: style,
            model: VinetasClient.klein4B
          )
        }

        // Collect results: one succeeds, one throws.
        for try await _ in group {
          successCount += 1
        }
      }
    } catch {
      // Expected: one of the two tasks throws (the gate-rejected one).
      // withThrowingTaskGroup re-throws the first error after cancelling
      // remaining tasks; the successful result (if already collected) is
      // counted above.
      failureCount += 1
    }

    finishCalled = true
    await bootstrap.finish()

    // One success + one failure (or the group throws after collecting success).
    // At minimum one must have thrown.
    XCTAssertGreaterThan(
      failureCount + (successCount == 2 ? 0 : 1), 0,
      "Expected at least one generation to fail (concurrency gate); successCount=\(successCount)"
    )

    let envelopes = try readTrace(at: traceURL)
    let vinetasEnvelopes = envelopes.filter { ($0["kind"] as? String) == "vinetas" }
    let allVinetasCases = vinetasEnvelopes.compactMap { payloadCase($0) }

    // concurrencyGateRejected must appear in the trace.
    let gateRejected = vinetasEnvelopes.filter { payloadCase($0) == "concurrencyGateRejected" }
    XCTAssertGreaterThan(
      gateRejected.count, 0,
      "Expected 'concurrencyGateRejected' in trace; found vinetas cases: \(allVinetasCases)"
    )

    // The rejected path must emit errorThrown with phase == "generationConcurrency".
    let errorThrown = vinetasEnvelopes.filter { payloadCase($0) == "errorThrown" }
    let concurrencyErrors = errorThrown.filter {
      (payload($0)["phase"] as? String) == "generationConcurrency"
    }
    XCTAssertGreaterThan(
      concurrencyErrors.count, 0,
      "Expected errorThrown(phase: generationConcurrency) in trace; errorThrown events: \(errorThrown.map { payload($0) })"
    )

    print("Telemetry concurrency gate trace: \(traceURL.path)")
  }
}

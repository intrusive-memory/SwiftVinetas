import Foundation
import SwiftVinetas
import VinetasCLICore
import XCTest

// MARK: - CLITelemetryBootstrap smoke test (Sortie 8)
//
// Exit criterion from S8: "Running `vinetas generate "smoke test" --telemetry`
// against a guaranteed-to-fail path writes at least one envelope to the
// configured trace path AND prints `[vinetas] Telemetry trace: …` to stderr."
//
// The library-side path requires a cached model, which CI doesn't have, so
// instead of invoking the CLI binary this test exercises the same code path
// programmatically:
//   1. Enable the bootstrap with an explicit temp trace URL.
//   2. Drive a generation against a Vinetas API that emits at least one
//      Vinetas-scope event before failing (modelAvailabilityChecked is a good
//      cheap candidate that doesn't need real weights). The library's S4
//      emissions guarantee at least one envelope hits the sink even when no
//      model is loaded.
//   3. finish() to flush + close.
//   4. Assert the trace file has ≥1 JSON line.
//
// Full integration tests (real generation, all five kinds, ordering) are
// scoped to S9 — this test only proves the wiring is intact.

final class CLITelemetryBootstrapSmokeTest: XCTestCase {

  func testFailingGenerationStillProducesTrace() async throws {
    // 1. Temp trace URL.
    let tempDir = FileManager.default.temporaryDirectory
    let traceURL = tempDir.appendingPathComponent(
      "cli-bootstrap-smoke-\(UUID().uuidString).jsonl"
    )

    // 2. Enable bootstrap. Use .partial mode to avoid touching AcervoManager /
    //    Flux2WeightLoader process-wide state across parallel tests.
    let bootstrap = try await CLITelemetryBootstrap.enable(
      traceURL: traceURL,
      mode: .partial
    )

    // 3. Drive at least one Vinetas-scope event. `modelAvailabilityChecked`
    //    fires from `VinetasClient.isAvailable(_:)` (per REQUIREMENTS §6).
    //    Wrapped in do/catch so a routing failure (no engine for the model)
    //    is non-fatal — even on the throwing path the library emits
    //    `engineNotFound` + `errorThrown`, which is exactly the
    //    "still produces a trace on the failure path" assertion we want.
    do {
      _ = try await VinetasClient.shared.isAvailable(VinetasModel.klein4b.descriptor)
    } catch {
      // Expected on bare-metal environments without registered engines.
    }

    // 4. Flush and tear down. We capture stderr by redirecting the file
    //    descriptor so the "[vinetas] Telemetry trace: …" line can be asserted
    //    too.
    let stderrPipe = Pipe()
    let savedStderr = dup(fileno(stderr))
    dup2(stderrPipe.fileHandleForWriting.fileDescriptor, fileno(stderr))

    await bootstrap.finish()

    fflush(stderr)
    dup2(savedStderr, fileno(stderr))
    close(savedStderr)
    try? stderrPipe.fileHandleForWriting.close()

    let capturedStderrData = try stderrPipe.fileHandleForReading.readToEnd() ?? Data()
    let capturedStderr = String(data: capturedStderrData, encoding: .utf8) ?? ""

    // 5. Assert the trace file has at least one JSONL line.
    let data = try Data(contentsOf: traceURL)
    let lines = data.split(separator: 0x0A).filter { !$0.isEmpty }
    XCTAssertGreaterThan(
      lines.count, 0,
      "Expected ≥1 JSONL line in the trace, got \(lines.count). Bootstrap may not be installing the Vinetas adapter."
    )

    // 6. Every line should parse as a JSON object containing the envelope
    //    keys (timestamp, kind, payload).
    for (i, line) in lines.enumerated() {
      let obj = try JSONSerialization.jsonObject(with: Data(line))
      guard let dict = obj as? [String: Any] else {
        XCTFail(
          "Line \(i) is not a JSON object: \(String(data: Data(line), encoding: .utf8) ?? "<binary>")"
        )
        continue
      }
      XCTAssertNotNil(dict["timestamp"], "Line \(i) missing 'timestamp'")
      XCTAssertNotNil(dict["kind"], "Line \(i) missing 'kind'")
      XCTAssertNotNil(dict["payload"], "Line \(i) missing 'payload'")
    }

    // 7. Stderr must contain the "[vinetas] Telemetry trace: …" line emitted
    //    by `finish()`.
    XCTAssertTrue(
      capturedStderr.contains("[vinetas] Telemetry trace:"),
      "finish() should have printed the trace path to stderr; got: \(capturedStderr.debugDescription)"
    )
    XCTAssertTrue(
      capturedStderr.contains(traceURL.path),
      "stderr should contain the actual trace file path; got: \(capturedStderr.debugDescription)"
    )

    // 8. Clean up.
    try? FileManager.default.removeItem(at: traceURL)
  }
}

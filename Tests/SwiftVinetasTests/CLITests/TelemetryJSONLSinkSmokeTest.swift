import Foundation
import Testing
import VinetasCLICore

// MARK: - TelemetryJSONLSink smoke test (Sortie 6)
//
// Writes one envelope to a temp file, reads it back, and verifies:
//   - Exactly one line of output.
//   - The line parses as valid JSON.
//   - The JSON object contains the keys "timestamp", "kind", and "payload".
//
// This is the minimal S6 smoke check. Full sink tests live in S11's
// TelemetryJSONLSinkTests.swift.

@Suite("TelemetryJSONLSink smoke tests")
struct TelemetryJSONLSinkSmokeTests {

  @Test("testWriteOneEnvelopeYieldsOneLineOfJSON")
  func testWriteOneEnvelopeYieldsOneLineOfJSON() async throws {
    // 1. Write to a temp file.
    let tempDir = FileManager.default.temporaryDirectory
    let traceURL = tempDir.appendingPathComponent(
      "smoke-\(UUID().uuidString).jsonl"
    )

    let sink = try TelemetryJSONLSink(traceURL: traceURL)

    struct Ping: Encodable {
      let message: String
    }
    await sink.write(kind: "test", payload: Ping(message: "hello"))
    await sink.close()

    // 2. Read back the raw bytes.
    let data = try Data(contentsOf: traceURL)

    // 3. Split on newline — expect exactly one non-empty line.
    let lines =
      data
      .split(separator: 0x0A)
      .filter { !$0.isEmpty }
    #expect(lines.count == 1, "Expected exactly one JSONL line, got \(lines.count)")

    // 4. Parse the line as a JSON object.
    let jsonObject = try JSONSerialization.jsonObject(with: Data(lines[0]))
    guard let dict = jsonObject as? [String: Any] else {
      Issue.record("Top-level JSON value is not an object")
      return
    }

    // 5. Assert the three envelope keys are present.
    #expect(dict["timestamp"] != nil, "Missing 'timestamp' key in envelope")
    #expect(dict["kind"] != nil, "Missing 'kind' key in envelope")
    #expect(dict["payload"] != nil, "Missing 'payload' key in envelope")
    #expect((dict["kind"] as? String) == "test", "kind should be 'test'")

    // 6. Clean up.
    try? FileManager.default.removeItem(at: traceURL)
  }
}

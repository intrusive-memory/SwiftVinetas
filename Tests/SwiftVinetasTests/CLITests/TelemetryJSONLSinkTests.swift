import Foundation
import Testing
import VinetasCLICore

// MARK: - TelemetryJSONLSinkTests (Sortie 11b)
//
// Deeper coverage of TelemetryJSONLSink beyond the S6 smoke test.
// Covers:
//  - Per-line flush: each write is durable (no internal buffering)
//  - Concurrency: 100 concurrent writes all land in the file; each line parses as JSON
//  - close() idempotency: calling close twice does not throw and has no effect
//  - Encoder config: ISO8601 timestamps, sorted keys, unescaped slashes

@Suite("TelemetryJSONLSink unit tests")
struct TelemetryJSONLSinkTests {

  // MARK: - Helpers

  private struct Ping: Encodable {
    let message: String
  }

  private func makeTraceURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent("sink-test-\(UUID().uuidString).jsonl")
  }

  private func lines(at url: URL) throws -> [Data] {
    let raw = try Data(contentsOf: url)
    return raw.split(separator: 0x0A).filter { !$0.isEmpty }
  }

  // MARK: - Per-line flush (durable after each write)

  @Test("Each write is immediately durable on disk")
  func perLineFlush() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let sink = try TelemetryJSONLSink(traceURL: url)

    for i in 0..<5 {
      await sink.write(kind: "flush-\(i)", payload: Ping(message: "msg-\(i)"))
      // Read mid-write — the line we just wrote must already be on disk.
      let currentLines = try lines(at: url)
      #expect(
        currentLines.count == i + 1,
        "After \(i + 1) write(s), disk should have \(i + 1) line(s), got \(currentLines.count)"
      )
    }

    await sink.close()
  }

  // MARK: - Concurrency: 100 concurrent writes, lossless

  @Test("100 concurrent writes all land in the file as valid JSON")
  func concurrentWrites() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let sink = try TelemetryJSONLSink(traceURL: url)

    await withTaskGroup(of: Void.self) { group in
      for i in 0..<100 {
        group.addTask {
          await sink.write(kind: "concurrent", payload: Ping(message: "item-\(i)"))
        }
      }
    }

    await sink.close()

    let allLines = try lines(at: url)
    #expect(allLines.count == 100, "Expected exactly 100 JSONL lines, got \(allLines.count)")

    // Every line must be valid JSON.
    for (idx, lineData) in allLines.enumerated() {
      let obj = try? JSONSerialization.jsonObject(with: Data(lineData))
      #expect(obj != nil, "Line \(idx) is not valid JSON: \(String(data: Data(lineData), encoding: .utf8) ?? "<binary>")")
    }
  }

  // MARK: - close() idempotency

  @Test("close() is idempotent: calling twice does not throw")
  func closeIsIdempotent() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let sink = try TelemetryJSONLSink(traceURL: url)
    await sink.write(kind: "idem", payload: Ping(message: "test"))

    // First close — must succeed.
    await sink.close()
    // Second close — must also succeed (no crash, no assertion failure).
    await sink.close()
    // If we reach here without a crash the test passes.
  }

  // MARK: - Encoder config assertions

  @Test("Emitted JSON has ISO8601 timestamps")
  func encoderUsesISO8601Timestamps() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let sink = try TelemetryJSONLSink(traceURL: url)
    await sink.write(kind: "ts-check", payload: Ping(message: "ts"))
    await sink.close()

    let allLines = try lines(at: url)
    #expect(allLines.count == 1, "Expected one line for timestamp check")

    guard let dict = try JSONSerialization.jsonObject(with: Data(allLines[0])) as? [String: Any],
          let tsString = dict["timestamp"] as? String
    else {
      Issue.record("Line is not a JSON object with a 'timestamp' string key")
      return
    }

    // ISO8601 pattern: YYYY-MM-DDTHH:MM:SSZ (or with fractional seconds)
    let iso8601Pattern = #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"#
    let matches = tsString.range(of: iso8601Pattern, options: .regularExpression) != nil
    #expect(
      matches,
      "timestamp '\(tsString)' does not match ISO8601 pattern '\(iso8601Pattern)'"
    )
  }

  @Test("Emitted JSON has sorted keys")
  func encoderUsesSortedKeys() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let sink = try TelemetryJSONLSink(traceURL: url)
    await sink.write(kind: "sorted-keys", payload: Ping(message: "keys"))
    await sink.close()

    let allLines = try lines(at: url)
    #expect(allLines.count == 1, "Expected one line for sorted-keys check")

    guard let rawString = String(data: Data(allLines[0]), encoding: .utf8) else {
      Issue.record("Line is not valid UTF-8")
      return
    }

    // Envelope keys in expected sorted order: "kind", "payload", "timestamp"
    let kindIdx = rawString.range(of: "\"kind\"")?.lowerBound
    let payloadIdx = rawString.range(of: "\"payload\"")?.lowerBound
    let timestampIdx = rawString.range(of: "\"timestamp\"")?.lowerBound

    if let k = kindIdx, let p = payloadIdx, let t = timestampIdx {
      #expect(k < p, "Expected 'kind' before 'payload' (sorted keys)")
      #expect(p < t, "Expected 'payload' before 'timestamp' (sorted keys)")
    } else {
      Issue.record("Could not find all three envelope keys in: \(rawString)")
    }
  }

  @Test("Emitted JSON does not escape forward slashes")
  func encoderDoesNotEscapeSlashes() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    struct URLPayload: Encodable {
      let path: String
    }

    let sink = try TelemetryJSONLSink(traceURL: url)
    await sink.write(kind: "slash", payload: URLPayload(path: "/Library/Caches/vinetas/telemetry/trace.jsonl"))
    await sink.close()

    let allLines = try lines(at: url)
    #expect(allLines.count == 1, "Expected one line for slash check")

    guard let rawString = String(data: Data(allLines[0]), encoding: .utf8) else {
      Issue.record("Line is not valid UTF-8")
      return
    }

    // With .withoutEscapingSlashes the encoder writes "/" not "\/"
    #expect(
      !rawString.contains("\\/"),
      "Encoder should not escape forward slashes (found \\/ in: \(rawString))"
    )
    #expect(
      rawString.contains("/Library"),
      "The literal slash should appear in the JSON output; got: \(rawString)"
    )
  }

  @Test("Envelope contains timestamp, kind, and payload keys")
  func envelopeHasRequiredKeys() async throws {
    let url = makeTraceURL()
    defer { try? FileManager.default.removeItem(at: url) }

    let sink = try TelemetryJSONLSink(traceURL: url)
    await sink.write(kind: "envelope-keys", payload: Ping(message: "check"))
    await sink.close()

    let allLines = try lines(at: url)
    #expect(allLines.count == 1)

    let dict = try JSONSerialization.jsonObject(with: Data(allLines[0])) as? [String: Any]
    #expect(dict != nil, "Line must parse as a JSON object")
    #expect(dict?["timestamp"] != nil, "Missing 'timestamp' key")
    #expect(dict?["kind"] != nil, "Missing 'kind' key")
    #expect(dict?["payload"] != nil, "Missing 'payload' key")
    #expect((dict?["kind"] as? String) == "envelope-keys", "kind should be 'envelope-keys'")
  }
}

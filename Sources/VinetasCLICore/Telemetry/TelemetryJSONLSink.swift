import Foundation

// MARK: - defaultTraceURL

/// Returns the default path for a JSONL telemetry trace file.
///
/// - macOS: `~/Library/Caches/vinetas/telemetry/<ISO8601-no-colons>.jsonl`
/// - Linux/CI: `$XDG_CACHE_HOME/vinetas/telemetry/...` or
///             `~/.cache/vinetas/telemetry/...`
///
/// Colons are stripped from the timestamp to make it safe on FAT-formatted
/// volumes (§7.5).  The parent directory is created if it does not exist.
public func defaultTraceURL() -> URL {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  let timestamp = formatter.string(from: Date())
    .replacingOccurrences(of: ":", with: "")

  let cacheDir = cacheDirectory()
    .appendingPathComponent("vinetas", isDirectory: true)
    .appendingPathComponent("telemetry", isDirectory: true)

  try? FileManager.default.createDirectory(
    at: cacheDir,
    withIntermediateDirectories: true
  )

  return cacheDir.appendingPathComponent("\(timestamp).jsonl")
}

/// Returns the per-platform user cache directory base.
private func cacheDirectory() -> URL {
  #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    // Apple platforms: ~/Library/Caches
    return FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
  #else
    // Linux / CI: honour $XDG_CACHE_HOME, then default to ~/.cache
    if let xdgCache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"],
      !xdgCache.isEmpty
    {
      return URL(fileURLWithPath: xdgCache)
    }
    let home = ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
    return URL(fileURLWithPath: home).appendingPathComponent(".cache", isDirectory: true)
  #endif
}

// MARK: - TelemetryJSONLSink

/// An actor that writes JSONL telemetry envelopes to a file, one per line,
/// with a flush after every write.
///
/// Usage:
/// ```swift
/// let sink = try TelemetryJSONLSink(traceURL: someURL)
/// await sink.write(kind: "vinetas", payload: myPayload)
/// await sink.close()
/// ```
public actor TelemetryJSONLSink {
  private let fileHandle: FileHandle
  private let encoder: JSONEncoder
  public let traceURL: URL

  /// Creates a new sink writing to `traceURL`.
  ///
  /// - Creates all intermediate directories if they do not exist.
  /// - Creates the file if it does not exist.
  /// - Throws if the file cannot be opened for writing.
  public init(traceURL: URL) throws {
    try FileManager.default.createDirectory(
      at: traceURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: traceURL.path, contents: nil)
    self.fileHandle = try FileHandle(forWritingTo: traceURL)

    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    enc.dateEncodingStrategy = .iso8601
    self.encoder = enc

    self.traceURL = traceURL
  }

  /// Encodes `payload` into a `TelemetryEnvelope` and appends it as a single
  /// JSON line (terminated by `0x0A`) to the trace file.
  ///
  /// Failures are silently swallowed so a broken payload never kills the
  /// generation command — telemetry is always best-effort.
  public func write<P: Encodable>(kind: String, payload: P) async {
    let envelope = TelemetryEnvelope(
      timestamp: Date(),
      kind: kind,
      payload: AnyEncodable(payload)
    )
    guard let data = try? encoder.encode(envelope) else { return }
    fileHandle.write(data)
    fileHandle.write(Data([0x0A]))
  }

  /// Flushes and closes the underlying file handle.
  public func close() async {
    try? fileHandle.close()
  }
}

import Foundation

// MARK: - AnyEncodable

/// Minimal type-erasure shim so TelemetryEnvelope's `payload` field can box
/// any `Encodable` value without knowing its concrete type at compile time.
public struct AnyEncodable: Encodable {
  private let _encode: (Encoder) throws -> Void

  public init<T: Encodable>(_ value: T) {
    self._encode = value.encode
  }

  public func encode(to encoder: Encoder) throws {
    try _encode(encoder)
  }
}

// MARK: - TelemetryEnvelope

/// The JSON object written per line in the JSONL trace file.
///
/// Example output:
/// ```json
/// {"kind":"vinetas","payload":{...},"timestamp":"2026-05-15T14:30:22Z"}
/// ```
public struct TelemetryEnvelope: Encodable {
  public let timestamp: Date
  public let kind: String
  public let payload: AnyEncodable

  public init(timestamp: Date, kind: String, payload: AnyEncodable) {
    self.timestamp = timestamp
    self.kind = kind
    self.payload = payload
  }
}

import Foundation

/// A raw JSON value carried verbatim inside a `Codable` record.
///
/// Used to embed a GLOSA shot's schema JSON (`Shot.schemaJSONData()`) in
/// ``ImageOutput/PanelMetadata/GlosaRecord`` as a bare JSON object. Unlike
/// `GlosaJSONValue`'s `Codable` form (which wraps objects as
/// `{"object": [...]}`), objects encode as keyed containers and arrays as
/// unkeyed containers, so the sidecar holds the shot exactly as the schema
/// defines it.
///
/// Numbers keep their kind: integers decode as `Int64` or `UInt64` and
/// re-encode exactly (no `Double` round-trip, so values above 2^53 survive);
/// only non-integral numbers are carried as `Double`. Booleans stay booleans.
enum RawJSONValue: Sendable, Equatable, Codable {
  case null
  case bool(Bool)
  case int(Int64)
  case uint(UInt64)
  case double(Double)
  case string(String)
  case array([RawJSONValue])
  case object([String: RawJSONValue])

  /// A dynamic coding key for arbitrary object member names.
  private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
  }

  init(from decoder: any Decoder) throws {
    if let keyed = try? decoder.container(keyedBy: Key.self) {
      var members: [String: RawJSONValue] = [:]
      for key in keyed.allKeys {
        members[key.stringValue] = try keyed.decode(RawJSONValue.self, forKey: key)
      }
      self = .object(members)
      return
    }
    if var unkeyed = try? decoder.unkeyedContainer() {
      var elements: [RawJSONValue] = []
      while !unkeyed.isAtEnd {
        elements.append(try unkeyed.decode(RawJSONValue.self))
      }
      self = .array(elements)
      return
    }
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .int(value)
    } else if let value = try? container.decode(UInt64.self) {
      self = .uint(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Value is not JSON")
    }
  }

  func encode(to encoder: any Encoder) throws {
    switch self {
    case .object(let members):
      var keyed = encoder.container(keyedBy: Key.self)
      for (key, value) in members {
        try keyed.encode(value, forKey: Key(stringValue: key))
      }
    case .array(let elements):
      var unkeyed = encoder.unkeyedContainer()
      for element in elements {
        try unkeyed.encode(element)
      }
    case .null:
      var container = encoder.singleValueContainer()
      try container.encodeNil()
    case .bool(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .int(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .uint(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .double(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    case .string(let value):
      var container = encoder.singleValueContainer()
      try container.encode(value)
    }
  }

  /// Decodes `data` (UTF-8 JSON text) into a raw value.
  init(jsonData data: Data) throws {
    self = try JSONDecoder().decode(RawJSONValue.self, from: data)
  }

  /// Compact JSON text for this value, keys sorted.
  func jsonData() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(self)
  }
}

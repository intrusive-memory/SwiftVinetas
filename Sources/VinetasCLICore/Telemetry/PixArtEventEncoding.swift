import Foundation
import PixArtBackbone
import Tuberia

// MARK: - PixArtEventCodable
//
// Flattens each `PixArtTelemetryEvent` case to a JSON object with a top-level
// "case" discriminant key plus the case's named fields at the same level.
//
// Example output:
//   {"case":"numericalAnomaly","phase":"ditForward","kind":"nan",…}
//
// TuberiaTensorStat is already Codable (it conforms in SwiftTuberia), so
// stat-bearing cases encode verbatim without redefining TuberiaTensorStat.
//
// Covers all 7 top-level cases of PixArtTelemetryEvent (PixArtBackbone 0.7.2+).

public struct PixArtEventCodable: Encodable {
  public let event: PixArtTelemetryEvent

  public init(event: PixArtTelemetryEvent) {
    self.event = event
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch event {

    // MARK: - Resource lifecycle

    case let .weightLoadComplete(component, paramCount, durationSeconds):
      try container.encode("weightLoadComplete", forKey: .case)
      try container.encode(component.rawValue, forKey: .component)
      try container.encode(paramCount, forKey: .paramCount)
      try container.encode(durationSeconds, forKey: .durationSeconds)

    case .weightUnloadComplete:
      try container.encode("weightUnloadComplete", forKey: .case)

    // MARK: - Recipe configuration

    case let .recipeValidated(name, checksPassed):
      try container.encode("recipeValidated", forKey: .case)
      try container.encode(name, forKey: .name)
      try container.encode(checksPassed, forKey: .checksPassed)

    case let .recipeValidationFailed(name, check, reason):
      try container.encode("recipeValidationFailed", forKey: .case)
      try container.encode(name, forKey: .name)
      try container.encode(check, forKey: .check)
      try container.encode(reason, forKey: .reason)

    // MARK: - Forward-pass output statistics

    case let .backboneForwardComplete(stat):
      try container.encode("backboneForwardComplete", forKey: .case)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(stat, forKey: .stat)

    // MARK: - Side channels

    case let .numericalAnomaly(phase, kind, stat):
      try container.encode("numericalAnomaly", forKey: .case)
      try container.encode(phase.rawValue, forKey: .phase)
      try container.encode(kind.rawValue, forKey: .kind)
      // TuberiaTensorStat is Codable — encode verbatim.
      try container.encode(stat, forKey: .stat)

    case let .errorThrown(phase, errorDescription):
      try container.encode("errorThrown", forKey: .case)
      try container.encode(phase.rawValue, forKey: .phase)
      try container.encode(errorDescription, forKey: .errorDescription)
    }
  }

  // MARK: - CodingKeys

  private enum CodingKeys: String, CodingKey {
    case `case`
    case component
    case paramCount
    case durationSeconds
    case name
    case checksPassed
    case check
    case reason
    case phase
    case kind
    case stat
    case errorDescription
  }
}

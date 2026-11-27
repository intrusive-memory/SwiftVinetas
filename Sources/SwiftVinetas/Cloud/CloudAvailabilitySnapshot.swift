import Foundation

/// What a vendor check last found out about one cloud provider (requirements
/// R-5). All model IDs here are Vinetas IDs (``CloudModelDescriptor/id``), not
/// the vendor's.
public struct CloudAvailabilitySnapshot: Codable, Sendable, Equatable {

  /// How the last check ended.
  public enum Status: Codable, Sendable, Equatable {
    /// The vendor answered; ``CloudAvailabilitySnapshot/modelIDs`` lists what it confirmed.
    case available
    /// No API key was configured, so no check was made.
    case noKey
    /// The vendor rejected the key.
    case keyRejected(reason: CloudEngineError.KeyRejectionReason)
    /// The check failed on the network or with a 5xx. The models of the last good
    /// snapshot are kept.
    case unreachable
    /// The vendor can't list models; the key check passed (R-9).
    case unsupported

    // On-disk shape: {"state": "keyRejected", "reason": "expired"}. `reason`
    // appears only for `keyRejected`.
    private enum CodingKeys: String, CodingKey { case state, reason }

    public init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let state = try container.decode(String.self, forKey: .state)
      switch state {
      case "available": self = .available
      case "noKey": self = .noKey
      case "keyRejected":
        self = .keyRejected(
          reason: try container.decode(CloudEngineError.KeyRejectionReason.self, forKey: .reason))
      case "unreachable": self = .unreachable
      case "unsupported": self = .unsupported
      default:
        throw DecodingError.dataCorruptedError(
          forKey: .state, in: container, debugDescription: "unknown status \(state)")
      }
    }

    public func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      switch self {
      case .available: try container.encode("available", forKey: .state)
      case .noKey: try container.encode("noKey", forKey: .state)
      case .keyRejected(let reason):
        try container.encode("keyRejected", forKey: .state)
        try container.encode(reason, forKey: .reason)
      case .unreachable: try container.encode("unreachable", forKey: .state)
      case .unsupported: try container.encode("unsupported", forKey: .state)
      }
    }
  }

  public var provider: CloudProvider
  public var status: Status

  /// Our IDs of the models the check confirmed.
  public var modelIDs: Set<String>

  /// When the vendor was last asked.
  public var checkedAt: Date

  /// A salted hash prefix of the key the check used, so a changed key can be
  /// noticed. `nil` when there was no key. The key itself is never stored.
  public var keyFingerprint: String?

  /// Our model ID to the vendor's announced shutdown date (start of that day, UTC).
  public var shutdownDates: [String: Date]

  public init(
    provider: CloudProvider,
    status: Status,
    modelIDs: Set<String> = [],
    checkedAt: Date,
    keyFingerprint: String? = nil,
    shutdownDates: [String: Date] = [:]
  ) {
    self.provider = provider
    self.status = status
    self.modelIDs = modelIDs
    self.checkedAt = checkedAt
    self.keyFingerprint = keyFingerprint
    self.shutdownDates = shutdownDates
  }

  // `modelIDs` is written sorted so the file is stable between writes.
  private enum CodingKeys: String, CodingKey {
    case provider, status, modelIDs, checkedAt, keyFingerprint, shutdownDates
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    provider = try container.decode(CloudProvider.self, forKey: .provider)
    status = try container.decode(Status.self, forKey: .status)
    modelIDs = Set(try container.decode([String].self, forKey: .modelIDs))
    checkedAt = try container.decode(Date.self, forKey: .checkedAt)
    keyFingerprint = try container.decodeIfPresent(String.self, forKey: .keyFingerprint)
    shutdownDates =
      try container.decodeIfPresent([String: Date].self, forKey: .shutdownDates) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(provider, forKey: .provider)
    try container.encode(status, forKey: .status)
    try container.encode(modelIDs.sorted(), forKey: .modelIDs)
    try container.encode(checkedAt, forKey: .checkedAt)
    try container.encodeIfPresent(keyFingerprint, forKey: .keyFingerprint)
    try container.encode(shutdownDates, forKey: .shutdownDates)
  }

  // MARK: Shutdown rule (R-5a, past-shutdown part)

  /// Whether `modelID`'s shutdown date is today or earlier, comparing UTC days.
  /// Applies even to a model the vendor still lists.
  public func isPastShutdown(_ modelID: String, now: Date = Date()) -> Bool {
    guard let shutdown = shutdownDates[modelID] else { return false }
    return Self.utcDay(shutdown) <= Self.utcDay(now)
  }

  /// Whether this snapshot says `modelID` can be used: the status allows models,
  /// the check confirmed it, and its shutdown date hasn't arrived.
  public func isModelAvailable(_ modelID: String, now: Date = Date()) -> Bool {
    switch status {
    case .noKey, .keyRejected: return false
    case .available, .unreachable, .unsupported: break
    }
    return modelIDs.contains(modelID) && !isPastShutdown(modelID, now: now)
  }

  /// The confirmed models that are not past their shutdown date.
  public func availableModelIDs(now: Date = Date()) -> Set<String> {
    Set(modelIDs.filter { isModelAvailable($0, now: now) })
  }

  private static func utcDay(_ date: Date) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.startOfDay(for: date)
  }

  // MARK: Vendor listing mapping (used by the availability service)

  /// Maps a vendor listing to our model IDs and shutdown dates for `provider`.
  /// A listing that doesn't list models (BFL, Stability) maps to every known
  /// model of the provider (R-9). Shutdown dates are matched whether or not the
  /// model was listed; the earliest date wins when several vendor IDs match.
  static func mapping(
    of listing: CloudVendorListing, provider: CloudProvider
  ) -> (modelIDs: Set<String>, shutdownDates: [String: Date]) {
    var modelIDs = Set<String>()
    var shutdownDates: [String: Date] = [:]
    for model in provider.models {
      if let vendorIDs = listing.modelIDs {
        if vendorIDs.contains(where: { model.matches(vendorID: $0) }) {
          modelIDs.insert(model.id)
        }
      } else {
        modelIDs.insert(model.id)
      }
      for (vendorID, date) in listing.shutdownDates where model.matches(vendorID: vendorID) {
        shutdownDates[model.id] = min(shutdownDates[model.id] ?? date, date)
      }
    }
    return (modelIDs, shutdownDates)
  }
}

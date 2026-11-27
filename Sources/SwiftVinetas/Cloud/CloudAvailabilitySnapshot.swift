import CryptoKit
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

  // MARK: Smart expiry (R-7a)

  /// The raw model IDs the vendor returned, before mapping to our IDs. A reader
  /// whose ``catalogDigest`` differs re-maps these against its own model table
  /// instead of trusting ``modelIDs``. Empty when the vendor doesn't list models
  /// (see ``vendorListsModels``) or the check made no listing.
  public var vendorModelIDs: Set<String>

  /// Whether the vendor listed its models. `false` for a key-check-only vendor
  /// (R-9), whose listing maps to every known model of the provider.
  public var vendorListsModels: Bool

  /// The raw vendor model ID to shutdown date, as the vendor returned them, so
  /// ``shutdownDates`` can be re-mapped along with ``vendorModelIDs``.
  public var vendorShutdownDates: [String: Date]

  /// ``catalogDigest(for:)`` of the build that wrote this snapshot. A reader
  /// with another digest treats the snapshot as stale and re-maps it.
  public var catalogDigest: String

  public init(
    provider: CloudProvider,
    status: Status,
    modelIDs: Set<String> = [],
    checkedAt: Date,
    keyFingerprint: String? = nil,
    shutdownDates: [String: Date] = [:],
    vendorModelIDs: Set<String> = [],
    vendorListsModels: Bool = true,
    vendorShutdownDates: [String: Date] = [:],
    catalogDigest: String? = nil
  ) {
    self.provider = provider
    self.status = status
    self.modelIDs = modelIDs
    self.checkedAt = checkedAt
    self.keyFingerprint = keyFingerprint
    self.shutdownDates = shutdownDates
    self.vendorModelIDs = vendorModelIDs
    self.vendorListsModels = vendorListsModels
    self.vendorShutdownDates = vendorShutdownDates
    self.catalogDigest = catalogDigest ?? Self.catalogDigest(for: provider)
  }

  // `modelIDs` and `vendorModelIDs` are written sorted so the file is stable
  // between writes.
  private enum CodingKeys: String, CodingKey {
    case provider, status, modelIDs, checkedAt, keyFingerprint, shutdownDates
    case vendorModelIDs, vendorListsModels, vendorShutdownDates, catalogDigest
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
    vendorModelIDs = Set(
      try container.decodeIfPresent([String].self, forKey: .vendorModelIDs) ?? [])
    vendorListsModels =
      try container.decodeIfPresent(Bool.self, forKey: .vendorListsModels) ?? true
    vendorShutdownDates =
      try container.decodeIfPresent([String: Date].self, forKey: .vendorShutdownDates) ?? [:]
    // A missing digest never matches a reader's, so such a snapshot is stale.
    catalogDigest = try container.decodeIfPresent(String.self, forKey: .catalogDigest) ?? ""
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(provider, forKey: .provider)
    try container.encode(status, forKey: .status)
    try container.encode(modelIDs.sorted(), forKey: .modelIDs)
    try container.encode(checkedAt, forKey: .checkedAt)
    try container.encodeIfPresent(keyFingerprint, forKey: .keyFingerprint)
    try container.encode(shutdownDates, forKey: .shutdownDates)
    try container.encode(vendorModelIDs.sorted(), forKey: .vendorModelIDs)
    try container.encode(vendorListsModels, forKey: .vendorListsModels)
    try container.encode(vendorShutdownDates, forKey: .vendorShutdownDates)
    try container.encode(catalogDigest, forKey: .catalogDigest)
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
    mapping(of: listing, models: provider.models)
  }

  /// ``mapping(of:provider:)`` against an explicit model table.
  static func mapping(
    of listing: CloudVendorListing, models: [CloudModelDescriptor]
  ) -> (modelIDs: Set<String>, shutdownDates: [String: Date]) {
    var modelIDs = Set<String>()
    var shutdownDates: [String: Date] = [:]
    for model in models {
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

  // MARK: Catalog digest and re-mapping (R-7a)

  /// A digest of `provider`'s known models (``CloudProvider/models``): each
  /// model's `id`, `vendorModelID` and sorted `vendorAliases`, the models sorted
  /// by `id`, hashed with SHA-256; the first 16 hex characters. It is computed
  /// from the model table, so adding, removing or re-aliasing a model changes it
  /// with no other edit.
  public static func catalogDigest(for provider: CloudProvider) -> String {
    catalogDigest(of: provider.models)
  }

  /// ``catalogDigest(for:)`` of an explicit model table.
  static func catalogDigest(of models: [CloudModelDescriptor]) -> String {
    // Unit (0x1F) and record (0x1E) separators can't appear in an ID, so the
    // input is unambiguous.
    let lines = models.sorted { $0.id < $1.id }.map { model in
      ([model.id, model.vendorModelID] + model.vendorAliases.sorted())
        .joined(separator: "\u{1F}")
    }
    let digest = SHA256.hash(data: Data(lines.joined(separator: "\u{1E}").utf8))
    return String(digest.map { String(format: "%02x", $0) }.joined().prefix(16))
  }

  /// This snapshot as a reader with model table `models` and digest `digest`
  /// sees it. When the snapshot's ``catalogDigest`` matches, it is returned
  /// unchanged. Otherwise ``modelIDs`` and ``shutdownDates`` are rebuilt from
  /// ``vendorModelIDs`` and ``vendorShutdownDates`` through the reader's own
  /// mapping, so a newly added model shows up and a model the reader doesn't
  /// know drops out. ``catalogDigest`` is kept as written, so the snapshot
  /// stays stale and the next refresh checks the vendor again. Snapshots that
  /// offer no models (`.noKey`, `.keyRejected`) are not re-mapped.
  func remapped(models: [CloudModelDescriptor], digest: String) -> CloudAvailabilitySnapshot {
    guard catalogDigest != digest else { return self }
    switch status {
    case .noKey, .keyRejected: return self
    case .available, .unreachable, .unsupported: break
    }
    let listing = CloudVendorListing(
      modelIDs: vendorListsModels ? vendorModelIDs : nil,
      shutdownDates: vendorShutdownDates)
    let mapped = Self.mapping(of: listing, models: models)
    var copy = self
    copy.modelIDs = mapped.modelIDs
    copy.shutdownDates = mapped.shutdownDates
    return copy
  }

  /// ``remapped(models:digest:)`` against this build's model table.
  func remappedForCurrentCatalog() -> CloudAvailabilitySnapshot {
    remapped(models: provider.models, digest: Self.catalogDigest(for: provider))
  }
}

import Foundation

/// What one vendor's listing call returned (requirements R-6, R-9, R-9a).
///
/// `modelIDs` is `nil` when the vendor has no way to list models (BFL and
/// Stability, R-9): the call only proved the key works. That is different from
/// an empty set, which means the vendor listed nothing. The IDs are *vendor*
/// model IDs, to be matched against ``CloudModelDescriptor/matches(vendorID:)``.
struct CloudVendorListing: Sendable, Equatable {

  /// Vendor model IDs, or `nil` when the vendor doesn't list models.
  let modelIDs: Set<String>?

  /// Retirement dates by vendor model ID, for the models that have one
  /// (OpenAI's `shutdown_date`, read as the start of that day in UTC).
  let shutdownDates: [String: Date]

  init(modelIDs: Set<String>?, shutdownDates: [String: Date] = [:]) {
    self.modelIDs = modelIDs
    self.shutdownDates = shutdownDates
  }

  /// A listing from a vendor that only offers a key check (R-9).
  static let keyVerifiedOnly = CloudVendorListing(modelIDs: nil)

  /// Whether the vendor listed its models at all.
  var vendorListsModels: Bool { modelIDs != nil }
}

enum CloudListing {

  /// Most pages followed for one listing, so a server that keeps returning a
  /// `nextPageToken` can't loop forever.
  static let maxPages = 10

  /// Parses a `YYYY-MM-DD` date as the start of that day in UTC.
  static func parseDay(_ text: String) -> Date? {
    let parts = text.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3, text.count == 10 else { return nil }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(
      from: DateComponents(
        timeZone: calendar.timeZone, year: parts[0], month: parts[1], day: parts[2]))
  }

  static func json(_ data: Data, provider: CloudProvider) throws -> [String: Any] {
    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw CloudEngineError.invalidResponse(provider: provider, detail: "non-JSON listing body")
    }
    return object
  }
}

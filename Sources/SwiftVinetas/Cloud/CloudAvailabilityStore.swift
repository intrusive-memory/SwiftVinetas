import Foundation
import SwiftAcervo

/// Persists one ``CloudAvailabilitySnapshot`` per provider as JSON, plus the
/// random salt for key fingerprints (requirements R-7, D-4, OQ-3).
///
/// Files live in `<App Group container>/vinetas-cloud-availability/`, or when
/// there is no container, `<Caches>/io.intrusive-memory.Vinetas/cloud-availability/`.
/// Tests pass their own directory.
struct CloudAvailabilityStore: Sendable {

  /// Bump when the file shape or its meaning changes (R-7a). A file with
  /// another version is ignored, as if the vendor was never checked, and is
  /// never deleted: an older process may still read its own version.
  ///
  /// - 1: S6 snapshot.
  /// - 2: adds `vendorModelIDs`, `vendorListsModels`, `vendorShutdownDates`
  ///   and `catalogDigest`.
  static let schemaVersion = 2

  /// A release can force every snapshot checked before this date to expire
  /// (R-7a), for a vendor change the catalog digest can't see. Raise it in a
  /// release; `.distantPast` expires nothing.
  static let minimumCheckedAt: Date = .distantPast

  static let appGroupDirectoryName = "vinetas-cloud-availability"
  static let cachesDirectoryPath = "io.intrusive-memory.Vinetas/cloud-availability"
  static let saltFileName = "fingerprint-salt.bin"
  static let saltLength = 32

  let directory: URL

  /// Snapshots checked before this are stale. ``minimumCheckedAt`` unless a
  /// test passes its own.
  let minimumCheckedAt: Date

  init(directory: URL, minimumCheckedAt: Date = CloudAvailabilityStore.minimumCheckedAt) {
    self.directory = directory
    self.minimumCheckedAt = minimumCheckedAt
  }

  /// A store in the default location for this process.
  init(
    appGroupContainer: () -> URL? = CloudAvailabilityStore.acervoContainer,
    cachesDirectory: () -> URL? = CloudAvailabilityStore.systemCaches
  ) {
    self.directory = Self.resolveDirectory(
      appGroupContainer: appGroupContainer, cachesDirectory: cachesDirectory)
    self.minimumCheckedAt = Self.minimumCheckedAt
  }

  /// The App Group container root, the way the CLI finds it: the parent of
  /// SwiftAcervo's shared-models directory. `nil` without the entitlement.
  static func acervoContainer() -> URL? {
    Acervo.resolvedSharedModelsDirectory?.deletingLastPathComponent()
  }

  static func systemCaches() -> URL? {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
  }

  /// The App Group directory when a container resolves, else the Caches one.
  /// Nothing is created here.
  static func resolveDirectory(
    appGroupContainer: () -> URL?, cachesDirectory: () -> URL?
  ) -> URL {
    if let container = appGroupContainer() {
      return container.appendingPathComponent(appGroupDirectoryName, isDirectory: true)
    }
    let caches = cachesDirectory() ?? FileManager.default.temporaryDirectory
    return caches.appendingPathComponent(cachesDirectoryPath, isDirectory: true)
  }

  // MARK: Snapshots

  func fileURL(for provider: CloudProvider) -> URL {
    directory.appendingPathComponent("\(provider.rawValue).json")
  }

  private struct Header: Decodable { let schemaVersion: Int }

  private struct File: Codable {
    let schemaVersion: Int
    let snapshot: CloudAvailabilitySnapshot
  }

  /// The stored snapshot, or `nil` when there is none, the file is corrupt,
  /// it has another schema version, or it belongs to another provider. A file
  /// with another schema version is left on disk. The snapshot is returned as
  /// written; the service re-maps it for its own catalog (R-7a).
  func read(_ provider: CloudProvider) -> CloudAvailabilitySnapshot? {
    guard let data = try? Data(contentsOf: fileURL(for: provider)) else { return nil }
    let decoder = Self.decoder()
    guard let header = try? decoder.decode(Header.self, from: data),
      header.schemaVersion == Self.schemaVersion,
      let file = try? decoder.decode(File.self, from: data),
      file.snapshot.provider == provider
    else { return nil }
    return file.snapshot
  }

  /// Writes the snapshot atomically, creating the directory when needed.
  func write(_ snapshot: CloudAvailabilitySnapshot) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try Self.encoder().encode(
      File(schemaVersion: Self.schemaVersion, snapshot: snapshot))
    try data.write(to: fileURL(for: snapshot.provider), options: .atomic)
  }

  func remove(_ provider: CloudProvider) {
    try? FileManager.default.removeItem(at: fileURL(for: provider))
  }

  // MARK: Fingerprint

  /// The fingerprint of `apiKey` under this directory's salt. The key is used
  /// only as hash input.
  func fingerprint(apiKey: String) throws -> String {
    CloudAvailabilityFingerprint.make(apiKey: apiKey, salt: try salt())
  }

  /// The salt: 32 random bytes, generated once and kept beside the snapshots
  /// (mode 0600). Creation is atomic, so two processes end up with one salt.
  func salt() throws -> Data {
    let url = directory.appendingPathComponent(Self.saltFileName)
    if let existing = Self.readSalt(url) { return existing }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    // A wrong-sized file is damaged; replace it.
    try? FileManager.default.removeItem(at: url)

    var bytes = [UInt8](repeating: 0, count: Self.saltLength)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw CocoaError(.fileWriteUnknown)
    }
    let temp = directory.appendingPathComponent(".salt-\(UUID().uuidString)")
    try Data(bytes).write(to: temp, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
    defer { try? FileManager.default.removeItem(at: temp) }
    // link() fails if another process won the race; then we read theirs.
    _ = link(temp.path, url.path)
    guard let salt = Self.readSalt(url) else { throw CocoaError(.fileReadCorruptFile) }
    return salt
  }

  private static func readSalt(_ url: URL) -> Data? {
    guard let data = try? Data(contentsOf: url), data.count == saltLength else { return nil }
    return data
  }

  // MARK: Coding

  private static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }

  private static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

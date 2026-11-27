import Foundation
import Testing

@testable import SwiftVinetas

// Covers the availability snapshot, its store and key fingerprint
// (requirements R-5, R-7 persistence, D-4, R-5a past-shutdown rule).
// Every test uses a temp directory; none touch the App Group or real Caches.

private func tempDirectory() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("cloud-availability-\(UUID().uuidString)", isDirectory: true)
}

private func utcDay(_ text: String) -> Date { CloudListing.parseDay(text)! }

private func openAIModel() -> CloudModelDescriptor { CloudProvider.openAI.models[0] }

@Suite("Cloud availability snapshot")
struct CloudAvailabilitySnapshotTests {

  @Test("Every status round-trips through JSON")
  func roundTrip() throws {
    let statuses: [CloudAvailabilitySnapshot.Status] =
      [.available, .noKey, .unreachable, .unsupported]
      + CloudEngineError.KeyRejectionReason.allCases.map { .keyRejected(reason: $0) }
    for status in statuses {
      let snapshot = CloudAvailabilitySnapshot(
        provider: .openAI, status: status, modelIDs: ["a", "b"],
        checkedAt: Date(timeIntervalSince1970: 1_800_000_000), keyFingerprint: "0123456789abcdef",
        shutdownDates: ["a": utcDay("2026-12-01")])
      let data = try JSONEncoder().encode(snapshot)
      #expect(try JSONDecoder().decode(CloudAvailabilitySnapshot.self, from: data) == snapshot)
    }
  }

  @Test("An unknown status fails to decode")
  func unknownStatus() {
    let json = Data(#"{"state":"mystery"}"#.utf8)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(CloudAvailabilitySnapshot.Status.self, from: json)
    }
  }

  @Test("A shutdown date of today or earlier makes a listed model unavailable")
  func pastShutdownRule() {
    let now = Date(timeIntervalSince1970: 1_795_000_000)  // 2026-11-18 UTC
    let day = ISO8601DateFormatter().string(from: now).prefix(10)
    let today = utcDay(String(day))
    let snapshot = CloudAvailabilitySnapshot(
      provider: .openAI, status: .available, modelIDs: ["past", "today", "future", "none"],
      checkedAt: now,
      shutdownDates: [
        "past": today.addingTimeInterval(-86_400), "today": today,
        "future": today.addingTimeInterval(86_400),
      ])
    #expect(!snapshot.isModelAvailable("past", now: now))
    #expect(!snapshot.isModelAvailable("today", now: now))
    // The same day, late in the evening UTC, still counts as today.
    #expect(!snapshot.isModelAvailable("today", now: today.addingTimeInterval(86_399)))
    #expect(snapshot.isModelAvailable("future", now: now))
    #expect(snapshot.isModelAvailable("none", now: now))
    #expect(snapshot.availableModelIDs(now: now) == ["future", "none"])
    // The day before the shutdown, the model is still usable.
    #expect(snapshot.isModelAvailable("today", now: today.addingTimeInterval(-1)))
  }

  @Test("Statuses without a working key offer no models")
  func statusGatesModels() {
    for status: CloudAvailabilitySnapshot.Status in [.noKey, .keyRejected(reason: .invalid)] {
      let snapshot = CloudAvailabilitySnapshot(
        provider: .openAI, status: status, modelIDs: ["a"], checkedAt: Date())
      #expect(!snapshot.isModelAvailable("a"))
    }
    let kept = CloudAvailabilitySnapshot(
      provider: .openAI, status: .unreachable, modelIDs: ["a"], checkedAt: Date())
    #expect(kept.isModelAvailable("a"))
  }

  @Test("A listing maps vendor IDs, aliases and shutdown dates to our IDs")
  func mapsListing() throws {
    let model = openAIModel()
    let alias = try #require(
      CloudProvider.openAI.models.first { !$0.vendorAliases.isEmpty })
    let aliasID = alias.vendorAliases[0]
    let early = utcDay("2026-12-01")
    let late = utcDay("2027-01-01")
    let listing = CloudVendorListing(
      modelIDs: [model.vendorModelID, aliasID, "unknown-vendor-model"],
      shutdownDates: [aliasID: late, alias.vendorModelID: early, "unknown-vendor-model": early])
    let mapped = CloudAvailabilitySnapshot.mapping(of: listing, provider: .openAI)
    #expect(mapped.modelIDs.contains(model.id))
    #expect(mapped.modelIDs.contains(alias.id))
    #expect(!mapped.modelIDs.contains("unknown-vendor-model"))
    #expect(mapped.shutdownDates[alias.id] == early)  // earliest wins
    #expect(
      mapped.shutdownDates.keys.allSatisfy { id in
        CloudProvider.openAI.models.contains { $0.id == id }
      })
  }

  @Test("A key-verified-only listing maps to every known model of the provider")
  func keyVerifiedMapsToAll() {
    let mapped = CloudAvailabilitySnapshot.mapping(of: .keyVerifiedOnly, provider: .stabilityAI)
    #expect(mapped.modelIDs == Set(CloudProvider.stabilityAI.models.map(\.id)))
    #expect(mapped.shutdownDates.isEmpty)
  }
}

@Suite("Cloud availability fingerprint")
struct CloudAvailabilityFingerprintTests {

  @Test("Stable for one key and salt, different for another key or salt")
  func stabilityAndChange() {
    let salt = Data(repeating: 7, count: 32)
    let one = CloudAvailabilityFingerprint.make(apiKey: "sk-test-one", salt: salt)
    #expect(one == CloudAvailabilityFingerprint.make(apiKey: "sk-test-one", salt: salt))
    #expect(one != CloudAvailabilityFingerprint.make(apiKey: "sk-test-two", salt: salt))
    #expect(
      one
        != CloudAvailabilityFingerprint.make(
          apiKey: "sk-test-one", salt: Data(repeating: 8, count: 32)))
    #expect(one.count == CloudAvailabilityFingerprint.length)
    #expect(one.allSatisfy { $0.isHexDigit })
    #expect(!one.contains("sk-test"))
  }
}

@Suite("Cloud availability store")
struct CloudAvailabilityStoreTests {

  private func sample(_ provider: CloudProvider = .openAI) -> CloudAvailabilitySnapshot {
    CloudAvailabilitySnapshot(
      provider: provider, status: .keyRejected(reason: .expired), modelIDs: ["x"],
      checkedAt: Date(timeIntervalSince1970: 1_800_000_000), keyFingerprint: "abcdef0123456789",
      shutdownDates: ["x": utcDay("2026-12-01")])
  }

  @Test("Writes create the directory and read back the same snapshot per provider")
  func readWrite() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = CloudAvailabilityStore(directory: dir)
    #expect(store.read(.openAI) == nil)
    try store.write(sample(.openAI))
    try store.write(sample(.google))
    #expect(store.read(.openAI) == sample(.openAI))
    #expect(store.read(.google) == sample(.google))
    #expect(store.read(.blackForestLabs) == nil)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("openAI.json").path))
  }

  @Test("A corrupt, wrong-schema or wrong-provider file reads as nil")
  func badFiles() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = CloudAvailabilityStore(directory: dir)
    try store.write(sample(.openAI))
    let url = store.fileURL(for: .openAI)

    try Data("not json {".utf8).write(to: url)
    #expect(store.read(.openAI) == nil)

    try store.write(sample(.openAI))
    let good = try String(contentsOf: url, encoding: .utf8)
    try good.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
      .write(to: url, atomically: true, encoding: .utf8)
    #expect(store.read(.openAI) == nil)

    // A future file whose body no longer decodes, but names its version.
    try Data(#"{"schemaVersion":2,"snapshot":{"shape":"new"}}"#.utf8).write(to: url)
    #expect(store.read(.openAI) == nil)

    try store.write(sample(.google))
    try FileManager.default.removeItem(at: url)
    try FileManager.default.copyItem(at: store.fileURL(for: .google), to: url)
    #expect(store.read(.openAI) == nil)
  }

  @Test("The salt is created once, is 32 bytes, and is reused")
  func saltPersists() throws {
    let dir = tempDirectory()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = CloudAvailabilityStore(directory: dir)
    let salt = try store.salt()
    #expect(salt.count == 32)
    #expect(try store.salt() == salt)
    #expect(try CloudAvailabilityStore(directory: dir).salt() == salt)
    let attributes = try FileManager.default.attributesOfItem(
      atPath: dir.appendingPathComponent(CloudAvailabilityStore.saltFileName).path)
    #expect((attributes[.posixPermissions] as? Int) == 0o600)
    #expect(try store.fingerprint(apiKey: "k") == store.fingerprint(apiKey: "k"))
    // No temporary salt files are left behind.
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names == [CloudAvailabilityStore.saltFileName])
  }

  @Test("A different directory gets a different salt, so fingerprints differ")
  func saltPerDirectory() throws {
    let a = tempDirectory()
    let b = tempDirectory()
    defer {
      try? FileManager.default.removeItem(at: a)
      try? FileManager.default.removeItem(at: b)
    }
    #expect(
      try CloudAvailabilityStore(directory: a).fingerprint(apiKey: "k")
        != CloudAvailabilityStore(directory: b).fingerprint(apiKey: "k"))
  }

  @Test("The directory is the App Group one when a container resolves, else Caches")
  func directoryFallback() {
    let container = URL(fileURLWithPath: "/tmp/fake-group", isDirectory: true)
    let caches = URL(fileURLWithPath: "/tmp/fake-caches", isDirectory: true)

    let grouped = CloudAvailabilityStore.resolveDirectory(
      appGroupContainer: { container }, cachesDirectory: { caches })
    #expect(grouped.path == "/tmp/fake-group/vinetas-cloud-availability")

    let fallback = CloudAvailabilityStore.resolveDirectory(
      appGroupContainer: { nil }, cachesDirectory: { caches })
    #expect(fallback.path == "/tmp/fake-caches/io.intrusive-memory.Vinetas/cloud-availability")
    #expect(
      CloudAvailabilityStore(appGroupContainer: { nil }, cachesDirectory: { caches }).directory
        == fallback)
  }
}

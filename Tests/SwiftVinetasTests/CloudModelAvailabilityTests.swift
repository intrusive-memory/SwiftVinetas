import Foundation
import Testing
import os.lock

@testable import SwiftVinetas

// Covers the availability service (requirements R-4, R-7, R-8, R-19, R-21,
// D-2, D-3). Vendor checks go to a fake `CloudProviderClient` that counts its
// requests; one test drives the real OpenAI adapter through a stubbed
// `URLProtocol`. Every test uses its own temp directory and a fake clock; no
// test reaches the network, reads a real key, or waits on wall-clock time.

private func tempDirectory() -> URL {
  FileManager.default.temporaryDirectory
    .appendingPathComponent("cloud-model-availability-\(UUID().uuidString)", isDirectory: true)
}

/// A clock the test moves by hand.
private final class FakeClock: Sendable {
  private let date = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_800_000_000))
  var now: Date { date.withLock { $0 } }
  func advance(_ seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

/// Blocks callers of `wait()` until `open()`.
private actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    if isOpen { return }
    await withCheckedContinuation { waiters.append($0) }
  }

  func open() {
    isOpen = true
    for waiter in waiters { waiter.resume() }
    waiters = []
  }
}

/// A vendor adapter whose listing is scripted by the test. `requests` counts
/// listing calls; generation is never used here.
private final class FakeListingClient: CloudProviderClient, Sendable {
  let provider: CloudProvider
  private let count = OSAllocatedUnfairLock(initialState: 0)
  private let handler: @Sendable () async throws -> CloudVendorListing

  init(
    _ provider: CloudProvider,
    handler: @escaping @Sendable () async throws -> CloudVendorListing
  ) {
    self.provider = provider
    self.handler = handler
  }

  var requests: Int { count.withLock { $0 } }

  func generate(
    _ request: GenerationRequest, model: CloudModelDescriptor, apiKey: String,
    session: URLSession
  ) async throws -> CloudImageOutput {
    throw CloudEngineError.unsupportedFeature("generate", provider: provider)
  }

  func listAvailableModels(apiKey: String, session: URLSession) async throws
    -> CloudVendorListing
  {
    count.withLock { $0 += 1 }
    return try await handler()
  }
}

/// A listing confirming every known model of `provider` by its vendor ID.
private func fullListing(_ provider: CloudProvider) -> CloudVendorListing {
  CloudVendorListing(modelIDs: Set(provider.models.map(\.vendorModelID)))
}

/// Lets each test switch between success and failure for one fake.
private final class Outcome: Sendable {
  private let error = OSAllocatedUnfairLock<(any Error & Sendable)?>(initialState: nil)
  func fail(with error: any Error & Sendable) { self.error.withLock { $0 = error } }
  func succeed() { error.withLock { $0 = nil } }
  var currentError: (any Error)? { error.withLock { $0 } }
}

private struct Harness {
  let directory = tempDirectory()
  let clock = FakeClock()
  let keys: InMemoryAPIKeyStore
  let clients: [CloudProvider: FakeListingClient]
  let service: CloudModelAvailability

  var store: CloudAvailabilityStore { CloudAvailabilityStore(directory: directory) }

  init(
    keys: [CloudProvider: String] = [.openAI: "availability-test-key-not-real"],
    clients: [CloudProvider: FakeListingClient],
    deadline: Duration = CloudModelAvailability.checkDeadline
  ) {
    self.keys = InMemoryAPIKeyStore(keys: keys)
    self.clients = clients
    self.service = Self.makeService(
      keys: self.keys, clients: clients, directory: directory, clock: clock,
      deadline: deadline)
  }

  /// A second service on the same directory, as after a relaunch.
  func relaunched() -> CloudModelAvailability {
    Self.makeService(keys: keys, clients: clients, directory: directory, clock: clock)
  }

  private static func makeService(
    keys: InMemoryAPIKeyStore, clients: [CloudProvider: FakeListingClient],
    directory: URL, clock: FakeClock,
    deadline: Duration = CloudModelAvailability.checkDeadline
  ) -> CloudModelAvailability {
    CloudModelAvailability(
      keyStore: keys,
      session: nil,
      store: CloudAvailabilityStore(directory: directory),
      client: { provider in
        clients[provider]
          ?? FakeListingClient(provider) {
            Issue.record("unexpected check for \(provider)")
            throw URLError(.notConnectedToInternet)
          }
      },
      now: { clock.now },
      deadline: deadline)
  }

  func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

@Suite("Cloud model availability service")
struct CloudModelAvailabilityTests {

  // MARK: Cache rules (R-7, R-19, D-3)

  @Test("No key: .noKey snapshot, no request, no models")
  func noKeyMakesNoRequest() async {
    let client = FakeListingClient(.openAI) { fullListing(.openAI) }
    let harness = Harness(keys: [:], clients: [.openAI: client])
    defer { harness.cleanUp() }

    let snapshot = await harness.service.refresh(.openAI, force: true)
    #expect(snapshot.status == .noKey)
    #expect(snapshot.modelIDs.isEmpty)
    #expect(snapshot.keyFingerprint == nil)
    #expect(client.requests == 0)
    #expect(harness.store.read(.openAI)?.status == .noKey)
  }

  @Test("A fresh cache makes no request, in memory and after a relaunch")
  func freshCacheMakesNoRequest() async throws {
    let client = FakeListingClient(.openAI) { fullListing(.openAI) }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    let first = await harness.service.refresh(.openAI)
    #expect(first.status == .available)
    #expect(first.modelIDs == Set(CloudProvider.openAI.models.map(\.id)))
    #expect(first.checkedAt == harness.clock.now)
    #expect(
      first.keyFingerprint
        == (try harness.store.fingerprint(apiKey: "availability-test-key-not-real")))
    #expect(client.requests == 1)

    harness.clock.advance(CloudModelAvailability.freshness - 1)
    #expect(await harness.service.refresh(.openAI) == first)
    #expect(await harness.relaunched().refresh(.openAI) == first)
    #expect(await harness.relaunched().snapshot(for: .openAI) == first)
    #expect(client.requests == 1)
  }

  @Test("A cache older than 24 hours is checked again; force always checks")
  func staleCacheMakesRequest() async {
    let client = FakeListingClient(.openAI) { fullListing(.openAI) }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    await harness.service.refresh(.openAI)
    harness.clock.advance(CloudModelAvailability.freshness)
    let second = await harness.service.refresh(.openAI)
    #expect(client.requests == 2)
    #expect(second.checkedAt == harness.clock.now)

    await harness.service.refresh(.openAI, force: true)
    #expect(client.requests == 3)
  }

  @Test("Changing, removing or adding the key makes the cache stale at once")
  func keyChangeInvalidates() async throws {
    let client = FakeListingClient(.openAI) { fullListing(.openAI) }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    let first = await harness.service.refresh(.openAI)
    #expect(client.requests == 1)

    try harness.keys.setAPIKey("another-test-key-not-real", for: .openAI)
    let changed = await harness.service.refresh(.openAI)
    #expect(client.requests == 2)
    #expect(changed.keyFingerprint != first.keyFingerprint)

    try harness.keys.removeAPIKey(for: .openAI)
    let removed = await harness.service.refresh(.openAI)
    #expect(removed.status == .noKey)
    #expect(client.requests == 2)
    #expect(await harness.service.isAvailable(CloudProvider.openAI.models[0].id) == false)

    try harness.keys.setAPIKey("another-test-key-not-real", for: .openAI)
    #expect(await harness.service.refresh(.openAI).status == .available)
    #expect(client.requests == 3)
  }

  // MARK: Failures (R-8, D-2)

  @Test("A failed check keeps the last good models with .unreachable and the old checkedAt")
  func failureKeepsLastSnapshot() async {
    let outcome = Outcome()
    let client = FakeListingClient(.openAI) {
      if let error = outcome.currentError { throw error }
      return CloudVendorListing(modelIDs: [CloudProvider.openAI.models[0].vendorModelID])
    }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    let good = await harness.service.refresh(.openAI)
    harness.clock.advance(CloudModelAvailability.freshness + 60)
    outcome.fail(with: URLError(.timedOut))

    let failed = await harness.service.refresh(.openAI)
    #expect(failed.status == .unreachable)
    #expect(failed.modelIDs == good.modelIDs)
    #expect(failed.checkedAt == good.checkedAt)
    #expect(failed.isChecked)
    #expect(await harness.service.isAvailable(CloudProvider.openAI.models[0].id))
    #expect(await harness.service.isAvailable(CloudProvider.openAI.models[1].id) == false)
    #expect(harness.store.read(.openAI)?.status == .unreachable)

    #expect(client.requests == 2)  // the isAvailable calls fall inside the back-off

    // A 5xx keeps it too.
    harness.clock.advance(CloudModelAvailability.failureBackoff)
    outcome.fail(
      with: CloudEngineError.httpStatus(provider: .openAI, status: 500, message: nil))
    let again = await harness.service.refresh(.openAI)
    #expect(again == failed)
    #expect(client.requests == 3)
  }

  @Test(
    "After a failed check the vendor is left alone for 5 minutes unless forced or the key changed")
  func failureBacksOff() async throws {
    let outcome = Outcome()
    outcome.fail(with: URLError(.notConnectedToInternet))
    let client = FakeListingClient(.openAI) {
      if let error = outcome.currentError { throw error }
      return fullListing(.openAI)
    }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    let failed = await harness.service.refresh(.openAI)
    #expect(failed.status == .unreachable)
    #expect(client.requests == 1)

    // Straight away, and just inside the window: no request.
    #expect(await harness.service.refresh(.openAI) == failed)
    harness.clock.advance(CloudModelAvailability.failureBackoff - 1)
    _ = await harness.service.availableModels()
    #expect(client.requests == 1)

    // After the window: one request.
    harness.clock.advance(1)
    await harness.service.refresh(.openAI)
    #expect(client.requests == 2)

    // `force` bypasses the window.
    await harness.service.refresh(.openAI, force: true)
    #expect(client.requests == 3)

    // So does a new key.
    try harness.keys.setAPIKey("another-test-key-not-real", for: .openAI)
    await harness.service.refresh(.openAI)
    #expect(client.requests == 4)

    // A success clears the back-off: the next failure starts a new window.
    outcome.succeed()
    #expect(await harness.service.refresh(.openAI, force: true).status == .available)
    #expect(client.requests == 5)
  }

  @Test("A check that never answers is cut off at the deadline and counts as unreachable")
  func checkDeadlineCutsOffAHungVendor() async {
    // The fake sleeps far past the deadline but, like URLSession, stops when
    // cancelled. The assertion is on the outcome, not on elapsed time.
    let client = FakeListingClient(.openAI) {
      try await Task.sleep(for: .seconds(3600))
      return fullListing(.openAI)
    }
    let harness = Harness(clients: [.openAI: client], deadline: .milliseconds(50))
    defer { harness.cleanUp() }

    let snapshot = await harness.service.refresh(.openAI)
    #expect(snapshot.status == .unreachable)
    #expect(snapshot.isChecked == false)
    #expect(client.requests == 1)
  }

  @Test("The listing session fails fast offline and keeps no cache, cookies or credentials")
  func listingSessionIsShortAndClean() {
    let config = CloudHTTP.makeListingSession().configuration
    #expect(config.waitsForConnectivity == false)
    #expect(config.timeoutIntervalForRequest == 15)
    #expect(config.timeoutIntervalForResource == 30)
    #expect(config.urlCache == nil)
    #expect(config.httpCookieStorage == nil)
    #expect(config.httpShouldSetCookies == false)
    #expect(config.urlCredentialStorage == nil)
    #expect(CloudModelAvailability.checkDeadline <= .seconds(45))
  }

  @Test("First run with the vendor unreachable: every known model, not checked (D-2)")
  func firstRunUnreachableIsNotChecked() async {
    let client = FakeListingClient(.openAI) { throw URLError(.notConnectedToInternet) }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    let snapshot = await harness.service.refresh(.openAI)
    #expect(snapshot.status == .unreachable)
    #expect(snapshot.isChecked == false)
    #expect(snapshot.checkedAt == .distantPast)
    #expect(snapshot.modelIDs == Set(CloudProvider.openAI.models.map(\.id)))
    #expect(snapshot.keyFingerprint != nil)
    for model in CloudProvider.openAI.models {
      #expect(snapshot.isModelAvailable(model.id, now: harness.clock.now))
    }
    // Kept in memory only, so a relaunch doesn't treat it as a real result.
    #expect(harness.store.read(.openAI) == nil)
    #expect(await harness.service.snapshot(for: .openAI) == snapshot)
  }

  @Test("A rejected key gives .keyRejected with its reason and no models")
  func keyRejectedHasNoModels() async {
    let client = FakeListingClient(.openAI) {
      throw CloudEngineError.keyRejected(provider: .openAI, reason: .expired)
    }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    let snapshot = await harness.service.refresh(.openAI)
    #expect(snapshot.status == .keyRejected(reason: .expired))
    #expect(snapshot.modelIDs.isEmpty)
    #expect(snapshot.isChecked)
    #expect(harness.store.read(.openAI)?.status == .keyRejected(reason: .expired))

    // Fresh for 24 hours like any other answer from the vendor.
    await harness.service.refresh(.openAI)
    #expect(client.requests == 1)
    #expect(await harness.service.availableModels().isEmpty)
  }

  @Test("A vendor that can't list models confirms every known model as .unsupported")
  func keyVerifiedOnlyIsUnsupported() async {
    let client = FakeListingClient(.blackForestLabs) { .keyVerifiedOnly }
    let harness = Harness(
      keys: [.blackForestLabs: "bfl-test-key-not-real"], clients: [.blackForestLabs: client])
    defer { harness.cleanUp() }

    let snapshot = await harness.service.refresh(.blackForestLabs)
    #expect(snapshot.status == .unsupported)
    #expect(snapshot.modelIDs == Set(CloudProvider.blackForestLabs.models.map(\.id)))
  }

  // MARK: Single-flight (R-21)

  @Test("Two concurrent refreshes for one provider make exactly one request")
  func concurrentRefreshesShareOneRequest() async {
    let gate = Gate()
    let (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
    let client = FakeListingClient(.openAI) {
      enteredContinuation.yield()
      await gate.wait()
      return fullListing(.openAI)
    }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }
    let service = harness.service

    // `force` on both, so without single-flight the second would make its own request.
    let first = Task { await service.refresh(.openAI, force: true) }
    var enteredIterator = entered.makeAsyncIterator()
    _ = await enteredIterator.next()  // the first check is waiting on the gate

    let second = Task { await service.refresh(.openAI, force: true) }
    while await service.joinedCount[.openAI, default: 0] < 1 {
      await Task.yield()
    }
    await gate.open()

    let (a, b) = (await first.value, await second.value)
    #expect(client.requests == 1)
    #expect(a == b)
    #expect(a.status == .available)
  }

  @Test("A check for one provider doesn't hold up another")
  func providersRunIndependently() async {
    let gate = Gate()
    let (entered, enteredContinuation) = AsyncStream.makeStream(of: Void.self)
    let openAI = FakeListingClient(.openAI) {
      enteredContinuation.yield()
      await gate.wait()
      return fullListing(.openAI)
    }
    let google = FakeListingClient(.google) { fullListing(.google) }
    let harness = Harness(
      keys: [.openAI: "openai-test-key-not-real", .google: "google-test-key-not-real"],
      clients: [.openAI: openAI, .google: google])
    defer { harness.cleanUp() }
    let service = harness.service

    let blocked = Task { await service.refresh(.openAI) }
    var enteredIterator = entered.makeAsyncIterator()
    _ = await enteredIterator.next()

    // Completes while OpenAI's check is still parked on the gate.
    #expect(await service.refresh(.google).status == .available)
    #expect(google.requests == 1)

    await gate.open()
    #expect(await blocked.value.status == .available)
    #expect(openAI.requests == 1)
  }

  // MARK: Updates and queries

  @Test("updates yields each new snapshot to every subscriber")
  func updatesYieldAfterRefresh() async {
    let client = FakeListingClient(.openAI) { fullListing(.openAI) }
    let harness = Harness(clients: [.openAI: client])
    defer { harness.cleanUp() }

    let one = harness.service.updates
    let two = harness.service.updates
    let snapshot = await harness.service.refresh(.openAI)

    var oneIterator = one.makeAsyncIterator()
    var twoIterator = two.makeAsyncIterator()
    #expect(await oneIterator.next() == snapshot)
    #expect(await twoIterator.next() == snapshot)
  }

  @Test("availableModels keeps catalog order and filters by each provider's snapshot")
  func availableModelsFiltersInCatalogOrder() async {
    let openAIKept = [CloudProvider.openAI.models[2], CloudProvider.openAI.models[0]]
    let openAI = FakeListingClient(.openAI) {
      CloudVendorListing(modelIDs: Set(openAIKept.map(\.vendorModelID)))
    }
    let stability = FakeListingClient(.stabilityAI) { .keyVerifiedOnly }
    // Google and BFL have no key, so they are never asked.
    let harness = Harness(
      keys: [.openAI: "openai-test-key-not-real", .stabilityAI: "stability-test-key-not-real"],
      clients: [.openAI: openAI, .stabilityAI: stability])
    defer { harness.cleanUp() }

    let models = await harness.service.availableModels()
    let expected =
      [CloudProvider.openAI.models[0], CloudProvider.openAI.models[2]]
      + CloudProvider.stabilityAI.models
    #expect(models.map(\.id) == expected.map(\.id))
    #expect(openAI.requests == 1)
    #expect(stability.requests == 1)

    #expect(await harness.service.isAvailable(CloudProvider.openAI.models[0].id))
    #expect(await harness.service.isAvailable(CloudProvider.openAI.models[1].id) == false)
    #expect(await harness.service.isAvailable("not-a-cloud-model") == false)
    #expect(openAI.requests == 1)
  }

  @Test("VinetasClient exposes the availability service it was given")
  func clientExposesService() {
    let service = CloudModelAvailability(
      keyStore: InMemoryAPIKeyStore(), storeDirectory: tempDirectory())
    let client = VinetasClient(router: EngineRouter(engines: []), cloudAvailability: service)
    #expect(client.cloudAvailability === service)
  }
}

// MARK: - Through the real adapter

private final class AvailabilityStubURLProtocol: URLProtocol, @unchecked Sendable {

  nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?
  nonisolated(unsafe) static var requests: [URLRequest] = []

  static func reset() {
    handler = nil
    requests = []
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [AvailabilityStubURLProtocol.self]
    return URLSession(configuration: config)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.requests.append(request)
    guard let handler = Self.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
      return
    }
    let (response, data) = handler(request)
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@Suite("Cloud model availability through the OpenAI adapter", .serialized)
struct CloudModelAvailabilityAdapterTests {

  @Test("One GET /v1/models, mapped to our IDs, then the fresh cache answers")
  func openAIListingThroughService() async {
    defer { AvailabilityStubURLProtocol.reset() }
    let kept = CloudProvider.openAI.models[0]
    AvailabilityStubURLProtocol.handler = { request in
      (
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
        Data(#"{"object":"list","data":[{"id":"\#(kept.vendorModelID)"}]}"#.utf8)
      )
    }
    let directory = tempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let service = CloudModelAvailability(
      keyStore: InMemoryAPIKeyStore(keys: [.openAI: "adapter-test-key-not-real"]),
      session: AvailabilityStubURLProtocol.makeSession(),
      storeDirectory: directory)

    let snapshot = await service.refresh(.openAI)
    #expect(snapshot.status == .available)
    #expect(snapshot.modelIDs == [kept.id])
    #expect(AvailabilityStubURLProtocol.requests.count == 1)
    #expect(AvailabilityStubURLProtocol.requests.first?.url?.path == "/v1/models")

    #expect(await service.isAvailable(kept.id))
    #expect(AvailabilityStubURLProtocol.requests.count == 1)

    // The key is never written to disk.
    let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    for name in files {
      let data = (try? Data(contentsOf: directory.appendingPathComponent(name))) ?? Data()
      #expect(data.range(of: Data("adapter-test-key-not-real".utf8)) == nil)
    }
  }
}

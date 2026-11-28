import Foundation
import os.lock

/// Which cloud models the configured API keys can use (requirements R-4, R-7,
/// R-8, R-19, R-21, decisions D-2 and D-3).
///
/// `VinetasClient` owns one, as ``VinetasClient/cloudAvailability``. It asks
/// each vendor which models a key can use, keeps one
/// ``CloudAvailabilitySnapshot`` per provider in memory and on disk, and
/// publishes every new snapshot on ``updates``. Nothing touches the network at
/// init.
///
/// **Cache rules.** A snapshot is fresh for ``freshness`` (24 hours, by
/// ``CloudAvailabilitySnapshot/checkedAt``). It is stale at once when the
/// current key's fingerprint differs from the snapshot's, or a key was added
/// or removed. An ``CloudAvailabilitySnapshot/Status/unreachable`` snapshot is
/// never fresh, but after a failed check the vendor is not asked again for
/// ``failureBackoff`` (5 minutes) unless `force` is set or the key changed, so
/// an outage doesn't turn every query into a request.
///
/// **Smart expiry** (R-7a). A snapshot is also stale when its
/// ``CloudAvailabilitySnapshot/catalogDigest`` differs from this build's (another
/// SwiftVinetas version wrote it), or its `checkedAt` is before
/// `CloudAvailabilityStore.minimumCheckedAt`. A snapshot read from disk with
/// another digest is re-mapped from its raw vendor IDs through this build's
/// model table, so until the re-check it shows the models this build knows.
///
/// **Bounded checks.** Checks use their own listing session
/// (``CloudHTTP/makeListingSession()``: no waiting for connectivity, 15 s per
/// request, 30 s per resource), and each check, retries and pages included, is
/// cut off after ``checkDeadline`` (40 s) and treated as unreachable.
///
/// **No key** (R-19): the snapshot is ``CloudAvailabilitySnapshot/Status/noKey``
/// with no models, and no request is made.
///
/// **Failures** (R-8): a network failure, timeout, 5xx or any error other than
/// a rejected key keeps the last good snapshot for the same key: its models,
/// shutdown dates and original `checkedAt`, with status `.unreachable`. A
/// rejected key gives ``CloudAvailabilitySnapshot/Status/keyRejected(reason:)``
/// with no models. With no earlier snapshot for this key, every known model of
/// the provider counts as available, *not checked* (D-2): status
/// `.unreachable`, `checkedAt == .distantPast`, and
/// ``CloudAvailabilitySnapshot/isChecked`` `false`. A not-checked snapshot is
/// kept in memory only, never written to disk.
///
/// **One check per vendor** (R-21): concurrent ``refresh(_:force:)`` calls for
/// one provider await the same check; different providers run independently.
///
/// The API key is read through the key store for each check, sent only to its
/// vendor, and never stored or logged; snapshots carry only a salted
/// fingerprint of it.
public actor CloudModelAvailability {

  /// How long a successful check stays fresh (D-3).
  public static let freshness: TimeInterval = 24 * 60 * 60

  /// How long after a failed check the vendor is left alone, unless `force`
  /// is set or the key changed.
  public static let failureBackoff: TimeInterval = 5 * 60

  /// The most time one check may take, retries and pages included.
  public static let checkDeadline: Duration = .seconds(40)

  /// Where API keys resolve from.
  public nonisolated let keyStore: any CloudAPIKeyStoring

  private let session: URLSession
  private let makeStore: @Sendable () -> CloudAvailabilityStore
  private var resolvedStore: CloudAvailabilityStore?
  private let clientFor: @Sendable (CloudProvider) -> any CloudProviderClient
  private let now: @Sendable () -> Date
  private let deadline: Duration
  private let broadcaster = AvailabilityBroadcaster()

  private var snapshots: [CloudProvider: CloudAvailabilitySnapshot] = [:]
  private var readFromDisk: Set<CloudProvider> = []

  /// When the last check failed, per provider, and for which key.
  private var lastFailure: [CloudProvider: (at: Date, keyFingerprint: String?)] = [:]

  private struct InFlight {
    let task: Task<CloudAvailabilitySnapshot, Never>
    let keyFingerprint: String?
  }
  private var inFlight: [CloudProvider: InFlight] = [:]

  /// Per provider, how many generation-time invalidations (R-10) have been
  /// applied. A check records it when it starts and discards its result if it
  /// changed, so a listing that began before an invalidation can't overwrite it.
  private var invalidations: [CloudProvider: Int] = [:]

  /// Providers whose last check was discarded for the reason above. Their
  /// cache is stale, so the next trigger checks again.
  private var needsRecheck: Set<CloudProvider> = []

  /// How many callers joined a check already running, per provider. Tests
  /// read it to know a second caller is waiting before letting the first
  /// check finish.
  private(set) var joinedCount: [CloudProvider: Int] = [:]

  /// Creates the service.
  ///
  /// - Parameters:
  ///   - keyStore: Where API keys resolve from; the same store the cloud
  ///     engines use.
  ///   - session: The `URLSession` for the vendor checks; `nil` builds
  ///     ``CloudHTTP/makeListingSession()``. Don't pass the engines' generation
  ///     session: it waits for connectivity, so an offline check would hang.
  ///   - storeDirectory: Where snapshots are kept; `nil` uses the App Group
  ///     container, else Caches (resolved on first use, not here).
  public init(
    keyStore: any CloudAPIKeyStoring = ChainedAPIKeyStore.default,
    session: URLSession? = nil,
    storeDirectory: URL? = nil
  ) {
    self.init(
      keyStore: keyStore,
      session: session,
      store: storeDirectory.map { CloudAvailabilityStore(directory: $0) },
      client: CloudImageEngine.defaultClient(for:),
      now: { Date() })
  }

  init(
    keyStore: any CloudAPIKeyStoring,
    session: URLSession?,
    store: CloudAvailabilityStore?,
    client: @escaping @Sendable (CloudProvider) -> any CloudProviderClient,
    now: @escaping @Sendable () -> Date,
    deadline: Duration = CloudModelAvailability.checkDeadline
  ) {
    self.keyStore = keyStore
    self.session = session ?? CloudHTTP.makeListingSession()
    self.deadline = deadline
    if let store {
      self.makeStore = { store }
    } else {
      self.makeStore = { CloudAvailabilityStore() }
    }
    self.clientFor = client
    self.now = now
  }

  // MARK: - Public API

  /// A new stream of every snapshot this service produces from now on: each
  /// completed check, and each change to `.noKey`. Every access returns its
  /// own stream, so several subscribers each get every update. A stream ends
  /// when its task is cancelled or the service is released.
  public nonisolated var updates: AsyncStream<CloudAvailabilitySnapshot> {
    broadcaster.subscribe()
  }

  /// The cached snapshot for `provider` (memory, then disk), without a
  /// network call. `nil` when there has never been one.
  public func snapshot(for provider: CloudProvider) -> CloudAvailabilitySnapshot? {
    cached(provider)
  }

  /// Checks `provider` when the cache is missing or stale, or when `force` is
  /// set, and returns the result. A fresh cache is returned without a request;
  /// with no key the result is `.noKey` without a request. Within
  /// ``failureBackoff`` of a failed check for the same key, the cached result
  /// is returned without a request unless `force` is set. A call made while a
  /// check for the same provider and key is running waits for that check, even
  /// with `force`. A check takes at most ``checkDeadline``.
  @discardableResult
  public func refresh(_ provider: CloudProvider, force: Bool = false) async
    -> CloudAvailabilitySnapshot
  {
    // Everything up to registering the task is synchronous, so two callers
    // can't both start a check (actor reentrancy only happens at an await).
    let key = keyStore.apiKey(for: provider)
    let fingerprint = key.flatMap { try? store.fingerprint(apiKey: $0) }

    if let running = inFlight[provider] {
      if running.keyFingerprint == fingerprint, key != nil {
        joinedCount[provider, default: 0] += 1
        return await running.task.value
      }
      // The key changed under a running check: let it finish (one request per
      // vendor at a time), then check again for the current key.
      _ = await running.task.value
      return await refresh(provider, force: force)
    }

    let previous = cached(provider)
    guard let key else {
      if let previous, previous.status == .noKey { return previous }
      let snapshot = CloudAvailabilitySnapshot(
        provider: provider, status: .noKey, checkedAt: now())
      save(snapshot, persist: true)
      return snapshot
    }
    if !force, let previous, isFresh(previous, keyFingerprint: fingerprint) {
      return previous
    }
    if !force, let previous, let failure = lastFailure[provider],
      failure.keyFingerprint == fingerprint
    {
      let since = now().timeIntervalSince(failure.at)
      if since >= 0, since < Self.failureBackoff { return previous }
    }

    let generation = invalidations[provider, default: 0]
    let task = Task {
      await self.check(
        provider, apiKey: key, keyFingerprint: fingerprint, invalidationCount: generation)
    }
    inFlight[provider] = InFlight(task: task, keyFingerprint: fingerprint)
    return await task.value
  }

  /// The available cloud models of every provider, in ``CloudModelDescriptor/all``
  /// order. Each provider is refreshed first, respecting the cache, so this
  /// makes a request only for a provider whose cache is missing or stale, and
  /// then may wait up to ``checkDeadline``. UIs should draw from
  /// ``snapshot(for:)`` and ``updates`` instead of awaiting this.
  public func availableModels() async -> [CloudModelDescriptor] {
    var byProvider: [CloudProvider: CloudAvailabilitySnapshot] = [:]
    await withTaskGroup(of: CloudAvailabilitySnapshot.self) { group in
      for provider in CloudProvider.allCases {
        group.addTask { await self.refresh(provider) }
      }
      for await snapshot in group {
        byProvider[snapshot.provider] = snapshot
      }
    }
    let date = now()
    return CloudModelDescriptor.all.filter {
      byProvider[$0.provider]?.isModelAvailable($0.id, now: date) ?? false
    }
  }

  /// Whether the cloud model with Vinetas ID `modelID` is available, after
  /// refreshing its provider (respecting the cache). `false` for an ID that
  /// is not a known cloud model. When the cache is missing or stale this makes
  /// a request and may wait up to ``checkDeadline``; UIs should draw from
  /// ``snapshot(for:)`` and ``updates`` instead.
  public func isAvailable(_ modelID: String) async -> Bool {
    guard let model = CloudModelDescriptor.all.first(where: { $0.id == modelID }) else {
      return false
    }
    let snapshot = await refresh(model.provider)
    return snapshot.isModelAvailable(modelID, now: now())
  }

  // MARK: - Generation-time invalidation (R-10)

  /// Applies a failure a generation reported, so the picker stops offering a
  /// model that is gone without waiting for the next check. Only
  /// ``CloudEngineError/modelUnavailable(provider:modelID:reason:)`` and
  /// ``CloudEngineError/keyRejected(provider:reason:)`` have an effect.
  /// ``VinetasClient`` wires this to its cloud engines.
  func handle(_ error: CloudEngineError) {
    switch error {
    case .modelUnavailable(let provider, let modelID, _):
      markUnavailable(provider: provider, modelID: modelID)
    case .keyRejected(let provider, let reason):
      markKeyRejected(provider: provider, reason: reason)
    default:
      break
    }
  }

  /// Removes the model with Vinetas ID `modelID` from `provider`'s snapshot,
  /// keeping its status and `checkedAt`, persists it and publishes one update.
  /// Does nothing when the snapshot already lacks the model, or says no
  /// models are usable (`.noKey`, `.keyRejected`).
  ///
  /// With no snapshot yet for the provider, one is made from the D-2
  /// baseline (every known model, not checked) minus this model; like any
  /// not-checked snapshot it stays in memory only.
  func markUnavailable(provider: CloudProvider, modelID: String) {
    invalidations[provider, default: 0] += 1
    var snapshot =
      cached(provider)
      ?? .notChecked(provider: provider, keyFingerprint: currentFingerprint(provider))
    switch snapshot.status {
    case .noKey, .keyRejected: return
    case .available, .unreachable, .unsupported: break
    }
    guard snapshot.modelIDs.contains(modelID) else { return }
    snapshot.modelIDs.remove(modelID)
    // Drop its raw vendor IDs too, so a re-map (R-7a) doesn't bring it back.
    if let model = provider.models.first(where: { $0.id == modelID }) {
      snapshot.vendorModelIDs = snapshot.vendorModelIDs.filter { !model.matches(vendorID: $0) }
    }
    save(snapshot, persist: snapshot.isChecked)
  }

  /// Marks `provider`'s snapshot ``CloudAvailabilitySnapshot/Status/keyRejected(reason:)``
  /// with no models for the current key, persists it and publishes one update.
  /// Does nothing when it already says so for this key.
  func markKeyRejected(provider: CloudProvider, reason: CloudEngineError.KeyRejectionReason) {
    invalidations[provider, default: 0] += 1
    let fingerprint = currentFingerprint(provider)
    if let existing = cached(provider), existing.status == .keyRejected(reason: reason),
      existing.keyFingerprint == fingerprint
    {
      return
    }
    let snapshot = CloudAvailabilitySnapshot(
      provider: provider, status: .keyRejected(reason: reason), checkedAt: now(),
      keyFingerprint: fingerprint)
    save(snapshot, persist: true)
  }

  private func currentFingerprint(_ provider: CloudProvider) -> String? {
    keyStore.apiKey(for: provider).flatMap { try? store.fingerprint(apiKey: $0) }
  }

  // MARK: - Check

  private func check(
    _ provider: CloudProvider, apiKey: String, keyFingerprint: String?,
    invalidationCount: Int
  ) async -> CloudAvailabilitySnapshot {
    let result: CloudAvailabilitySnapshot
    let client = clientFor(provider)
    let session = session
    do {
      let listing = try await Self.withDeadline(deadline, provider: provider) {
        try await client.listAvailableModels(apiKey: apiKey, session: session)
      }
      let mapped = CloudAvailabilitySnapshot.mapping(of: listing, provider: provider)
      result = CloudAvailabilitySnapshot(
        provider: provider,
        status: listing.vendorListsModels ? .available : .unsupported,
        modelIDs: mapped.modelIDs,
        checkedAt: now(),
        keyFingerprint: keyFingerprint,
        shutdownDates: mapped.shutdownDates,
        vendorModelIDs: listing.modelIDs ?? [],
        vendorListsModels: listing.vendorListsModels,
        vendorShutdownDates: listing.shutdownDates)
    } catch CloudEngineError.keyRejected(_, let reason) {
      result = CloudAvailabilitySnapshot(
        provider: provider, status: .keyRejected(reason: reason), checkedAt: now(),
        keyFingerprint: keyFingerprint)
    } catch {
      // Read the cache now, not when the check started, so a change made
      // meanwhile is not lost.
      result = Self.unreachable(
        provider: provider, previous: cached(provider), keyFingerprint: keyFingerprint)
    }
    if invalidations[provider, default: 0] != invalidationCount {
      // A generation reported a failure while this listing ran. Its answer may
      // predate that failure, so keep what the invalidation wrote and check
      // again on the next trigger.
      needsRecheck.insert(provider)
      inFlight[provider] = nil
      return cached(provider) ?? result
    }
    needsRecheck.remove(provider)
    if result.status == .unreachable {
      lastFailure[provider] = (now(), keyFingerprint)
    } else {
      lastFailure[provider] = nil
    }
    inFlight[provider] = nil
    save(result, persist: result.isChecked)
    return result
  }

  /// Runs `operation`, throwing ``CloudEngineError/timedOut(provider:)`` and
  /// cancelling it if it hasn't finished within `deadline`.
  static func withDeadline<T: Sendable>(
    _ deadline: Duration, provider: CloudProvider,
    _ operation: @escaping @Sendable () async throws -> T
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask { try await operation() }
      group.addTask {
        try await Task.sleep(for: deadline)
        throw CloudEngineError.timedOut(provider: provider)
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else { throw CancellationError() }
      return first
    }
  }

  /// The R-8 / D-2 result of a failed check.
  static func unreachable(
    provider: CloudProvider, previous: CloudAvailabilitySnapshot?, keyFingerprint: String?
  ) -> CloudAvailabilitySnapshot {
    if let previous, previous.isChecked, previous.keyFingerprint == keyFingerprint {
      switch previous.status {
      case .available, .unsupported, .unreachable:
        var kept = previous
        kept.status = .unreachable
        return kept
      case .keyRejected:
        // The vendor already rejected this key; a failed retry changes nothing.
        return previous
      case .noKey:
        break
      }
    }
    return .notChecked(provider: provider, keyFingerprint: keyFingerprint)
  }

  // MARK: - Cache

  private var store: CloudAvailabilityStore {
    if let resolvedStore { return resolvedStore }
    let made = makeStore()
    resolvedStore = made
    return made
  }

  private func cached(_ provider: CloudProvider) -> CloudAvailabilitySnapshot? {
    if let snapshot = snapshots[provider] { return snapshot }
    guard !readFromDisk.contains(provider) else { return nil }
    readFromDisk.insert(provider)
    let snapshot = store.read(provider)?.remappedForCurrentCatalog()
      .enforcingRejectedKeyHasNoModels()
    snapshots[provider] = snapshot
    return snapshot
  }

  private func isFresh(_ snapshot: CloudAvailabilitySnapshot, keyFingerprint: String?) -> Bool {
    guard !needsRecheck.contains(snapshot.provider), snapshot.isChecked, let keyFingerprint,
      snapshot.keyFingerprint == keyFingerprint
    else { return false }
    switch snapshot.status {
    case .noKey, .unreachable: return false
    case .available, .unsupported, .keyRejected: break
    }
    // R-7a: written by a build with another model table, or before the
    // release's forced-expiry date.
    guard snapshot.catalogDigest == CloudAvailabilitySnapshot.catalogDigest(for: snapshot.provider),
      snapshot.checkedAt >= store.minimumCheckedAt
    else { return false }
    let age = now().timeIntervalSince(snapshot.checkedAt)
    // A `checkedAt` in the future (the clock moved back) counts as stale.
    return age >= 0 && age < Self.freshness
  }

  private func save(_ snapshot: CloudAvailabilitySnapshot, persist: Bool) {
    let snapshot = snapshot.enforcingRejectedKeyHasNoModels()
    snapshots[snapshot.provider] = snapshot
    readFromDisk.insert(snapshot.provider)
    if persist {
      try? store.write(snapshot)
    }
    broadcaster.yield(snapshot)
  }
}

// MARK: - Not checked (D-2)

extension CloudAvailabilitySnapshot {

  /// R-8a: a `.keyRejected` snapshot offers no models, whatever wrote it. Empties
  /// every model field so no re-map can bring models back.
  func enforcingRejectedKeyHasNoModels() -> CloudAvailabilitySnapshot {
    guard case .keyRejected = status else { return self }
    var copy = self
    copy.modelIDs = []
    copy.shutdownDates = [:]
    copy.vendorModelIDs = []
    copy.vendorShutdownDates = [:]
    return copy
  }

  /// Whether a vendor check produced this snapshot. `false` for the D-2
  /// fallback: no earlier snapshot and the vendor unreachable, so every known
  /// model counts as available but nothing was confirmed. Such a snapshot has
  /// status ``Status/unreachable`` and `checkedAt == .distantPast`.
  public var isChecked: Bool { checkedAt != .distantPast }

  /// The D-2 fallback for `provider`: every known model, not checked.
  static func notChecked(provider: CloudProvider, keyFingerprint: String?)
    -> CloudAvailabilitySnapshot
  {
    CloudAvailabilitySnapshot(
      provider: provider, status: .unreachable,
      modelIDs: Set(provider.models.map(\.id)), checkedAt: .distantPast,
      keyFingerprint: keyFingerprint)
  }
}

// MARK: - Broadcast

/// Fans each snapshot out to every live ``CloudModelAvailability/updates`` stream.
final class AvailabilityBroadcaster: Sendable {

  private let continuations = OSAllocatedUnfairLock<
    [UUID: AsyncStream<CloudAvailabilitySnapshot>.Continuation]
  >(initialState: [:])

  func subscribe() -> AsyncStream<CloudAvailabilitySnapshot> {
    let (stream, continuation) = AsyncStream.makeStream(of: CloudAvailabilitySnapshot.self)
    let id = UUID()
    continuations.withLock { $0[id] = continuation }
    continuation.onTermination = { [weak self] _ in
      _ = self?.continuations.withLock { $0.removeValue(forKey: id) }
    }
    return stream
  }

  func yield(_ snapshot: CloudAvailabilitySnapshot) {
    for continuation in continuations.withLock({ Array($0.values) }) {
      continuation.yield(snapshot)
    }
  }

  deinit {
    for continuation in continuations.withLock({ Array($0.values) }) {
      continuation.finish()
    }
  }
}

import Foundation
import Security

/// Supplies per-provider API keys to the cloud engines.
///
/// Keys are read at generation time by ``CloudImageEngine`` and at display
/// time by hosts (the app's settings screen, the CLI's `list`/`info`); both go
/// through the same store so the UI and the engines can never disagree about
/// whether a provider is configured.
///
/// Production resolution is a ``ChainedAPIKeyStore`` — environment variables
/// first, then the keychain (``ChainedAPIKeyStore/default``). Tests and
/// previews use ``InMemoryAPIKeyStore``.
///
/// Implementations must never write a key to disk in plaintext, and must
/// never include key material in an error, a log line, or ``keySource(for:)``.
public protocol CloudAPIKeyStoring: Sendable {

  /// The stored key for `provider`, or `nil` when none is set.
  func apiKey(for provider: CloudProvider) -> String?

  /// Stores (or replaces) the key for `provider`.
  func setAPIKey(_ key: String, for provider: CloudProvider) throws

  /// Removes the key for `provider`. A no-op when none is stored.
  func removeAPIKey(for provider: CloudProvider) throws

  /// A short, key-free description of where the key for `provider` resolved
  /// from ("environment (OPENAI_API_KEY)", "keychain"), or `nil` when no key
  /// is set. For diagnostics such as `vinetas list`.
  func keySource(for provider: CloudProvider) -> String?
}

extension CloudAPIKeyStoring {
  public func keySource(for provider: CloudProvider) -> String? {
    apiKey(for: provider) == nil ? nil : "configured"
  }
}

/// Errors raised by the key stores.
public enum CloudKeyStoreError: LocalizedError, Sendable, Equatable {
  /// A Security framework call failed with the given status.
  case keychain(OSStatus)
  /// The store cannot be written (environment variables, a chain with no
  /// writable member).
  case readOnly(String)

  public var errorDescription: String? {
    switch self {
    case .keychain(let status):
      let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
      return "Keychain error: \(detail)"
    case .readOnly(let store):
      return "The \(store) key store is read-only."
    }
  }
}

// MARK: - Keychain

/// Keychain-backed store. One generic-password item per provider under a
/// single service name.
///
/// With an ``accessGroup`` the items live in the **data-protection keychain**
/// (`kSecUseDataProtectionKeychain`), which is the only macOS keychain that
/// honours `kSecAttrAccessGroup`. That is what lets the sandboxed Vinetas app
/// and its bundled, separately-sandboxed `VinetasCLI` read the same item
/// without a user-facing keychain prompt: both binaries carry the group in
/// their `keychain-access-groups` entitlement. Without an access group the
/// store is the process's own partition (the pre-0.23 app behaviour, and the
/// right choice on iOS, which has no CLI).
///
/// A process that lacks the entitlement for the configured group simply
/// resolves no key (`errSecMissingEntitlement` is swallowed on read), so a
/// locally built, unsigned `vinetas` falls through to the environment
/// variable instead of failing.
public final class KeychainAPIKeyStore: CloudAPIKeyStoring {

  /// The keychain service every Vinetas key lives under.
  public static let defaultService = "io.intrusive-memory.Vinetas.cloudAPIKeys"

  /// The keychain access group shared by `Vinetas.app` and the `VinetasCLI`
  /// it bundles: the team identifier followed by the group name declared in
  /// both entitlements files.
  public static let vinetasSharedAccessGroup = "H3EJ6Y8VJ6.io.intrusive-memory.Vinetas.shared"

  /// The process-wide store the engines read by default: the shared app↔CLI
  /// group on macOS, the process's own partition on iOS.
  public static let shared: KeychainAPIKeyStore = {
    #if os(macOS)
      return KeychainAPIKeyStore(accessGroup: vinetasSharedAccessGroup)
    #else
      return KeychainAPIKeyStore()
    #endif
  }()

  /// The un-grouped partition the app used before the shared group existed.
  /// Source side of ``migrateKeys(from:to:providers:)``.
  public static let legacy = KeychainAPIKeyStore(accessGroup: nil)

  public let service: String
  public let accessGroup: String?

  public init(service: String = KeychainAPIKeyStore.defaultService, accessGroup: String? = nil) {
    self.service = service
    self.accessGroup = accessGroup
  }

  private func baseQuery(for provider: CloudProvider) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
    ]
    if let accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
      query[kSecUseDataProtectionKeychain as String] = true
    }
    return query
  }

  public func apiKey(for provider: CloudProvider) -> String? {
    var query = baseQuery(for: provider)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    let key = String(decoding: data, as: UTF8.self)
    return key.isEmpty ? nil : key
  }

  public func keySource(for provider: CloudProvider) -> String? {
    guard apiKey(for: provider) != nil else { return nil }
    return accessGroup == nil ? "keychain" : "shared keychain"
  }

  public func setAPIKey(_ key: String, for provider: CloudProvider) throws {
    let data = Data(key.utf8)
    let query = baseQuery(for: provider)
    let update: [String: Any] = [kSecValueData as String: data]

    let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if updateStatus == errSecSuccess { return }
    guard updateStatus == errSecItemNotFound else {
      throw CloudKeyStoreError.keychain(updateStatus)
    }

    var insert = query
    insert[kSecValueData as String] = data
    insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let addStatus = SecItemAdd(insert as CFDictionary, nil)
    guard addStatus == errSecSuccess else { throw CloudKeyStoreError.keychain(addStatus) }
  }

  public func removeAPIKey(for provider: CloudProvider) throws {
    let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CloudKeyStoreError.keychain(status)
    }
  }

  /// One-shot, idempotent key migration between two stores.
  ///
  /// For each provider: if `destination` has no key and `source` has one,
  /// the key is written to `destination` and then removed from `source`.
  /// Providers already present in `destination` are left alone (so a second
  /// run is a no-op), and a provider with no key anywhere is skipped.
  ///
  /// The app calls this once on first launch after adopting the shared
  /// access group: `migrateKeys(from: .legacy, to: .shared)`.
  ///
  /// - Returns: The providers whose key was moved.
  @discardableResult
  public static func migrateKeys(
    from source: any CloudAPIKeyStoring,
    to destination: any CloudAPIKeyStoring,
    providers: [CloudProvider] = CloudProvider.allCases
  ) throws -> [CloudProvider] {
    var migrated: [CloudProvider] = []
    for provider in providers {
      guard destination.apiKey(for: provider) == nil,
        let key = source.apiKey(for: provider)
      else { continue }
      try destination.setAPIKey(key, for: provider)
      try source.removeAPIKey(for: provider)
      migrated.append(provider)
    }
    return migrated
  }
}

// MARK: - Environment

/// Read-only store backed by environment variables
/// (``CloudProvider/environmentVariable`` and its aliases).
///
/// This is how agents, cron shells, and CI supply keys: no keychain, no GUI
/// session. There is deliberately no `--api-key` flag anywhere in the CLI — a
/// flag would land in shell history and `ps` output; an environment variable
/// scoped to one invocation (`env OPENAI_API_KEY=… vinetas generate …`) does
/// not.
public struct EnvironmentAPIKeyStore: CloudAPIKeyStoring {

  private let environment: [String: String]

  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.environment = environment
  }

  /// The variable the key for `provider` resolved from, or `nil`.
  public func resolvedVariable(for provider: CloudProvider) -> String? {
    for name in [provider.environmentVariable] + provider.environmentVariableAliases {
      if let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
      {
        return name
      }
    }
    return nil
  }

  public func apiKey(for provider: CloudProvider) -> String? {
    guard let name = resolvedVariable(for: provider) else { return nil }
    return environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public func keySource(for provider: CloudProvider) -> String? {
    resolvedVariable(for: provider).map { "environment (\($0))" }
  }

  public func setAPIKey(_ key: String, for provider: CloudProvider) throws {
    throw CloudKeyStoreError.readOnly("environment")
  }

  public func removeAPIKey(for provider: CloudProvider) throws {
    throw CloudKeyStoreError.readOnly("environment")
  }
}

// MARK: - Chain

/// Resolves a key from the first member store that has one.
///
/// Writes go to the first member that accepts them (read-only members throw
/// ``CloudKeyStoreError/readOnly(_:)`` and are skipped); removals are applied
/// to every writable member so a key cannot linger in a later store.
public struct ChainedAPIKeyStore: CloudAPIKeyStoring {

  public let stores: [any CloudAPIKeyStoring]

  public init(_ stores: [any CloudAPIKeyStoring]) {
    self.stores = stores
  }

  /// The production chain shared by the app and the CLI: environment
  /// variables first, then ``KeychainAPIKeyStore/shared``.
  public static var `default`: ChainedAPIKeyStore {
    ChainedAPIKeyStore([EnvironmentAPIKeyStore(), KeychainAPIKeyStore.shared])
  }

  public func apiKey(for provider: CloudProvider) -> String? {
    for store in stores {
      if let key = store.apiKey(for: provider) { return key }
    }
    return nil
  }

  public func keySource(for provider: CloudProvider) -> String? {
    for store in stores {
      if let source = store.keySource(for: provider) { return source }
    }
    return nil
  }

  public func setAPIKey(_ key: String, for provider: CloudProvider) throws {
    for store in stores {
      do {
        try store.setAPIKey(key, for: provider)
        return
      } catch CloudKeyStoreError.readOnly {
        continue
      }
    }
    throw CloudKeyStoreError.readOnly("chain")
  }

  public func removeAPIKey(for provider: CloudProvider) throws {
    var removedSomewhere = false
    for store in stores {
      do {
        try store.removeAPIKey(for: provider)
        removedSomewhere = true
      } catch CloudKeyStoreError.readOnly {
        continue
      }
    }
    if !removedSomewhere { throw CloudKeyStoreError.readOnly("chain") }
  }
}

// MARK: - In-memory

/// A lock-guarded dictionary store for tests, previews, and UI-test launches.
public final class InMemoryAPIKeyStore: CloudAPIKeyStoring, @unchecked Sendable {

  private let lock = NSLock()
  private var keys: [CloudProvider: String]

  public init(keys: [CloudProvider: String] = [:]) {
    self.keys = keys
  }

  public func apiKey(for provider: CloudProvider) -> String? {
    lock.withLock { keys[provider] }
  }

  public func keySource(for provider: CloudProvider) -> String? {
    apiKey(for: provider) == nil ? nil : "memory"
  }

  public func setAPIKey(_ key: String, for provider: CloudProvider) throws {
    lock.withLock { keys[provider] = key }
  }

  public func removeAPIKey(for provider: CloudProvider) throws {
    _ = lock.withLock { keys.removeValue(forKey: provider) }
  }
}

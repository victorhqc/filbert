import Foundation
import Security

/// Secure store for every provider's API key.
///
/// All secrets live in a **single** generic-password item — a JSON object
/// keyed by provider ID — rather than one item per provider. macOS scopes a
/// keychain-access prompt (and the "Always Allow" grant) to the *item* being
/// read, so one item per provider meant one prompt per provider on first run:
/// jarring for a fresh install, and worse under an unstable code signature
/// where the grant never sticks. Collapsing to one item means the app is
/// prompted **once** no matter how many providers are configured. Signing the
/// app later drops that single prompt to zero on release builds.
///
/// The public API is still per-provider (`save`/`load`/`delete` by provider
/// ID); only the on-disk layout changed. A decoded copy is cached in memory so
/// the several reads per launch (`isConfigured`, `fetchAll`, `applyResults`,
/// the 5-minute auto-refresh) touch the keychain only once per session.
public final class Keychain: @unchecked Sendable {
    public static let shared = Keychain()

    private let service = "ai-usage"
    /// Account under which the consolidated JSON blob is stored.
    private let account = "providers"
    /// Prefix of the pre-consolidation per-provider accounts, read only during
    /// the one-time migration below.
    private let legacyAccountPrefix = "provider-"

    /// Decoded provider-ID → secret map. `nil` until the first keychain read;
    /// an empty dictionary is a valid loaded state (no keys saved yet).
    private var cache: [String: String]?
    /// Serializes every keychain touch. Held across the (potentially blocking)
    /// `SecItem` calls so concurrent readers in `ProviderRegistry.fetchAll`
    /// trigger at most one prompt — the first thread reads, the rest wait and
    /// then hit the cache. Not reentrant: only the public entry points lock;
    /// the private `…Store` helpers assume the lock is already held.
    private let lock = NSLock()

    private init() {}

    public func save(_ key: String, for providerId: String) throws {
        try mutateStore { $0[providerId] = key }
    }

    public func load(for providerId: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let key = try loadedStore()[providerId] else {
            throw KeychainError.loadFailed(errSecItemNotFound)
        }
        return key
    }

    public func delete(for providerId: String) throws {
        try mutateStore { $0.removeValue(forKey: providerId) }
    }

    // MARK: - Store access (all callers hold `lock`)

    /// Returns the cached store, loading it from the keychain — migrating any
    /// legacy per-provider items — on first use.
    private func loadedStore() throws -> [String: String] {
        if let cache {
            return cache
        }
        let store = try readStore()
        cache = store
        return store
    }

    /// Loads the store, applies `transform`, and writes it back atomically.
    private func mutateStore(_ transform: (inout [String: String]) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var store = try loadedStore()
        transform(&store)
        try writeStore(store)
        cache = store
    }

    private func readStore() throws -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let store = try? JSONDecoder().decode([String: String].self, from: data)
            else {
                throw KeychainError.loadFailed(errSecDecode)
            }
            return store
        case errSecItemNotFound:
            // No consolidated blob yet. Fold any legacy per-provider items into
            // one and persist it so this cost is paid at most once.
            let migrated = readLegacyItems()
            if !migrated.isEmpty {
                try writeStore(migrated)
                deleteLegacyItems(providerIds: Array(migrated.keys))
            }
            return migrated
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    private func writeStore(_ store: [String: String]) throws {
        let data = try JSONEncoder().encode(store)

        // Delete-then-add (rather than update) so the item is (re)created by the
        // running app, matching the original per-provider behavior.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)

        var addQuery = base
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - One-time migration from per-provider items

    /// Reads every legacy `provider-<id>` item for this service and returns
    /// them keyed by provider ID. Empty when there is nothing to migrate.
    private func readLegacyItems() -> [String: String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]]
        else {
            return [:]
        }

        var store: [String: String] = [:]
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  account.hasPrefix(legacyAccountPrefix),
                  let data = item[kSecValueData as String] as? Data,
                  let key = String(data: data, encoding: .utf8)
            else {
                continue
            }
            store[String(account.dropFirst(legacyAccountPrefix.count))] = key
        }
        return store
    }

    private func deleteLegacyItems(providerIds: [String]) {
        for providerId in providerIds {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "\(legacyAccountPrefix)\(providerId)",
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

public enum KeychainError: Error, Equatable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
}

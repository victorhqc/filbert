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
/// ID); only the on-disk layout changed. A decoded copy is cached in memory
/// so the several reads per launch (`isConfigured`, `fetchAll`,
/// `applyResults`, the 5-minute auto-refresh) touch the keychain only once
/// per session. Writes trust the Security framework status without a
/// read-back; `Keychain.lock` is the sole integrity guarantee against
/// concurrent in-process access.
public final class Keychain: @unchecked Sendable {
    public static let shared = Keychain()

    private let service: String
    private let storage: any KeychainStorage
    private let account = "providers"

    /// `nil` = not yet loaded; an empty dict is a valid loaded state.
    private var cache: [String: [String: String]]?
    /// Held across the (potentially blocking) `SecItem` calls so concurrent
    /// readers in `ProviderRegistry.fetchAll` trigger at most one prompt — the
    /// first thread reads, the rest wait and hit the cache. Not reentrant: only
    /// the public entry points lock; the private `…Store` helpers assume the
    /// lock is already held.
    private let lock = NSLock()

    private convenience init() {
        self.init(
            storage: SecurityKeychainStorage(),
            service: "filbert"
        )
    }

    init(
        storage: any KeychainStorage,
        service: String
    ) {
        self.storage = storage
        self.service = service
    }

    public func save(_ key: String, for providerId: String) throws {
        try mutateStore { store in
            var fields = store[providerId] ?? [:]
            fields["value"] = key
            store[providerId] = fields
        }
    }

    public func load(for providerId: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard let key = try loadedStore()[providerId]?["value"] else {
            throw KeychainError.loadFailed(errSecItemNotFound)
        }
        return key
    }

    /// Core does not interpret field names or values — it stores them opaquely.
    public func save(_ fields: [String: String], for providerId: String) throws {
        try mutateStore { $0[providerId] = fields }
    }

    public func loadFields(for providerId: String) throws -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        guard let fields = try loadedStore()[providerId] else {
            throw KeychainError.loadFailed(errSecItemNotFound)
        }
        return fields
    }

    public func delete(for providerId: String) throws {
        try mutateStore { $0.removeValue(forKey: providerId) }
    }
}

private extension Keychain {
    // MARK: - Store access (all callers hold `lock`)

    private func loadedStore() throws -> [String: [String: String]] {
        if let cache {
            return cache
        }
        let loaded = try readStore()
        cache = loaded
        return loaded
    }

    /// On write failure the in-memory cache is left at its pre-write state.
    private func mutateStore(_ transform: (inout [String: [String: String]]) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var store = try loadedStore()
        transform(&store)
        let data = try JSONEncoder().encode(store)
        do {
            try storage.replaceData(
                data,
                service: service,
                account: account,
                authenticationContext: .shared
            )
        } catch let error as KeychainStorageError {
            throw KeychainError.saveFailed(error.status)
        }
        cache = store
    }

    private func readStore() throws -> [String: [String: String]] {
        do {
            guard let data = try storage.readData(
                service: service,
                account: account,
                authenticationContext: .shared
            ) else {
                return [:]
            }
            return try decodeStore(data)
        } catch let error as KeychainStorageError {
            throw KeychainError.loadFailed(error.status)
        }
    }

    private func decodeStore(_ data: Data) throws -> [String: [String: String]] {
        do {
            return try JSONDecoder().decode([String: [String: String]].self, from: data)
        } catch {
            throw KeychainError.loadFailed(errSecDecode)
        }
    }
}

public enum KeychainError: Error, Equatable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
}

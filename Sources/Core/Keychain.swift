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
/// concurrent in-process access (core 07 AC2).
public final class Keychain: @unchecked Sendable {
    public static let shared = Keychain()

    private let service: String
    private let storage: any KeychainStorage
    /// Account under which the consolidated JSON blob is stored.
    private let account = "providers"

    /// Decoded provider-ID → provider-owned secret-field map. `nil` until the
    /// first keychain read; an empty dictionary is a valid loaded state.
    private var cache: [String: [String: String]]?
    /// Serializes every keychain touch. Held across the (potentially blocking)
    /// `SecItem` calls so concurrent readers in `ProviderRegistry.fetchAll`
    /// trigger at most one prompt — the first thread reads, the rest wait and
    /// then hit the cache. Not reentrant: only the public entry points lock;
    /// the private `…Store` helpers assume the lock is already held.
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

    /// Stores provider-owned string fields while preserving every other
    /// provider's field map. Core does not interpret field names or values.
    public func save(_ fields: [String: String], for providerId: String) throws {
        try mutateStore { $0[providerId] = fields }
    }

    /// Loads a provider-owned field map without assigning meaning to its
    /// fields. Missing maps use the same not-found error as API-key loads.
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

    /// Returns the cached store, loading it from the keychain on first use.
    private func loadedStore() throws -> [String: [String: String]] {
        if let cache {
            return cache
        }
        let loaded = try readStore()
        cache = loaded
        return loaded
    }

    /// Loads the store, applies `transform`, and writes it back. The write
    /// trusts the Security framework status; on failure the in-memory cache
    /// is left at its pre-write state (core 07 AC2).
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

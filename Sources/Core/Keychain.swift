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

    private let service: String
    private let previousService: String?
    private let storage: any KeychainStorage
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

    private convenience init() {
        self.init(
            storage: SecurityKeychainStorage(),
            service: "filbert",
            previousService: LegacyBrandIdentifiers.keychainService
        )
    }

    init(
        storage: any KeychainStorage,
        service: String,
        previousService: String?
    ) {
        self.storage = storage
        self.service = service
        self.previousService = previousService
    }

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
        do {
            if let data = try storage.readData(service: service, account: account) {
                return try decodeStore(data, error: .loadFailed(errSecDecode))
            }
        } catch let error as KeychainStorageError {
            throw KeychainError.loadFailed(error.status)
        }

        return try migrateStore()
    }

    private func writeStore(_ store: [String: String]) throws {
        let data = try JSONEncoder().encode(store)
        do {
            try storage.replaceData(data, service: service, account: account)
        } catch let error as KeychainStorageError {
            throw KeychainError.saveFailed(error.status)
        }
    }

    // swiftlint:disable:next function_body_length
    private func migrateStore() throws -> [String: String] {
        var migrated: [String: String] = [:]
        var itemsToDelete: [(service: String, account: String)] = []

        if let previousService {
            let previousItems = try migrationItems(service: previousService)
            migrated.merge(previousItems.store) { _, latest in latest }
            itemsToDelete.append(contentsOf: previousItems.accounts.map {
                (previousService, $0)
            })

            do {
                if let data = try storage.readData(service: previousService, account: account) {
                    let consolidated = try decodeStore(
                        data,
                        error: .migrationFailed(errSecDecode)
                    )
                    migrated.merge(consolidated) { _, latest in latest }
                    itemsToDelete.append((previousService, account))
                }
            } catch let error as KeychainStorageError {
                throw KeychainError.migrationFailed(error.status)
            }
        }

        let currentItems = try migrationItems(service: service)
        migrated.merge(currentItems.store) { _, latest in latest }
        itemsToDelete.append(contentsOf: currentItems.accounts.map { (service, $0) })

        guard !migrated.isEmpty else {
            return [:]
        }

        do {
            let data = try JSONEncoder().encode(migrated)
            try storage.replaceData(data, service: service, account: account)
            guard let verificationData = try storage.readData(service: service, account: account)
            else {
                throw KeychainError.migrationFailed(errSecItemNotFound)
            }
            let verified = try decodeStore(
                verificationData,
                error: .migrationFailed(errSecDecode)
            )
            guard verified == migrated else {
                throw KeychainError.migrationFailed(errSecVerifyFailed)
            }
        } catch let error as KeychainError {
            storage.delete(service: service, account: account)
            throw error
        } catch let error as KeychainStorageError {
            storage.delete(service: service, account: account)
            throw KeychainError.migrationFailed(error.status)
        }

        for item in itemsToDelete {
            storage.delete(service: item.service, account: item.account)
        }
        return migrated
    }

    private func migrationItems(
        service: String
    ) throws -> (store: [String: String], accounts: [String]) {
        let items: [StoredKeychainItem]
        do {
            items = try storage.readItems(service: service)
        } catch let error as KeychainStorageError {
            throw KeychainError.migrationFailed(error.status)
        }

        var migrated: [String: String] = [:]
        var accounts: [String] = []
        for item in items where item.account.hasPrefix(legacyAccountPrefix) {
            guard let key = String(data: item.data, encoding: .utf8) else { continue }
            let providerId = String(item.account.dropFirst(legacyAccountPrefix.count))
            migrated[providerId] = key
            accounts.append(item.account)
        }
        return (migrated, accounts)
    }

    private func decodeStore(
        _ data: Data,
        error: KeychainError
    ) throws -> [String: String] {
        guard let store = try? JSONDecoder().decode([String: String].self, from: data) else {
            throw error
        }
        return store
    }
}

public enum KeychainError: Error, Equatable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case migrationFailed(OSStatus)
}

private extension KeychainStorageError {
    var status: OSStatus {
        switch self {
        case let .status(status):
            status
        }
    }
}

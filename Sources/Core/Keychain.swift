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

    /// Decoded provider-ID → provider-owned secret-field map. `nil` until the
    /// first keychain read; an empty dictionary is a valid loaded state.
    private var cache: [String: [String: String]]?
    /// Exact bytes read from the consolidated item. Retained only so a failed
    /// write verification can restore the previous item before reporting the
    /// failure.
    private var cachedData: Data?
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

    // MARK: - Store access (all callers hold `lock`)

    /// Returns the cached store, loading it from the keychain — migrating any
    /// legacy per-provider items — on first use.
    private func loadedStore() throws -> [String: [String: String]] {
        if let cache {
            return cache
        }
        let loaded = try readStore()
        cache = loaded.store
        cachedData = loaded.data
        return loaded.store
    }

    /// Loads the store, applies `transform`, and writes it back atomically.
    private func mutateStore(_ transform: (inout [String: [String: String]]) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        var store = try loadedStore()
        transform(&store)
        let data = try writeStore(store, previousData: cachedData)
        cache = store
        cachedData = data
    }

    private func readStore() throws -> LoadedStore {
        let current: ConsolidatedStore?
        do {
            if let data = try storage.readData(service: service, account: account) {
                current = try decodeStore(data, error: .loadFailed(errSecDecode))
            } else {
                current = nil
            }
        } catch let error as KeychainStorageError {
            throw KeychainError.loadFailed(error.status)
        }

        return try migrateStore(current: current)
    }

    private func writeStore(
        _ store: [String: [String: String]],
        previousData: Data?
    ) throws -> Data {
        let data = try JSONEncoder().encode(store)
        try replaceAndVerify(
            data,
            previousData: previousData,
            errorFactory: { .saveFailed($0) }
        )
        return data
    }

    private func migrateStore(current: ConsolidatedStore?) throws -> LoadedStore {
        var migrated: [String: [String: String]] = [:]
        var itemsToDelete: [(service: String, account: String)] = []
        var requiresWrite = current?.isLegacy ?? false

        if let previousService {
            let previousItems = try migrationItems(service: previousService)
            migrated.merge(previousItems.store) { _, latest in latest }
            itemsToDelete.append(contentsOf: previousItems.accounts.map {
                (previousService, $0)
            })
            requiresWrite = requiresWrite || !previousItems.accounts.isEmpty

            do {
                if let data = try storage.readData(service: previousService, account: account) {
                    let consolidated = try decodeStore(
                        data,
                        error: .migrationFailed(errSecDecode)
                    )
                    migrated.merge(consolidated.store) { _, latest in latest }
                    itemsToDelete.append((previousService, account))
                    requiresWrite = true
                }
            } catch let error as KeychainStorageError {
                throw KeychainError.migrationFailed(error.status)
            }
        }

        let currentItems = try migrationItems(service: service)
        migrated.merge(currentItems.store) { _, latest in latest }
        itemsToDelete.append(contentsOf: currentItems.accounts.map { (service, $0) })
        requiresWrite = requiresWrite || !currentItems.accounts.isEmpty

        if let current {
            migrated.merge(current.store) { _, latest in latest }
        }

        guard requiresWrite else {
            return LoadedStore(store: current?.store ?? [:], data: current?.data)
        }

        let data = try JSONEncoder().encode(migrated)
        try replaceAndVerify(
            data,
            previousData: current?.data,
            errorFactory: { .migrationFailed($0) }
        )
        for item in itemsToDelete {
            storage.delete(service: item.service, account: item.account)
        }
        return LoadedStore(store: migrated, data: data)
    }

    private func replaceAndVerify(
        _ data: Data,
        previousData: Data?,
        errorFactory: (OSStatus) -> KeychainError
    ) throws {
        var replaced = false
        do {
            try storage.replaceData(data, service: service, account: account)
            replaced = true
            guard let verified = try storage.readData(service: service, account: account),
                  verified == data
            else {
                throw KeychainError.saveFailed(errSecVerifyFailed)
            }
        } catch let storageError as KeychainStorageError {
            if replaced {
                restore(previousData)
            }
            throw errorFactory(storageError.status)
        } catch {
            if replaced {
                restore(previousData)
            }
            throw errorFactory(errSecVerifyFailed)
        }
    }

    private func restore(_ previousData: Data?) {
        if let previousData {
            try? storage.replaceData(previousData, service: service, account: account)
        } else {
            storage.delete(service: service, account: account)
        }
    }

    private func migrationItems(
        service: String
    ) throws -> (store: [String: [String: String]], accounts: [String]) {
        let items: [StoredKeychainItem]
        do {
            items = try storage.readItems(service: service)
        } catch let error as KeychainStorageError {
            throw KeychainError.migrationFailed(error.status)
        }

        var migrated: [String: [String: String]] = [:]
        var accounts: [String] = []
        for item in items where item.account.hasPrefix(legacyAccountPrefix) {
            guard let key = String(data: item.data, encoding: .utf8) else { continue }
            let providerId = String(item.account.dropFirst(legacyAccountPrefix.count))
            migrated[providerId] = ["value": key]
            accounts.append(item.account)
        }
        return (migrated, accounts)
    }

    private func decodeStore(
        _ data: Data,
        error: KeychainError
    ) throws -> ConsolidatedStore {
        if let store = try? JSONDecoder().decode([String: [String: String]].self, from: data) {
            return ConsolidatedStore(store: store, data: data, isLegacy: false)
        }
        if let legacyStore = try? JSONDecoder().decode([String: String].self, from: data) {
            let store = legacyStore.mapValues { ["value": $0] }
            return ConsolidatedStore(store: store, data: data, isLegacy: true)
        }
        throw error
    }
}

private struct ConsolidatedStore {
    let store: [String: [String: String]]
    let data: Data
    let isLegacy: Bool
}

private struct LoadedStore {
    let store: [String: [String: String]]
    let data: Data?
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

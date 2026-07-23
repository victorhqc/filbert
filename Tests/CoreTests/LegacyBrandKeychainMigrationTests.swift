@testable import Core
import Foundation
import Security
import XCTest

final class LegacyBrandKeychainMigrationTests: XCTestCase {
    private let currentService = "filbert"
    private let previousService = "ai-usage"

    func testLoadMigratesConsolidatedAndPerProviderSecretsThenDeletesOldItems() throws {
        let storage = InMemoryKeychainStorage()
        storage.items[previousService] = try [
            "providers": JSONEncoder().encode(["zai": "consolidated-key"]),
            "provider-deepseek": Data("deepseek-key".utf8),
        ]
        let keychain = makeKeychain(storage: storage)

        XCTAssertEqual(try keychain.load(for: "zai"), "consolidated-key")
        XCTAssertEqual(try keychain.load(for: "deepseek"), "deepseek-key")

        let migratedData = try XCTUnwrap(storage.items[currentService]?["providers"])
        let migrated = try JSONDecoder().decode([String: [String: String]].self, from: migratedData)
        XCTAssertEqual(
            migrated,
            [
                "zai": ["value": "consolidated-key"],
                "deepseek": ["value": "deepseek-key"],
            ]
        )
        XCTAssertNil(storage.items[previousService]?["providers"])
        XCTAssertNil(storage.items[previousService]?["provider-deepseek"])
    }

    func testLoadPrefersCurrentServicePerProviderItemDuringMigration() throws {
        let storage = InMemoryKeychainStorage()
        storage.items[previousService] = try [
            "providers": JSONEncoder().encode(["zai": "previous-key"]),
        ]
        storage.items[currentService] = [
            "provider-zai": Data("current-key".utf8),
        ]

        let keychain = makeKeychain(storage: storage)

        XCTAssertEqual(try keychain.load(for: "zai"), "current-key")
    }

    func testMigrationFailureLeavesPreviousItemsIntact() throws {
        let storage = InMemoryKeychainStorage()
        let previousData = try JSONEncoder().encode(["zai": "secret-key"])
        storage.items[previousService] = ["providers": previousData]
        storage.replaceError = errSecNotAvailable
        let keychain = makeKeychain(storage: storage)

        XCTAssertThrowsError(try keychain.load(for: "zai")) { error in
            XCTAssertEqual(error as? KeychainError, .migrationFailed(errSecNotAvailable))
        }
        XCTAssertEqual(storage.items[previousService]?["providers"], previousData)
        XCTAssertFalse(
            storage.deletedItems.contains {
                $0.service == previousService && $0.account == "providers"
            }
        )
    }

    func testVerificationFailureLeavesPreviousItemsIntact() throws {
        let storage = InMemoryKeychainStorage()
        let previousData = try JSONEncoder().encode(["zai": "secret-key"])
        storage.items[previousService] = ["providers": previousData]
        storage.corruptNextReplacement = true
        let keychain = makeKeychain(storage: storage)

        XCTAssertThrowsError(try keychain.load(for: "zai")) { error in
            guard case .migrationFailed = error as? KeychainError else {
                XCTFail("Expected migrationFailed, got \(error)")
                return
            }
        }
        XCTAssertEqual(storage.items[previousService]?["providers"], previousData)
        XCTAssertFalse(
            storage.deletedItems.contains {
                $0.service == previousService && $0.account == "providers"
            }
        )
    }

    func testLoadConvertsCurrentServiceLegacyPayloadWithoutChangingAPIKeyLoads() throws {
        let storage = InMemoryKeychainStorage()
        storage.items[currentService] = try [
            "providers": JSONEncoder().encode(["zai": "legacy-key"]),
        ]
        let keychain = makeKeychain(storage: storage)

        XCTAssertEqual(try keychain.load(for: "zai"), "legacy-key")

        let migratedData = try XCTUnwrap(storage.items[currentService]?["providers"])
        XCTAssertEqual(
            try JSONDecoder().decode([String: [String: String]].self, from: migratedData),
            ["zai": ["value": "legacy-key"]]
        )
    }

    func testFieldMapsRoundTripAndPreserveOtherProviders() throws {
        let storage = InMemoryKeychainStorage()
        let zaiFields = ["value": "zai-key", "metadata": "keep"]
        storage.items[currentService] = try [
            "providers": JSONEncoder().encode(["zai": zaiFields]),
        ]
        let keychain = makeKeychain(storage: storage)

        try keychain.save(
            ["accessToken": "cursor-access", "refreshToken": "cursor-refresh"],
            for: "cursor"
        )

        XCTAssertEqual(try keychain.load(for: "zai"), "zai-key")
        XCTAssertEqual(
            try keychain.loadFields(for: "cursor"),
            ["accessToken": "cursor-access", "refreshToken": "cursor-refresh"]
        )
        let savedData = try XCTUnwrap(storage.items[currentService]?["providers"])
        let saved = try JSONDecoder().decode([String: [String: String]].self, from: savedData)
        XCTAssertEqual(saved["zai"], zaiFields)
        XCTAssertTrue(storage.deletedItems.isEmpty)
    }

    func testFailedUpdatePreservesCachedAndStoredFields() throws {
        let storage = InMemoryKeychainStorage()
        let original = ["zai": ["value": "zai-key"], "deepseek": ["value": "deepseek-key"]]
        let originalData = try JSONEncoder().encode(original)
        storage.items[currentService] = ["providers": originalData]
        let keychain = makeKeychain(storage: storage)

        XCTAssertEqual(try keychain.load(for: "zai"), "zai-key")
        storage.replaceError = errSecNotAvailable

        XCTAssertThrowsError(try keychain.save("new-key", for: "zai")) { error in
            XCTAssertEqual(error as? KeychainError, .saveFailed(errSecNotAvailable))
        }
        XCTAssertEqual(storage.items[currentService]?["providers"], originalData)
        XCTAssertEqual(try keychain.load(for: "zai"), "zai-key")
        XCTAssertEqual(try keychain.load(for: "deepseek"), "deepseek-key")
        XCTAssertTrue(storage.deletedItems.isEmpty)
    }

    func testCreateFailureDoesNotCreateConsolidatedItem() {
        let storage = InMemoryKeychainStorage()
        storage.createError = errSecNotAvailable
        let keychain = makeKeychain(storage: storage)

        XCTAssertThrowsError(try keychain.save("zai-key", for: "zai")) { error in
            XCTAssertEqual(error as? KeychainError, .saveFailed(errSecNotAvailable))
        }
        XCTAssertNil(storage.items[currentService]?["providers"])
        XCTAssertTrue(storage.deletedItems.isEmpty)
    }

    func testVerificationFailureRestoresExistingConsolidatedItem() throws {
        let storage = InMemoryKeychainStorage()
        let originalData = try JSONEncoder().encode(["zai": ["value": "zai-key"]])
        storage.items[currentService] = ["providers": originalData]
        let keychain = makeKeychain(storage: storage)

        XCTAssertEqual(try keychain.load(for: "zai"), "zai-key")
        storage.corruptNextReplacement = true

        XCTAssertThrowsError(try keychain.save("new-key", for: "zai")) { error in
            XCTAssertEqual(error as? KeychainError, .saveFailed(errSecVerifyFailed))
        }
        XCTAssertEqual(storage.items[currentService]?["providers"], originalData)
        XCTAssertEqual(try keychain.load(for: "zai"), "zai-key")
        XCTAssertTrue(storage.deletedItems.isEmpty)
    }

    private func makeKeychain(storage: InMemoryKeychainStorage) -> Keychain {
        Keychain(
            storage: storage,
            service: currentService,
            previousService: previousService
        )
    }
}

private final class InMemoryKeychainStorage: KeychainStorage, @unchecked Sendable {
    var items: [String: [String: Data]] = [:]
    var deletedItems: [(service: String, account: String)] = []
    var replaceError: OSStatus?
    var createError: OSStatus?
    var corruptNextReplacement = false

    func readData(service: String, account: String) throws -> Data? {
        items[service]?[account]
    }

    func readItems(service: String) throws -> [StoredKeychainItem] {
        (items[service] ?? [:]).map { account, data in
            StoredKeychainItem(account: account, data: data)
        }
    }

    func replaceData(_ data: Data, service: String, account: String) throws {
        if let replaceError {
            throw KeychainStorageError.status(replaceError)
        }
        if items[service]?[account] == nil, let createError {
            throw KeychainStorageError.status(createError)
        }
        let replacement = corruptNextReplacement ? Data("not-json".utf8) : data
        corruptNextReplacement = false
        items[service, default: [:]][account] = replacement
    }

    func delete(service: String, account: String) {
        items[service]?[account] = nil
        deletedItems.append((service, account))
    }
}

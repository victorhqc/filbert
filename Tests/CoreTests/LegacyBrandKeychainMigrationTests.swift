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
        let migrated = try JSONDecoder().decode([String: String].self, from: migratedData)
        XCTAssertEqual(
            migrated,
            ["zai": "consolidated-key", "deepseek": "deepseek-key"]
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
        storage.corruptReplacement = true
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
    var corruptReplacement = false

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
        items[service, default: [:]][account] = corruptReplacement
            ? Data("not-json".utf8)
            : data
    }

    func delete(service: String, account: String) {
        items[service]?[account] = nil
        deletedItems.append((service, account))
    }
}

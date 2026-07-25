@testable import Core
import Foundation
import Security
import XCTest

final class KeychainTests: XCTestCase {
    private let currentService = "filbert"

    func testKeychainError_casesExist() {
        // We can't test real Keychain I/O in CI, but the enum must compile.
        let errors: [KeychainError] = [
            .saveFailed(-1),
            .loadFailed(-1),
            .deleteFailed(-1),
        ]

        XCTAssertEqual(errors.count, 3)
    }

    func testKeychainError_isEquatable() {
        let lhs = KeychainError.saveFailed(-1)
        let rhs = KeychainError.saveFailed(-1)
        let other = KeychainError.loadFailed(-1)

        XCTAssertEqual(lhs, rhs)
        XCTAssertNotEqual(lhs, other)
    }

    func testAbsentItemLoadsEmptyStoreThenCreatesOnFirstSave() throws {
        let storage = InMemoryKeychainStorage()
        let keychain = makeKeychain(storage: storage)

        XCTAssertNil(storage.items[currentService]?["providers"])

        try keychain.save("zai-key", for: "zai")
        let savedData = try XCTUnwrap(storage.items[currentService]?["providers"])
        XCTAssertEqual(
            try JSONDecoder().decode([String: [String: String]].self, from: savedData),
            ["zai": ["value": "zai-key"]]
        )
        XCTAssertEqual(try keychain.load(for: "zai"), "zai-key")
    }

    func testLegacyFlatPayloadSurfacesAsLoadError() throws {
        let storage = InMemoryKeychainStorage()
        let payload = try JSONEncoder().encode(["zai": "legacy-key"])
        storage.items[currentService] = [
            "providers": payload,
        ]
        let keychain = makeKeychain(storage: storage)

        XCTAssertThrowsError(try keychain.load(for: "zai")) { error in
            XCTAssertEqual(error as? KeychainError, .loadFailed(errSecDecode))
        }
        // The store is untouched — recovery happens via the normal setup flow,
        // not an in-place rewrite.
        XCTAssertNotNil(storage.items[currentService]?["providers"])
        XCTAssertTrue(storage.deletedItems.isEmpty)
    }

    func testFieldMapsRoundTripAndPreserveOtherProviders() throws {
        let storage = InMemoryKeychainStorage()
        let zaiFields = ["value": "zai-key", "metadata": "keep"]
        let payload = try JSONEncoder().encode(["zai": zaiFields])
        storage.items[currentService] = [
            "providers": payload,
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

    func testKeychainStorageTypesArePublicAcrossModuleBoundary() {
        // Compile-time assertion only — no runtime behavior to exercise.
        let storage: any KeychainStorage = SecurityKeychainStorage()
        let context = KeychainAuthenticationContext()
        let error: Error = KeychainStorageError.status(errSecNotAvailable)

        XCTAssertNotNil(storage)
        XCTAssertNotNil(context.localAuthenticationContext)
        XCTAssertNotNil(error)
    }

    func testSharedAuthenticationContextIsReusedAcrossAccesses() {
        let first = KeychainAuthenticationContext.shared.localAuthenticationContext
        let second = KeychainAuthenticationContext.shared.localAuthenticationContext

        XCTAssertTrue(first === second)
    }

    func testInvalidateSwapsUnderlyingLAContext() {
        // sleep/wake/lock swap the underlying `LAContext` so macOS can
        // re-prompt within its new authorization window.
        let context = KeychainAuthenticationContext()
        let before = context.localAuthenticationContext

        context.invalidate()

        let after = context.localAuthenticationContext
        XCTAssertFalse(before === after)
    }

    private func makeKeychain(storage: InMemoryKeychainStorage) -> Keychain {
        Keychain(storage: storage, service: currentService)
    }
}

private final class InMemoryKeychainStorage: KeychainStorage, @unchecked Sendable {
    var items: [String: [String: Data]] = [:]
    var deletedItems: [(service: String, account: String)] = []
    var replaceError: OSStatus?
    var createError: OSStatus?

    func readData(
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws -> Data? {
        _ = authenticationContext
        return items[service]?[account]
    }

    func replaceData(
        _ data: Data,
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) throws {
        _ = authenticationContext
        if let replaceError {
            throw KeychainStorageError.status(replaceError)
        }
        if items[service]?[account] == nil, let createError {
            throw KeychainStorageError.status(createError)
        }
        items[service, default: [:]][account] = data
    }

    func delete(
        service: String,
        account: String,
        authenticationContext: KeychainAuthenticationContext
    ) {
        _ = authenticationContext
        items[service]?[account] = nil
        deletedItems.append((service, account))
    }
}

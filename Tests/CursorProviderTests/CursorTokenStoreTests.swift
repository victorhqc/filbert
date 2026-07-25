@testable import Core
@testable import CursorProvider
import Foundation
import XCTest

final class CursorTokenBootstrapTests: XCTestCase {
    func testSharedPairBypassesBothExternalStores() throws {
        let vault = TestCursorCredentialVault(fields: [
            "accessToken": "shared-access",
            "refreshToken": "shared-refresh",
        ])
        let externalReads = LockedBox(0)
        let store = makeStore(
            vault: vault,
            readKeychain: { _, _ in
                externalReads.withValue { $0 += 1 }
                return "external"
            },
            readSQLite: { _, _ in
                externalReads.withValue { $0 += 1 }
                return "external"
            }
        )

        let pair = try store.loadOrBootstrap()

        XCTAssertEqual(pair, CursorTokenPair(accessToken: "shared-access", refreshToken: "shared-refresh"))
        XCTAssertEqual(externalReads.read(), 0)
        XCTAssertEqual(vault.counts().saves, 0)
    }

    func testBootstrapImportsKeychainPairOnceAndPersistsIt() throws {
        let vault = TestCursorCredentialVault()
        let keychainReads = LockedBox(0)
        let sqliteReads = LockedBox(0)
        let store = makeStore(
            vault: vault,
            readKeychain: { service, account in
                keychainReads.withValue { $0 += 1 }
                guard service == "cursor-access-token" || service == "cursor-refresh-token" else {
                    return nil
                }
                return account == "cursor-user"
                    ? (service == "cursor-access-token" ? "keychain-access" : "keychain-refresh")
                    : nil
            },
            readSQLite: { _, _ in
                sqliteReads.withValue { $0 += 1 }
                return nil
            }
        )

        XCTAssertEqual(
            try store.loadOrBootstrap(),
            CursorTokenPair(accessToken: "keychain-access", refreshToken: "keychain-refresh")
        )
        XCTAssertEqual(
            try store.loadOrBootstrap(),
            CursorTokenPair(accessToken: "keychain-access", refreshToken: "keychain-refresh")
        )
        XCTAssertEqual(keychainReads.read(), 2)
        XCTAssertEqual(sqliteReads.read(), 0)
        XCTAssertEqual(vault.counts().saves, 1)
        XCTAssertEqual(
            vault.storedFields(),
            ["accessToken": "keychain-access", "refreshToken": "keychain-refresh"]
        )
    }

    func testBootstrapFallsBackToSQLiteAfterIncompleteKeychainPair() throws {
        let vault = TestCursorCredentialVault()
        let store = makeStore(
            vault: vault,
            readKeychain: { service, account in
                service == "cursor-access-token" && account == "cursor-user"
                    ? "incomplete-access"
                    : nil
            },
            readSQLite: { _, key in
                key == CursorAuth.sqliteAccessKey ? "sqlite-access" : "sqlite-refresh"
            }
        )

        XCTAssertEqual(
            try store.loadOrBootstrap(),
            CursorTokenPair(accessToken: "sqlite-access", refreshToken: "sqlite-refresh")
        )
        XCTAssertEqual(vault.counts().saves, 1)
    }

    func testMissingCredentialsAttemptExternalImportOnlyOnce() throws {
        let vault = TestCursorCredentialVault()
        let externalReads = LockedBox(0)
        let store = makeStore(
            vault: vault,
            readKeychain: { _, _ in
                externalReads.withValue { $0 += 1 }
                return nil
            },
            readSQLite: { _, _ in
                externalReads.withValue { $0 += 1 }
                return nil
            }
        )

        XCTAssertNil(try store.loadOrBootstrap())
        let readsAfterFirstAttempt = externalReads.read()
        XCTAssertNil(try store.loadOrBootstrap())

        XCTAssertGreaterThan(readsAfterFirstAttempt, 0)
        XCTAssertEqual(externalReads.read(), readsAfterFirstAttempt)
        XCTAssertEqual(vault.counts().saves, 0)
    }

    func testConcurrentBootstrapUsesOneExternalReadAndOneSharedSave() async throws {
        let vault = TestCursorCredentialVault()
        let keychainReads = LockedBox(0)
        let store = makeStore(
            vault: vault,
            readKeychain: { service, _ in
                keychainReads.withValue { $0 += 1 }
                return service == "cursor-access-token" ? "access" : "refresh"
            },
            readSQLite: { _, _ in nil }
        )

        let pairs = try await withThrowingTaskGroup(of: CursorTokenPair?.self) { group in
            for _ in 0 ..< 8 {
                group.addTask { try store.loadOrBootstrap() }
            }
            var results: [CursorTokenPair?] = []
            for try await pair in group {
                results.append(pair)
            }
            return results
        }

        let expectedPair = CursorTokenPair(accessToken: "access", refreshToken: "refresh")
        XCTAssertEqual(pairs, Array(repeating: expectedPair, count: 8))
        XCTAssertEqual(keychainReads.read(), 2)
        XCTAssertEqual(vault.counts().saves, 1)
    }

    func testMalformedSharedPairDoesNotReadExternalStores() {
        let vault = TestCursorCredentialVault(fields: ["accessToken": "only-access"])
        let externalReads = LockedBox(0)
        let store = makeStore(
            vault: vault,
            readKeychain: { _, _ in
                externalReads.withValue { $0 += 1 }
                return "external"
            },
            readSQLite: { _, _ in
                externalReads.withValue { $0 += 1 }
                return "external"
            }
        )

        XCTAssertThrowsError(try store.loadOrBootstrap()) { error in
            XCTAssertTrue(error is CursorCredentialVaultError)
        }
        XCTAssertEqual(externalReads.read(), 0)
    }

    func testFailedSharedSaveKeepsBootstrapUnconfiguredWithoutRepeatingExternalRead() {
        let vault = TestCursorCredentialVault()
        vault.setSaveFailure(true)
        let externalReads = LockedBox(0)
        let store = makeStore(
            vault: vault,
            readKeychain: { service, _ in
                externalReads.withValue { $0 += 1 }
                return service == "cursor-access-token" ? "access" : "refresh"
            },
            readSQLite: { _, _ in nil }
        )

        XCTAssertThrowsError(try store.loadOrBootstrap())
        let readsAfterFailure = externalReads.read()
        XCTAssertThrowsError(try store.loadOrBootstrap())

        XCTAssertNil(vault.storedFields())
        XCTAssertEqual(externalReads.read(), readsAfterFailure)
    }

    func testExplicitReimportReadsExternalStoresAfterFailedBootstrap() throws {
        let vault = TestCursorCredentialVault()
        let imported = LockedBox(false)
        let store = makeStore(
            vault: vault,
            readKeychain: { service, _ in
                guard imported.read() else { return nil }
                return service == "cursor-access-token" ? "new-access" : "new-refresh"
            },
            readSQLite: { _, _ in nil }
        )

        XCTAssertNil(try store.loadOrBootstrap())
        imported.withValue { $0 = true }
        try store.reimport()

        XCTAssertEqual(
            try store.loadOrBootstrap(),
            CursorTokenPair(accessToken: "new-access", refreshToken: "new-refresh")
        )
        XCTAssertEqual(vault.counts().saves, 1)
    }
}

final class CursorTokenRefreshTests: XCTestCase {
    func testEnsureValidAccessTokenRefreshesOnlySharedAccessToken() async throws {
        let vault = TestCursorCredentialVault(fields: [
            "accessToken": CursorTestFixtures.makeJWT(exp: 0),
            "refreshToken": "valid-refresh",
            "providerOwnedExtra": "retain",
        ])
        let session = CursorTestFixtures.mockSession(refreshBody: CursorTestFixtures.refreshResponse())
        let store = makeStore(
            vault: vault,
            session: session,
            readKeychain: { _, _ in nil },
            readSQLite: { _, _ in nil }
        )
        let pair = try XCTUnwrap(vault.load())
        let accessToken = try await store.ensureValidAccessToken(pair)

        XCTAssertEqual(accessToken, "fresh-access-token")
        XCTAssertEqual(
            vault.storedFields(),
            [
                "accessToken": "fresh-access-token",
                "refreshToken": "valid-refresh",
                "providerOwnedExtra": "retain",
            ]
        )
        XCTAssertEqual(vault.counts().accessUpdates, 1)
    }

    func testEnsureValidAccessTokenKeepsValidTokenWithoutRefresh() async throws {
        let vault = TestCursorCredentialVault(fields: [
            "accessToken": CursorTestFixtures.makeJWT(exp: Date().addingTimeInterval(3600).timeIntervalSince1970),
            "refreshToken": "refresh",
        ])
        let refreshCalled = LockedBox(false)
        let session = CursorTestFixtures.mockSession(
            refreshBody: CursorTestFixtures.refreshResponse(),
            onRefresh: { refreshCalled.withValue { $0 = true } }
        )
        let store = makeStore(
            vault: vault,
            session: session,
            readKeychain: { _, _ in nil },
            readSQLite: { _, _ in nil }
        )

        let pair = try XCTUnwrap(vault.load())
        let accessToken = try await store.ensureValidAccessToken(pair)
        XCTAssertEqual(accessToken, pair.accessToken)
        XCTAssertFalse(refreshCalled.read())
        XCTAssertEqual(vault.counts().accessUpdates, 0)
    }

    func testEnsureValidAccessTokenPreservesSessionAndClientErrors() async {
        let pair = CursorTokenPair(
            accessToken: CursorTestFixtures.makeJWT(exp: 0),
            refreshToken: "refresh"
        )

        let expiredVault = TestCursorCredentialVault(fields: [
            "accessToken": pair.accessToken,
            "refreshToken": pair.refreshToken,
        ])
        let expiredStore = makeStore(
            vault: expiredVault,
            session: CursorTestFixtures.mockSession(refreshBody: CursorTestFixtures.shouldLogoutResponse()),
            readKeychain: { _, _ in nil },
            readSQLite: { _, _ in nil }
        )
        await assertThrowsCursorError(.sessionExpired) {
            _ = try await expiredStore.ensureValidAccessToken(pair)
        }

        let rejectedVault = TestCursorCredentialVault(fields: [
            "accessToken": pair.accessToken,
            "refreshToken": pair.refreshToken,
        ])
        let rejectedStore = makeStore(
            vault: rejectedVault,
            session: CursorTestFixtures.mockSession(refreshStatus: 400, refreshBody: Data("{}".utf8)),
            readKeychain: { _, _ in nil },
            readSQLite: { _, _ in nil }
        )
        await assertThrowsCursorError(.clientIdRejected) {
            _ = try await rejectedStore.ensureValidAccessToken(pair)
        }
    }

    func testJWTExpiryDecodesExpClaim() {
        let token = CursorTestFixtures.makeJWT(exp: 1_700_000_000)
        XCTAssertEqual(CursorTokenStore.jwtExpiry(token), Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertNil(CursorTokenStore.jwtExpiry("not-a-jwt"))
    }
}

private func makeStore(
    vault: TestCursorCredentialVault,
    session: URLSession = .shared,
    readKeychain: @escaping @Sendable (String, String) -> String?,
    readSQLite: @escaping @Sendable (String, String) -> String?
) -> CursorTokenStore {
    CursorTokenStore(
        vault: vault,
        session: session,
        homeDirectory: "/test",
        externalStorage: ClosureKeychainStorage(read: readKeychain),
        readSQLiteValue: readSQLite
    )
}

private func assertThrowsCursorError(
    _ expected: CursorError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        XCTFail("Expected \(expected)")
    } catch let error as CursorError {
        XCTAssertEqual(error, expected)
    } catch {
        XCTFail("Unexpected error: \(error)")
    }
}

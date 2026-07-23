@testable import CursorProvider
import Foundation
import XCTest

private struct KeychainWrite: Equatable {
    let service: String
    let account: String
    let value: String
}

final class CursorTokenStoreTests: XCTestCase {
    // MARK: - AC4b: locator ordering (providers 07)

    func testLocator_prefersPATHBeforeKnownLocations() {
        let expectedPath = "/custom/bin/cursor-agent"
        let locator = CursorLocator(
            environment: ["PATH": "/custom/bin:/opt/homebrew/bin", "HOME": "/test"],
            isExecutable: { $0 == expectedPath || $0 == "/opt/homebrew/bin/cursor-agent" }
        )

        XCTAssertEqual(locator.resolve(), expectedPath)
    }

    func testLocator_findsCursorAgentBeforeCursorAndAgent() {
        let locator = CursorLocator(
            environment: ["PATH": "/bin", "HOME": "/test"],
            isExecutable: {
                $0 == "/bin/cursor-agent" || $0 == "/bin/cursor" || $0 == "/bin/agent"
            }
        )

        XCTAssertEqual(locator.resolve(), "/bin/cursor-agent")
    }

    func testLocator_returnsNilWhenNoExecutableExists() {
        let locator = CursorLocator(
            environment: ["PATH": "/custom/bin", "HOME": "/test"],
            isExecutable: { _ in false }
        )

        XCTAssertNil(locator.resolve())
    }

    // MARK: - AC4: token loading order (providers 07)

    func testTokenStore_prefersKeychainBeforeSQLite() {
        let sqliteReads = LockedBox<[String]>([])

        let store = CursorTokenStore(
            homeDirectory: "/test",
            readKeychain: { service, account in
                guard service == "cursor-agent" else { return nil }
                return account == "cursor-access-token" ? "keychain-access" : "keychain-refresh"
            },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, key in
                sqliteReads.withValue { $0.append(key) }
                return nil
            }
        )

        let pair = store.load()

        XCTAssertEqual(pair?.accessToken, "keychain-access")
        XCTAssertEqual(pair?.refreshToken, "keychain-refresh")
        XCTAssertEqual(pair?.source, .keychain)
        // SQLite must not be read when Keychain has the token.
        XCTAssertTrue(sqliteReads.read().isEmpty)
    }

    func testTokenStore_fallsBackToSQLiteWhenKeychainEmpty() {
        let store = CursorTokenStore(
            homeDirectory: "/test",
            readKeychain: { _, _ in nil },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, key in
                if key == "cursorAuth/accessToken" {
                    return "sqlite-access"
                }
                if key == "cursorAuth/refreshToken" {
                    return "sqlite-refresh"
                }
                return nil
            }
        )

        let pair = store.load()

        XCTAssertEqual(pair?.accessToken, "sqlite-access")
        XCTAssertEqual(pair?.refreshToken, "sqlite-refresh")
        XCTAssertEqual(pair?.source, .sqlite)
    }

    func testTokenStore_fallsBackToSQLiteWhenKeychainPairIsIncomplete() {
        let store = CursorTokenStore(
            homeDirectory: "/test",
            readKeychain: { _, account in
                account == "cursor-access-token" ? "keychain-access" : nil
            },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, key in
                key == "cursorAuth/accessToken" ? "sqlite-access" : "sqlite-refresh"
            }
        )

        let pair = store.load()

        XCTAssertEqual(pair?.accessToken, "sqlite-access")
        XCTAssertEqual(pair?.refreshToken, "sqlite-refresh")
        XCTAssertEqual(pair?.source, .sqlite)
    }

    func testTokenStore_returnsNilWhenNeitherSourceHasToken() {
        let store = CursorTokenStore(
            homeDirectory: "/test",
            readKeychain: { _, _ in nil },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )

        XCTAssertNil(store.load())
    }

    // MARK: - AC5: JWT expiry decoding (providers 07)

    func testJWTExpiry_decodesExpClaim() {
        let token = CursorTestFixtures.makeJWT(exp: 1_700_000_000)
        let expiry = CursorTokenStore.jwtExpiry(token)

        XCTAssertEqual(expiry, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testJWTExpiry_returnsNilForNonJWT() {
        XCTAssertNil(CursorTokenStore.jwtExpiry("not-a-jwt"))
    }

    // MARK: - AC5: transparent refresh (providers 07)

    func testEnsureValidAccessToken_refreshesExpiredToken() async throws {
        let writtenBack = LockedBox<String?>(nil)
        let session = CursorTestFixtures.mockSession(
            refreshBody: CursorTestFixtures.refreshResponse()
        )
        let store = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            refreshSkew: 60,
            readKeychain: { _, _ in nil },
            writeKeychain: { _, account, value in
                if account == "cursor-access-token" {
                    writtenBack.withValue { $0 = value }
                }
            },
            readSQLiteValue: { _, _ in nil }
        )

        let pair = CursorTokenPair(
            accessToken: CursorTestFixtures.makeJWT(exp: 0),
            refreshToken: "valid-refresh",
            source: .keychain
        )

        let token = try await store.ensureValidAccessToken(pair)

        XCTAssertEqual(token, "fresh-access-token")
        XCTAssertEqual(writtenBack.read(), "fresh-access-token")
    }

    func testEnsureValidAccessToken_keepsValidTokenWithoutRefresh() async throws {
        var refreshCalled = false
        let session = CursorTestFixtures.mockSession(
            refreshBody: CursorTestFixtures.refreshResponse(),
            onRefresh: { refreshCalled = true }
        )
        let store = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            readKeychain: { _, _ in nil },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )

        let pair = CursorTokenPair(
            accessToken: CursorTestFixtures.makeJWT(exp: Date().addingTimeInterval(3600).timeIntervalSince1970),
            refreshToken: "refresh",
            source: .keychain
        )

        let token = try await store.ensureValidAccessToken(pair)

        XCTAssertEqual(token, pair.accessToken)
        XCTAssertFalse(refreshCalled)
    }

    func testEnsureValidAccessToken_throwsSessionExpiredOnShouldLogout() async {
        let session = CursorTestFixtures.mockSession(
            refreshBody: CursorTestFixtures.shouldLogoutResponse()
        )
        let store = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            readKeychain: { _, _ in nil },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )

        let pair = CursorTokenPair(
            accessToken: CursorTestFixtures.makeJWT(exp: 0),
            refreshToken: "refresh",
            source: .keychain
        )

        await assertThrowsCursorError(.sessionExpired) {
            _ = try await store.ensureValidAccessToken(pair)
        }
    }

    func testEnsureValidAccessToken_throwsSessionExpiredWhenAccessTokenIsMissing() async {
        let session = CursorTestFixtures.mockSession(
            refreshBody: Data(#"{"shouldLogout":false}"#.utf8)
        )
        let store = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            readKeychain: { _, _ in nil },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )

        let pair = CursorTokenPair(
            accessToken: CursorTestFixtures.makeJWT(exp: 0),
            refreshToken: "refresh",
            source: .keychain
        )

        await assertThrowsCursorError(.sessionExpired) {
            _ = try await store.ensureValidAccessToken(pair)
        }
    }

    // MARK: - AC11: client_id rotation (providers 07)

    func testEnsureValidAccessToken_throwsClientIdRejectedOn4xxRefresh() async {
        let session = CursorTestFixtures.mockSession(
            refreshStatus: 400,
            refreshBody: Data("{}".utf8)
        )
        let store = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            readKeychain: { _, _ in nil },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )

        let pair = CursorTokenPair(
            accessToken: CursorTestFixtures.makeJWT(exp: 0),
            refreshToken: "refresh",
            source: .keychain
        )

        await assertThrowsCursorError(.clientIdRejected) {
            _ = try await store.ensureValidAccessToken(pair)
        }
    }

    // MARK: - AC10/AC11: error message mapping (providers 07)

    func testCursorError_401MapsToAuthenticationFailed() {
        XCTAssertEqual(CursorError.http(401).errorDescription, "Authentication failed")
    }

    func testCursorError_429MapsToRateLimited() {
        XCTAssertEqual(CursorError.http(429).errorDescription, "Rate limited")
    }

    func testCursorError_sessionExpiredMessage() {
        XCTAssertEqual(CursorError.sessionExpired.errorDescription, "Session expired")
    }

    func testCursorError_clientIdRejectedMessage() {
        XCTAssertEqual(
            CursorError.clientIdRejected.errorDescription,
            "Session expired — this provider needs an update"
        )
    }

    // MARK: - Helpers

    private func assertThrowsCursorError(
        _ expected: CursorError,
        operation: () async throws -> Void
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)")
        } catch let error as CursorError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

final class CurrentCursorAgentKeychainTests: XCTestCase {
    func testTokenStore_readsCurrentCursorAgentKeychainCredentials() {
        let store = CursorTokenStore(
            homeDirectory: "/test",
            readKeychain: { service, account in
                switch (service, account) {
                case ("cursor-access-token", "cursor-user"):
                    "current-access"
                case ("cursor-refresh-token", "cursor-user"):
                    "current-refresh"
                default:
                    nil
                }
            },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )

        let pair = store.load()

        XCTAssertEqual(pair?.accessToken, "current-access")
        XCTAssertEqual(pair?.refreshToken, "current-refresh")
        XCTAssertEqual(pair?.source, .keychain)
        XCTAssertEqual(pair?.keychainCredentials, CursorAuth.currentCLIKeychainCredentials)
    }

    func testEnsureValidAccessToken_writesToCurrentCursorAgentKeychainCredentials() async throws {
        let writtenBack = LockedBox<KeychainWrite?>(nil)
        let session = CursorTestFixtures.mockSession(
            refreshBody: CursorTestFixtures.refreshResponse()
        )
        let store = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            refreshSkew: 60,
            readKeychain: { _, _ in nil },
            writeKeychain: { service, account, value in
                writtenBack.withValue { $0 = KeychainWrite(service: service, account: account, value: value) }
            },
            readSQLiteValue: { _, _ in nil }
        )
        let pair = CursorTokenPair(
            accessToken: CursorTestFixtures.makeJWT(exp: 0),
            refreshToken: "valid-refresh",
            source: .keychain,
            keychainCredentials: CursorAuth.currentCLIKeychainCredentials
        )

        _ = try await store.ensureValidAccessToken(pair)

        XCTAssertEqual(
            writtenBack.read()?.service,
            CursorAuth.currentCLIKeychainCredentials.accessTokenService
        )
        XCTAssertEqual(
            writtenBack.read()?.account,
            CursorAuth.currentCLIKeychainCredentials.accessTokenAccount
        )
        XCTAssertEqual(writtenBack.read()?.value, "fresh-access-token")
    }
}

import Core
@testable import CursorProvider
import Foundation
import XCTest

final class CursorRateLimitTests: XCTestCase {
    func testFetchQuota_suppressesRequestsDuringBackoff() async {
        let usageRequestCount = LockedBox(0)
        let session = CursorTestFixtures.mockSession(
            usageBody: Data(),
            usageStatus: 429,
            onUsage: { usageRequestCount.withValue { $0 += 1 } }
        )
        let tokenStore = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            readKeychain: { _, _ in CursorTestFixtures.tokenPair(valid: true).accessToken },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )
        let provider = CursorProvider(
            locator: CursorLocator(
                environment: ["PATH": "/bin", "HOME": "/test"],
                isExecutable: { _ in true }
            ),
            tokenStore: tokenStore,
            session: session
        )

        for _ in 0 ..< 2 {
            await assertThrowsCursorError(.http(429)) {
                _ = try await provider.fetchQuota(
                    auth: .apiKeyFree,
                    baseURL: CursorProvider.baseURL
                )
            }
        }

        XCTAssertEqual(usageRequestCount.read(), 1)
    }

    func testTokenRefresh_preservesRateLimitError() async {
        let session = CursorTestFixtures.mockSession(
            refreshStatus: 429,
            refreshBody: Data()
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

        await assertThrowsCursorError(.http(429)) {
            _ = try await store.ensureValidAccessToken(pair)
        }
    }

    func testBackoff_doublesDelayAfterConsecutiveResponses() async throws {
        let clock = LockedBox(Date(timeIntervalSince1970: 1000))
        let backoff = CursorRateLimitBackoff(
            baseDelay: 10,
            maximumDelay: 60,
            now: { clock.read() }
        )

        await backoff.recordRateLimit()
        await assertThrowsCursorError(.http(429)) {
            try await backoff.checkRequestAllowed()
        }

        clock.withValue { $0.addTimeInterval(10) }
        try await backoff.checkRequestAllowed()
        await backoff.recordRateLimit()

        clock.withValue { $0.addTimeInterval(19) }
        await assertThrowsCursorError(.http(429)) {
            try await backoff.checkRequestAllowed()
        }

        clock.withValue { $0.addTimeInterval(1) }
        try await backoff.checkRequestAllowed()
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
}

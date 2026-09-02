import Core
import Foundation
@testable import GeminiCLIProvider
import XCTest

extension GeminiCLIProviderTests {
    func testMissingCredentialsFailWithoutPlaceholderQuota() async {
        let provider = makeProvider(credentials: nil)

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: GeminiCLIProvider.baseURL
            )
            XCTFail("Expected missing-credentials error")
        } catch let error as GeminiCLIError {
            XCTAssertEqual(error, .missingCredentials)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

extension GeminiCLIProviderTests {
    func testExpiredCredentialsWithoutRefreshTokenFailAsSignedOut() async {
        let provider = makeProvider(
            credentials: GeminiCredentials(
                accessToken: "expired-token",
                refreshToken: nil,
                expiresAt: Date(timeIntervalSince1970: 100)
            ),
            now: { Date(timeIntervalSince1970: 200) }
        )

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: GeminiCLIProvider.baseURL
            )
            XCTFail("Expected signed-out error")
        } catch let error as GeminiCLIError {
            XCTAssertEqual(error, .signedOut)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

extension GeminiCLIProviderTests {
    func testFetchStopsWhenWorkflowDeadlineExpires() async {
        let transport = RecordingTransport(
            responses: [],
            delay: 0.1
        )
        let provider = makeProvider(
            credentials: validCredentials(),
            transport: transport,
            workflowTimeout: 0.01
        )

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: GeminiCLIProvider.baseURL
            )
            XCTFail("Expected workflow timeout")
        } catch let error as GeminiCLIError {
            XCTAssertEqual(error, .timeout)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

extension GeminiCLIProviderTests {
    func testUserFacingFailuresAreDistinctAndRedacted() {
        let descriptions = [
            GeminiCLIError.network.errorDescription,
            GeminiCLIError.timeout.errorDescription,
            GeminiCLIError.decoding.errorDescription,
            GeminiCLIError.http(500).errorDescription,
        ]

        XCTAssertEqual(Set(descriptions).count, descriptions.count)
        for description in descriptions {
            XCTAssertFalse(description?.contains("access-token") == true)
            XCTAssertFalse(description?.contains("gemini-project") == true)
        }
    }
}

extension GeminiCLIProviderTests {
    func testFetchRedactsSecretsFromRecordingLogsAndErrors() async throws {
        let logger = RecordingLogSink()
        let transport = RecordingTransport(
            responses: [
                GeminiHTTPResponse(
                    data: Data(#"{"cloudaicompanionProject":"project-secret"}"#.utf8),
                    statusCode: 200,
                    retryAfter: nil
                ),
                GeminiHTTPResponse(data: Data(), statusCode: 500, retryAfter: nil),
                GeminiHTTPResponse(data: Data(), statusCode: 500, retryAfter: nil),
                GeminiHTTPResponse(data: Data(), statusCode: 500, retryAfter: nil),
            ],
            logger: logger
        )
        let provider = makeProvider(
            credentials: GeminiCredentials(
                accessToken: "access-secret",
                refreshToken: "refresh-secret",
                expiresAt: Date(timeIntervalSince1970: 10000)
            ),
            transport: transport
        )

        do {
            _ = try await provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: GeminiCLIProvider.baseURL
            )
            XCTFail("Expected HTTP failure")
        } catch let error as GeminiCLIError {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.contains("access-secret"))
            XCTAssertFalse(description.contains("refresh-secret"))
            XCTAssertFalse(description.contains("project-secret"))
        }

        let logs = await logger.recordedEntries().joined(separator: "\n")
        XCTAssertFalse(logs.contains("access-secret"))
        XCTAssertFalse(logs.contains("refresh-secret"))
        XCTAssertFalse(logs.contains("project-secret"))
    }
}

extension GeminiCLIProviderTests {
    func testGlyphAssetsAreBundled() {
        guard case let .asset(name, bundle) = GeminiCLIProvider.providerGlyph else {
            return XCTFail("Expected an asset glyph")
        }
        XCTAssertEqual(name, "ProviderGlyph")
        XCTAssertNotNil(bundle.url(forResource: "ProviderGlyph", withExtension: "png"))
        XCTAssertNotNil(bundle.url(forResource: "ProviderGlyph@2x", withExtension: "png"))
    }
}

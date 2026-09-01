import Core
import Foundation
@testable import GeminiCLIProvider
import XCTest

private struct GeminiHTTPStatusCase {
    let status: Int
    let expected: GeminiCLIError
    let attempts: Int
}

final class GeminiCLIProviderTests: XCTestCase {
    func testProviderReportsAPIKeyFreeSetupAndSetupHelp() async throws {
        let provider = makeProvider(credentials: nil)

        XCTAssertEqual(GeminiCLIProvider.authShape, .apiKeyFree)
        XCTAssertFalse(provider.isConfigured())
        guard case let .setup(message) = await provider.currentSetupState() else {
            return XCTFail("Expected setup state")
        }
        XCTAssertEqual(message, "Sign in to Gemini CLI")

        let setupHelp = try XCTUnwrap(GeminiCLIProvider.setupHelp)
        XCTAssertEqual(setupHelp.linkLabel, "Install Gemini CLI")
        XCTAssertEqual(
            setupHelp.url,
            URL(
                string: "https://google-gemini.github.io/gemini-cli/docs/get-started/authentication.html"
            )
        )
    }
}

extension GeminiCLIProviderTests {
    func testProviderReportsInvalidAndDeniedKeychainStates() async {
        let invalid = makeProvider(
            credentialsResult: .failure(.invalidPayload)
        )
        guard case let .setup(invalidMessage) = await invalid.currentSetupState() else {
            return XCTFail("Expected invalid-payload setup state")
        }
        XCTAssertEqual(invalidMessage, "Update Gemini CLI and sign in again")

        let denied = makeProvider(
            credentialsResult: .failure(.accessDenied(-25293))
        )
        guard case let .setup(deniedMessage) = await denied.currentSetupState() else {
            return XCTFail("Expected access-denied setup state")
        }
        XCTAssertEqual(deniedMessage, "Allow Filbert to read the Gemini CLI Keychain item")
    }
}

extension GeminiCLIProviderTests {
    func testProviderMapsAndSortsQuotaBuckets() throws {
        let provider = makeProvider(credentials: validCredentials())
        let response = try decodeFixture("quota-success.json", as: GeminiQuotaResponse.self)

        let quota = try provider.map(response)

        XCTAssertEqual(quota.lines.count, 3)
        XCTAssertEqual(quota.lines[0].label, "gemini-2.5-flash · Requests")
        XCTAssertEqual(quota.lines[0].percentage, 25)
        XCTAssertEqual(quota.lines[0].resetDate, Date(timeIntervalSince1970: 1_735_689_600.123))
        XCTAssertEqual(quota.lines[0].details?.first?.value, "75")
        XCTAssertEqual(quota.lines[1].label, "gemini-2.5-pro · Input tokens")
        XCTAssertEqual(quota.lines[1].percentage, 80)
        XCTAssertEqual(quota.lines[2].label, "gemini-2.5-pro · Output tokens")
        XCTAssertEqual(quota.lines[2].percentage, 50)
        XCTAssertTrue(quota.headline.hasPrefix("80% used"))
        XCTAssertEqual(
            quota.activityObservation?.metrics.map(\.id),
            [
                "gemini-gemini-2-5-flash-requests",
                "gemini-gemini-2-5-pro-input-tokens",
                "gemini-gemini-2-5-pro-output-tokens",
            ]
        )
    }
}

extension GeminiCLIProviderTests {
    func testProviderAcceptsFractionOnlyBucketsAndRejectsPayloadDrift() throws {
        let provider = makeProvider(credentials: validCredentials())
        let fractionOnly = GeminiQuotaResponse(buckets: [
            GeminiQuotaBucket(
                remainingAmount: nil,
                remainingFraction: 1,
                resetTime: nil,
                tokenType: nil,
                modelId: "gemini-2.5-flash"
            ),
        ])
        let quota = try provider.map(fractionOnly)
        XCTAssertEqual(quota.lines[0].percentage, 0)
        XCTAssertEqual(quota.lines[0].label, "gemini-2.5-flash · Quota")
        XCTAssertNil(quota.lines[0].total)

        XCTAssertThrowsError(
            try provider.map(GeminiQuotaResponse(buckets: [
                GeminiQuotaBucket(
                    remainingAmount: nil,
                    remainingFraction: 2,
                    resetTime: nil,
                    tokenType: "REQUESTS",
                    modelId: "gemini-2.5-flash"
                ),
            ]))
        ) { error in
            XCTAssertEqual(error as? GeminiCLIError, .payloadDrift)
        }

        XCTAssertThrowsError(
            try provider.map(GeminiQuotaResponse(buckets: [
                GeminiQuotaBucket(
                    remainingAmount: nil,
                    remainingFraction: 0.5,
                    resetTime: "not-an-iso-date",
                    tokenType: "REQUESTS",
                    modelId: "gemini-2.5-flash"
                ),
            ]))
        ) { error in
            XCTAssertEqual(error as? GeminiCLIError, .payloadDrift)
        }
    }
}

extension GeminiCLIProviderTests {
    func testFetchUsesOAuthHeadersAndReadOnlyCodeAssistRequests() async throws {
        let quotaData = Data(
            #"{"buckets":[{"modelId":"gemini-2.5-flash","tokenType":"REQUESTS","remainingFraction":0.75}]}"#.utf8
        )
        let transport = RecordingTransport(responses: [
            GeminiHTTPResponse(
                data: Data(#"{"cloudaicompanionProject":"gemini-project"}"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
            GeminiHTTPResponse(
                data: quotaData,
                statusCode: 200,
                retryAfter: nil
            ),
        ])
        let provider = makeProvider(
            credentials: validCredentials(),
            transport: transport
        )

        let quota = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: GeminiCLIProvider.baseURL
        )

        XCTAssertEqual(quota.lines[0].percentage, 25)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.map(\.url?.absoluteString),
            [
                "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
                "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
            ]
        )
        XCTAssertTrue(requests.allSatisfy {
            $0.value(forHTTPHeaderField: "Authorization") == "Bearer access-token"
        })
        let quotaBody = try XCTUnwrap(requests[1].httpBody)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: quotaBody) as? [String: String],
            ["project": "gemini-project"]
        )
    }
}

extension GeminiCLIProviderTests {
    func testFetchRefreshesWithRefreshTokenWithoutPersistingIt() async throws {
        let transport = RecordingTransport(responses: [
            GeminiHTTPResponse(
                data: Data(#"{"access_token":"refreshed-token","expires_in":3600}"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
            GeminiHTTPResponse(
                data: Data(#"{"cloudaicompanionProject":"gemini-project"}"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
            GeminiHTTPResponse(
                data: Data(#"{"buckets":[{"modelId":"gemini-2.5-flash","remainingFraction":0.5}]}"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
        ])
        let provider = makeProvider(
            credentials: GeminiCredentials(
                accessToken: "expired-token",
                refreshToken: "refresh/token",
                expiresAt: Date(timeIntervalSince1970: 100)
            ),
            transport: transport,
            now: { Date(timeIntervalSince1970: 200) }
        )

        _ = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: GeminiCLIProvider.baseURL
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(
            requests[0].url,
            URL(string: "https://oauth2.googleapis.com/token")
        )
        XCTAssertEqual(
            requests[0].value(forHTTPHeaderField: "Authorization"),
            nil
        )
        let refreshBody = try XCTUnwrap(
            String(data: XCTUnwrap(requests[0].httpBody), encoding: .utf8)
        )
        XCTAssertTrue(refreshBody.contains("refresh_token=refresh%2Ftoken"))
        XCTAssertFalse(refreshBody.contains("client_secret="))
        XCTAssertEqual(
            requests[1].value(forHTTPHeaderField: "Authorization"),
            "Bearer refreshed-token"
        )
    }
}

extension GeminiCLIProviderTests {
    func testFetchRetriesRateLimitWithoutChangingRequest() async throws {
        let transport = RecordingTransport(responses: [
            GeminiHTTPResponse(
                data: Data(#"{"cloudaicompanionProject":"gemini-project"}"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
            GeminiHTTPResponse(data: Data(), statusCode: 429, retryAfter: 0),
            GeminiHTTPResponse(
                data: Data(#"{"buckets":[{"modelId":"gemini-2.5-flash","remainingFraction":0.9}]}"#.utf8),
                statusCode: 200,
                retryAfter: nil
            ),
        ])
        let provider = makeProvider(
            credentials: validCredentials(),
            transport: transport
        )

        _ = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: GeminiCLIProvider.baseURL
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests[1].url,
            requests[2].url
        )
    }
}

extension GeminiCLIProviderTests {
    func testFetchMapsCodeAssistHTTPStatuses() async {
        let cases = [
            GeminiHTTPStatusCase(status: 401, expected: .signedOut, attempts: 1),
            GeminiHTTPStatusCase(
                status: 403,
                expected: .projectSetupRequired,
                attempts: 1
            ),
            GeminiHTTPStatusCase(status: 429, expected: .rateLimited, attempts: 3),
        ]

        for testCase in cases {
            let responses = [
                GeminiHTTPResponse(
                    data: Data(#"{"cloudaicompanionProject":"gemini-project"}"#.utf8),
                    statusCode: 200,
                    retryAfter: nil
                ),
            ] + Array(
                repeating: GeminiHTTPResponse(
                    data: Data(),
                    statusCode: testCase.status,
                    retryAfter: 0
                ),
                count: testCase.attempts
            )
            let transport = RecordingTransport(responses: responses)
            let provider = makeProvider(
                credentials: validCredentials(),
                transport: transport
            )

            do {
                _ = try await provider.fetchQuota(
                    auth: .apiKeyFree,
                    baseURL: GeminiCLIProvider.baseURL
                )
                XCTFail("Expected HTTP status \(testCase.status)")
            } catch let error as GeminiCLIError {
                XCTAssertEqual(error, testCase.expected)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}

extension GeminiCLIProviderTests {
    func testFetchCoalescesConcurrentWorkflows() async throws {
        let transport = RecordingTransport(
            responses: [
                GeminiHTTPResponse(
                    data: Data(#"{"cloudaicompanionProject":"gemini-project"}"#.utf8),
                    statusCode: 200,
                    retryAfter: nil
                ),
                GeminiHTTPResponse(
                    data: Data(#"{"buckets":[{"modelId":"gemini-2.5-flash","remainingFraction":0.9}]}"#.utf8),
                    statusCode: 200,
                    retryAfter: nil
                ),
            ],
            delay: 0.1
        )
        let provider = makeProvider(
            credentials: validCredentials(),
            transport: transport
        )

        async let first = provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: GeminiCLIProvider.baseURL
        )
        async let second = provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: GeminiCLIProvider.baseURL
        )
        _ = try await (first, second)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
    }
}

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
    func testGlyphAssetsAreBundled() {
        guard case let .asset(name, bundle) = GeminiCLIProvider.providerGlyph else {
            return XCTFail("Expected an asset glyph")
        }
        XCTAssertEqual(name, "ProviderGlyph")
        XCTAssertNotNil(bundle.url(forResource: "ProviderGlyph", withExtension: "png"))
        XCTAssertNotNil(bundle.url(forResource: "ProviderGlyph@2x", withExtension: "png"))
    }
}

import Core
import Foundation
@testable import GeminiCLIProvider
import XCTest

extension GeminiCLIProviderTests {
    func testFetchUsesOAuthHeadersAndReadOnlyCodeAssistRequests() async throws {
        let quotaData = Data(
            #"{"buckets":[{"modelId":"gemini-2.5-flash","tokenType":"REQUESTS","remainingFraction":0.75}]}"#.utf8
        )
        let transport = try RecordingTransport(responses: [
            GeminiHTTPResponse(
                data: fixtureData("load-code-assist-server-project.json"),
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
        try assertLoadCodeAssistRequest(requests[0])
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
    func testFetchUsesCurrentCodeAssistProjectFallback() async throws {
        let transport = try RecordingTransport(responses: [
            GeminiHTTPResponse(
                data: fixtureData("load-code-assist-current-project.json"),
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
            credentials: validCredentials(),
            transport: transport
        )

        _ = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: GeminiCLIProvider.baseURL
        )

        let requests = await transport.recordedRequests()
        let quotaBody = try XCTUnwrap(requests[1].httpBody)
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: quotaBody) as? [String: String],
            ["project": "current-gemini-project"]
        )
    }
}

extension GeminiCLIProviderTests {
    func testOAuthRefreshMapsRejectedTokenStatusesToSignedOut() async {
        for status in [400, 401, 403] {
            let transport = RecordingTransport(responses: [
                GeminiHTTPResponse(
                    data: Data(),
                    statusCode: status,
                    retryAfter: nil
                ),
            ])
            let client = GeminiOAuthClient(
                http: GeminiHTTPClient(transport: transport, sleep: { _ in })
            )

            do {
                _ = try await client.exchange(refreshToken: "refresh-token")
                XCTFail("Expected signed-out error for HTTP \(status)")
            } catch let error as GeminiCLIError {
                XCTAssertEqual(error, .signedOut)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
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
    func testFetchHonorsRetryAfterAndUsesExponentialBackoffForServerErrors() async throws {
        let sleeps = GeminiSleepRecorder()
        let transport = try RecordingTransport(responses: [
            GeminiHTTPResponse(
                data: Data(),
                statusCode: 429,
                retryAfter: 2.5
            ),
            GeminiHTTPResponse(
                data: fixtureData("load-code-assist-server-project.json"),
                statusCode: 200,
                retryAfter: nil
            ),
            GeminiHTTPResponse(
                data: Data(),
                statusCode: 503,
                retryAfter: nil
            ),
            GeminiHTTPResponse(
                data: fixtureData("quota-success.json"),
                statusCode: 200,
                retryAfter: nil
            ),
        ])
        let provider = makeProvider(
            credentials: validCredentials(),
            transport: transport,
            sleep: { delay in
                await sleeps.record(delay)
            }
        )

        _ = try await provider.fetchQuota(
            auth: .apiKeyFree,
            baseURL: GeminiCLIProvider.baseURL
        )

        let recordedSleeps = await sleeps.recordedValues()
        XCTAssertEqual(recordedSleeps, [2.5, 0.5])
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
        let gate = GeminiRequestGate()
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
            gate: gate
        )
        let provider = makeProvider(
            credentials: validCredentials(),
            transport: transport
        )

        let first = Task {
            try await provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: GeminiCLIProvider.baseURL
            )
        }
        await transport.waitForRequestCount(1)
        let second = Task {
            try await provider.fetchQuota(
                auth: .apiKeyFree,
                baseURL: GeminiCLIProvider.baseURL
            )
        }
        await gate.open()
        _ = try await first.value
        _ = try await second.value

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
    }
}

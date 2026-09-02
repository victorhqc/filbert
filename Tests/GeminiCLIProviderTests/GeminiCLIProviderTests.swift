import Core
import Foundation
@testable import GeminiCLIProvider
import XCTest

final class GeminiCLIProviderTests: XCTestCase {
    func testProviderReportsAPIKeyFreeSetupAndSetupHelp() async throws {
        let provider = makeProvider(credentials: nil)

        XCTAssertEqual(GeminiCLIProvider.authShape, .apiKeyFree)
        XCTAssertFalse(provider.isConfigured())
        XCTAssertTrue(makeProvider(credentials: validCredentials()).isConfigured())
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
    func testDecodesGeminiCLIKeychainCredentialFixture() throws {
        let credentials = try GeminiKeychainStore.decodeCredentials(
            from: fixtureData("keychain-oauth.json")
        )

        XCTAssertEqual(credentials.accessToken, "fixture-access-token")
        XCTAssertEqual(credentials.refreshToken, "fixture-refresh-token")
        XCTAssertEqual(
            credentials.expiresAt,
            Date(timeIntervalSince1970: 1_735_689_600)
        )
        XCTAssertFalse(String(describing: credentials).contains("fixture-"))
    }

    func testDecodesLoadCodeAssistProjectFixtures() throws {
        let serverProject = try decodeFixture(
            "load-code-assist-server-project.json",
            as: GeminiLoadCodeAssistResponse.self
        )
        let currentProject = try decodeFixture(
            "load-code-assist-current-project.json",
            as: GeminiLoadCodeAssistResponse.self
        )
        let objectProject = try decodeFixture(
            "load-code-assist-object-project.json",
            as: GeminiLoadCodeAssistResponse.self
        )

        XCTAssertEqual(serverProject.projectIdentifier, "gemini-project")
        XCTAssertEqual(currentProject.projectIdentifier, "current-gemini-project")
        XCTAssertEqual(objectProject.projectIdentifier, "object-gemini-project")
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

        let empty = try provider.map(GeminiQuotaResponse(buckets: []))
        XCTAssertTrue(empty.lines.isEmpty)
        XCTAssertEqual(empty.headline, "No usage limits reported")

        let missing = try provider.map(GeminiQuotaResponse(buckets: nil))
        XCTAssertTrue(missing.lines.isEmpty)
        XCTAssertEqual(missing.headline, "No usage limits reported")

        let drift = try decodeFixture(
            "payload-drift.json",
            as: GeminiQuotaResponse.self
        )
        XCTAssertThrowsError(
            try provider.map(drift)
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

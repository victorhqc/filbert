import Core
@testable import CursorProvider
import Foundation
import XCTest

final class CursorProviderTests: XCTestCase {
    // MARK: - AC1: provider-owned glyph (providers 07)

    func testProviderGlyphLoadsFromModuleResources() {
        guard case let .asset(name, bundle) = CursorProvider.providerGlyph else {
            return XCTFail("Expected an asset-backed provider glyph")
        }

        XCTAssertEqual(name, "ProviderGlyph")
        XCTAssertNotNil(bundle.url(forResource: name, withExtension: "png"))
        XCTAssertNotNil(bundle.url(forResource: "\(name)@2x", withExtension: "png"))
    }

    // MARK: - AC2b: external login prerequisite (providers 07)

    func testSetupHelpPointsToCursorCLIAuthenticationDocs() {
        XCTAssertEqual(CursorProvider.setupHelp.linkLabel, "Sign in to Cursor")
        XCTAssertEqual(
            CursorProvider.setupHelp.url,
            URL(string: "https://docs.cursor.com/en/cli/reference/authentication")
        )
    }

    // MARK: - AC10: setup state (providers 07)

    func testSetupState_missingBinaryAndToken_showsInstallMessage() async {
        let provider = makeProvider(token: nil, binaryExists: false)

        XCTAssertEqual(CursorProvider.authShape, .apiKeyFree)
        XCTAssertFalse(provider.isConfigured())
        guard case let .setup(message) = await provider.currentSetupState() else {
            return XCTFail("Expected setup state")
        }
        XCTAssertEqual(
            message,
            "Cursor CLI not installed — run `agent login`, or sign in to the Cursor app."
        )
    }

    func testSetupState_binaryPresentNoToken_showsSignInMessage() async {
        let provider = makeProvider(token: nil, binaryExists: true)

        XCTAssertTrue(provider.isConfigured())
        guard case let .setup(message) = await provider.currentSetupState() else {
            return XCTFail("Expected setup state")
        }
        XCTAssertEqual(message, "Sign in to Cursor")
    }

    func testSetupState_tokenPresent_isConfiguredWithNoSetupState() async {
        let provider = makeProvider(token: CursorTestFixtures.tokenPair(valid: true), binaryExists: false)

        XCTAssertTrue(provider.isConfigured())
        let state = await provider.currentSetupState()
        XCTAssertNil(state)
    }

    // MARK: - AC6: authenticated Connect-RPC request shape (providers 07)

    func testFetchQuota_issuesCorrectRequest() async throws {
        let provider = makeProviderWithMock(usageBody: CursorTestFixtures.usageResponse())

        _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: CursorProvider.baseURL)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertTrue(
            request.url?.absoluteString.contains(
                "aiserver.v1.DashboardService/GetCurrentPeriodUsage"
            ) == true
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer valid-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
    }

    func testFetchQuota_usesCustomBaseURLWhenProvided() async throws {
        let provider = makeProviderWithMock(usageBody: CursorTestFixtures.usageResponse())
        let proxy = try XCTUnwrap(URL(string: "https://cursor-proxy.example.com"))

        _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: proxy)

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertTrue(
            request.url?.absoluteString.hasPrefix("https://cursor-proxy.example.com/") == true
        )
    }

    // MARK: - AC7: plan usage mapping (providers 07)

    func testFetchQuota_mapsPlanUsageToPercentageAndCurrencyLines() async throws {
        let quota = try await fetchWithMock(CursorTestFixtures.usageResponse())

        let includedLine = try XCTUnwrap(quota.lines.first { $0.label == "Included usage" })
        XCTAssertEqual(includedLine.percentage, 42.5)
        XCTAssertEqual(try XCTUnwrap(includedLine.used), 50.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(includedLine.total), 100.0, accuracy: 0.01)
        XCTAssertEqual(includedLine.unit, "USD")
        XCTAssertNotNil(includedLine.resetDate)
    }

    func testFetchQuota_addsBonusCreditsLineWhenPresent() async throws {
        let quota = try await fetchWithMock(CursorTestFixtures.usageResponse())

        let bonusLine = try XCTUnwrap(quota.lines.first { $0.label == "Bonus credits" })
        XCTAssertEqual(try XCTUnwrap(bonusLine.total), 20.0, accuracy: 0.01)
        XCTAssertEqual(bonusLine.unit, "USD")
    }

    func testFetchQuota_addsAutoAndApiPercentDetails() async throws {
        let quota = try await fetchWithMock(CursorTestFixtures.usageResponse())

        let includedLine = try XCTUnwrap(quota.lines.first { $0.label == "Included usage" })
        let details = try XCTUnwrap(includedLine.details)
        XCTAssertTrue(details.contains { $0.label == "Auto" && $0.value == "10%" })
        XCTAssertTrue(details.contains { $0.label == "API" && $0.value == "30%" })
    }

    func testFetchQuota_omitsBonusLineWhenAbsent() async throws {
        var json = CursorTestFixtures.usageDict()
        var planUsage = json["planUsage"] as? [String: Any] ?? [:]
        planUsage.removeValue(forKey: "bonusSpend")
        json["planUsage"] = planUsage
        let quota = try await fetchWithMock(CursorTestFixtures.jsonToData(json))

        XCTAssertNil(quota.lines.first { $0.label == "Bonus credits" })
    }

    func testFetchQuota_supportsLegacyIndividualUsageShape() async throws {
        let quota = try await fetchWithMock(CursorTestFixtures.legacyResponse())

        let includedLine = try XCTUnwrap(quota.lines.first { $0.label == "Included usage" })
        XCTAssertEqual(includedLine.percentage, 55.0)
        XCTAssertEqual(try XCTUnwrap(includedLine.used), 55.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(includedLine.total), 100.0, accuracy: 0.01)

        let onDemandLine = try XCTUnwrap(quota.lines.first { $0.label == "On-demand spend" })
        XCTAssertEqual(try XCTUnwrap(onDemandLine.used), 15.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(onDemandLine.total), 20.0, accuracy: 0.01)
    }

    // MARK: - AC8: on-demand and pooled spend (providers 07)

    func testFetchQuota_addsOnDemandSpendLine() async throws {
        let quota = try await fetchWithMock(CursorTestFixtures.usageResponse())

        let onDemandLine = try XCTUnwrap(quota.lines.first { $0.label == "On-demand spend" })
        XCTAssertEqual(try XCTUnwrap(onDemandLine.used), 15.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(onDemandLine.total), 20.0, accuracy: 0.01)
        XCTAssertEqual(onDemandLine.unit, "USD")
    }

    func testFetchQuota_omitsOnDemandLineWhenLimitIsZero() async throws {
        var json = CursorTestFixtures.usageDict()
        var spendLimit = json["spendLimitUsage"] as? [String: Any] ?? [:]
        spendLimit["individualLimit"] = 0
        json["spendLimitUsage"] = spendLimit
        let quota = try await fetchWithMock(CursorTestFixtures.jsonToData(json))

        XCTAssertNil(quota.lines.first { $0.label == "On-demand spend" })
    }

    func testFetchQuota_addsPooledSpendLineForTeamPlans() async throws {
        let quota = try await fetchWithMock(CursorTestFixtures.usageResponse())

        let pooledLine = try XCTUnwrap(quota.lines.first { $0.label == "Pooled spend" })
        XCTAssertEqual(try XCTUnwrap(pooledLine.used), 5.0, accuracy: 0.01)
        // total = used + remaining = 500 + 500 = 1000 cents = $10.00
        XCTAssertEqual(try XCTUnwrap(pooledLine.total), 10.0, accuracy: 0.01)
        XCTAssertEqual(pooledLine.unit, "USD")
    }

    // MARK: - AC9: headline (providers 07)

    func testFetchQuota_headlineShowsRemainingAmountWithCountdown() async throws {
        let quota = try await fetchWithMock(CursorTestFixtures.usageResponse())

        // remaining = (10000 - 5000) / 100 = $50.00 left
        XCTAssertTrue(quota.headline.contains("left"), "headline was: \(quota.headline)")
    }

    func testFetchQuota_headlineShowsUnlimitedWhenIsUnlimited() async throws {
        var json = CursorTestFixtures.usageDict()
        json["isUnlimited"] = true
        let quota = try await fetchWithMock(CursorTestFixtures.jsonToData(json))

        XCTAssertEqual(quota.headline, "Unlimited")
    }

    func testFetchQuota_headlineFallsBackToNoDataWhenNoPlanData() async throws {
        let json = Data("""
        {
          "billingCycleStart": "1700000000000",
          "billingCycleEnd": "1702592000000",
          "isUnlimited": false
        }
        """.utf8)
        let quota = try await fetchWithMock(json)

        XCTAssertEqual(quota.headline, "No data")
    }

    // MARK: - AC10: typed errors (providers 07)

    func testFetchQuota_throwsMissingTokenWhenNoToken() async {
        let provider = makeProvider(token: nil, binaryExists: true)

        await assertThrowsCursorError(.missingToken) {
            try await provider.fetchQuota(auth: .apiKeyFree, baseURL: CursorProvider.baseURL)
        }
    }

    func testFetchQuota_throwsHttpForNon200Statuses() async {
        for code in [401, 403, 429, 500] {
            let provider = makeProviderWithMock(usageBody: Data(), usageStatus: code)
            MockURLProtocol.lastRequest = nil

            await assertThrowsCursorError(.http(code)) {
                try await provider.fetchQuota(auth: .apiKeyFree, baseURL: CursorProvider.baseURL)
            }
        }
    }

    func testFetchQuota_throwsNetworkForConnectionFailure() async {
        let provider = makeProviderWithMock(
            usageBody: Data(),
            usageError: URLError(.notConnectedToInternet)
        )

        do {
            _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: CursorProvider.baseURL)
            XCTFail("Expected network error")
        } catch let error as CursorError {
            if case .network = error {
                // expected
            } else {
                XCTFail("Expected .network error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchQuota_throwsDecodingForInvalidJSON() async {
        let provider = makeProviderWithMock(usageBody: Data("not json".utf8))

        do {
            _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: CursorProvider.baseURL)
            XCTFail("Expected decoding error")
        } catch let error as CursorError {
            if case .decoding = error {
                // expected
            } else {
                XCTFail("Expected .decoding error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func makeProvider(token: CursorTokenPair?, binaryExists: Bool) -> CursorProvider {
        let locator = CursorLocator(
            environment: ["PATH": "/bin", "HOME": "/test"],
            isExecutable: { _ in binaryExists }
        )
        let tokenStore = CursorTokenStore(
            homeDirectory: "/test",
            readKeychain: { _, _ in token?.accessToken },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )
        return CursorProvider(locator: locator, tokenStore: tokenStore, session: .shared)
    }

    private func makeProviderWithMock(
        usageBody: Data,
        usageStatus: Int = 200,
        usageError: Error? = nil
    ) -> CursorProvider {
        let session = CursorTestFixtures.mockSession(
            usageBody: usageBody,
            usageStatus: usageStatus,
            usageError: usageError
        )
        let tokenStore = CursorTokenStore(
            session: session,
            homeDirectory: "/test",
            readKeychain: { _, _ in CursorTestFixtures.tokenPair(valid: true).accessToken },
            writeKeychain: { _, _, _ in },
            readSQLiteValue: { _, _ in nil }
        )
        let locator = CursorLocator(
            environment: ["PATH": "/bin", "HOME": "/test"],
            isExecutable: { _ in true }
        )
        return CursorProvider(locator: locator, tokenStore: tokenStore, session: session)
    }

    private func fetchWithMock(_ data: Data) async throws -> ProviderQuota {
        let provider = makeProviderWithMock(usageBody: data)
        return try await provider.fetchQuota(auth: .apiKeyFree, baseURL: CursorProvider.baseURL)
    }

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

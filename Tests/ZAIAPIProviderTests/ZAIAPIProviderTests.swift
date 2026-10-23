import Core
import XCTest
@testable import ZAIAPIProvider

final class ZAIAPIProviderTests: ZAIAPIProviderTestCase {
    // MARK: - Request

    func testFetchQuota_issuesTheRawKeyReportRequest() async throws {
        _ = try await fetch(fixture("balance-global-topup"))

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.z.ai/api/biz/account/query-customer-account-report"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testFetchQuota_followsTheBaseURLOverride() async throws {
        _ = try await fetch(fixture("balance-cn-live"), baseURL: ZAIAPIProvider.bigModelBaseURL)

        XCTAssertEqual(
            MockURLProtocol.lastRequest?.url?.absoluteString,
            "https://open.bigmodel.cn/api/biz/account/query-customer-account-report"
        )
    }

    func testAuthShapeIsAPIKey() {
        guard case .apiKey = ZAIAPIProvider.authShape else {
            return XCTFail("Expected an API key provider")
        }
    }

    func testSettingsTextNamesTheKeyTypeAndTheBigModelHost() {
        XCTAssertEqual(ZAIAPIProvider.providerDescription, "Monitor pay-as-you-go balance")
        XCTAssertEqual(
            ZAIAPIProvider.providerDisclaimer,
            "Use a Standard API key. Coding Plan usage is shown by the z.ai provider. "
                + "For BigModel (bigmodel.cn) accounts, set the base URL to https://open.bigmodel.cn."
        )
    }

    // MARK: - Currency

    func testCurrencyFollowsTheHost() throws {
        let cases = [
            ("https://api.z.ai", "USD"),
            ("https://open.bigmodel.cn", "CNY"),
            ("https://OPEN.BIGMODEL.CN", "CNY"),
            ("https://bigmodel.cn", "CNY"),
            ("https://zai-proxy.example.com", "USD"),
            ("https://notbigmodel.cn", "USD"),
        ]
        for (host, currency) in cases {
            XCTAssertEqual(try ZAIAPIProvider.currency(for: XCTUnwrap(URL(string: host))), currency, host)
        }
    }

    func testBigModelHostReportsCNY() async throws {
        let quota = try await fetch(fixture("balance-cn-live"), baseURL: ZAIAPIProvider.bigModelBaseURL)

        XCTAssertTrue(quota.lines.allSatisfy { $0.balance?.unit == .currency("CNY") })
        XCTAssertEqual(quota.headline.resolved, "CN¥14.68 left")
    }

    // MARK: - Live captures

    func testTopUpShowsOnlyTheAvailableBalance() async throws {
        let quota = try await fetch(fixture("balance-global-topup"))

        XCTAssertEqual(quota.lines.map(\.id), ["available-balance"])
        XCTAssertEqual(quota.lines.map(\.label.resolved), ["Available balance"])
        XCTAssertEqual(amounts(quota), [.finite(3)])
        XCTAssertTrue(quota.lines.allSatisfy { $0.balance?.unit == .currency("USD") })
        XCTAssertEqual(quota.headline.resolved, "$3.00 left")
        XCTAssertEqual(quota.headlineUsageLineId, "available-balance")
    }

    func testSubCentSpendKeepsEveryDecimalAndHidesTheSpendLine() async throws {
        let quota = try await fetch(fixture("balance-global-spend"))

        XCTAssertEqual(quota.lines.map(\.id), ["available-balance"])
        XCTAssertEqual(amounts(quota), try [.finite(decimal("2.99999415"))])
        XCTAssertEqual(quota.activityObservation?.metrics.map(\.value), try [.number(decimal("0.00000585"))])
    }

    func testBigModelCaptureShowsTheSpendLine() async throws {
        let quota = try await fetch(fixture("balance-cn-live"), baseURL: ZAIAPIProvider.bigModelBaseURL)

        XCTAssertEqual(quota.lines.map(\.id), ["available-balance", "total-spend"])
        XCTAssertEqual(quota.lines.map(\.label.resolved), ["Available balance", "Spent to date"])
        XCTAssertEqual(amounts(quota), try [.finite(decimal("14.68002004")), .finite(decimal("0.31997996"))])
    }

    func testEmptyAccountReadsNoBalanceAvailable() async throws {
        let quota = try await fetch(fixture("balance-global-empty"))

        XCTAssertEqual(quota.headline.resolved, "No balance available")
        XCTAssertEqual(quota.lines.map(\.id), ["available-balance"])
        XCTAssertEqual(amounts(quota), [.finite(0)])
    }

    // MARK: - Lines

    func testFrozenBalanceIsShown() async throws {
        let quota = try await fetch(json: body(available: "7.5", frozen: "2.5", spend: "5"))

        XCTAssertEqual(quota.lines.map(\.id), ["available-balance", "frozen-balance", "total-spend"])
        XCTAssertEqual(quota.lines.map(\.label.resolved), ["Available balance", "Frozen", "Spent to date"])
        XCTAssertEqual(amounts(quota), [.finite(7.5), .finite(2.5), .finite(5)])
    }

    func testSpendLineAppearsAtOneCent() async throws {
        let shown = try await fetch(json: body(spend: "0.010000000"))
        let hidden = try await fetch(json: body(spend: "0.009999999"))

        XCTAssertEqual(shown.lines.map(\.id), ["available-balance", "total-spend"])
        XCTAssertEqual(hidden.lines.map(\.id), ["available-balance"])
        XCTAssertEqual(hidden.activityObservation?.metrics.map(\.id), ["total-spend"])
    }

    func testNullAvailableBalanceFallsBackToBalance() async throws {
        let quota = try await fetch(json: body(available: "null", balance: "4.2"))

        XCTAssertEqual(amounts(quota).first, try .finite(decimal("4.2")))
        XCTAssertEqual(quota.headline.resolved, "$4.20 left")
    }

    func testMissingBalanceReadsNoData() async throws {
        let quota = try await fetch(json: body(available: "null", balance: "null", frozen: "null", spend: "null"))

        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertEqual(quota.headline.resolved, "No data")
        XCTAssertNil(quota.headlineUsageLineId)
        XCTAssertEqual(quota.activityObservation?.metrics.isEmpty, true)
    }

    func testNegativeBalanceReadsNoBalanceAvailableAndKeepsTheLines() async throws {
        let quota = try await fetch(json: body(available: "-0.25", spend: "3.25"))

        XCTAssertEqual(quota.headline.resolved, "No balance available")
        XCTAssertEqual(quota.lines.map(\.id), ["available-balance", "total-spend"])
    }

    // MARK: - Activity

    func testOnlyTheSpendCountsAsActivity() async throws {
        let quota = try await fetch(json: body(available: "7.5", frozen: "2.5", spend: "5"))

        let observation = try XCTUnwrap(quota.activityObservation)
        XCTAssertEqual(observation.freshness, .fresh)
        XCTAssertEqual(observation.metrics.map(\.id), ["total-spend"])
        XCTAssertEqual(observation.metrics.map(\.kind), [.usage])
        XCTAssertEqual(observation.metrics.map(\.value), [.number(5)])
        XCTAssertTrue(observation.metrics.allSatisfy { $0.forecastDescriptor == nil })
    }

    // MARK: - Helpers

    private func body(
        available: String = "1",
        balance: String = "1",
        frozen: String = "0E-9",
        spend: String = "0E-9"
    ) -> String {
        """
        {"code":200,"msg":"Operation successful","data":{
          "balance":\(balance),"availableBalance":\(available),"frozenBalance":\(frozen),
          "totalSpendAmount":\(spend),"todaySpendAmount":null,"creditStatus":"NOT_OPEN"
        },"success":true}
        """
    }
}

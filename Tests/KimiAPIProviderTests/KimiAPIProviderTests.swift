import Core
@testable import KimiAPIProvider
import XCTest

final class KimiAPIProviderTests: XCTestCase {
    private var provider: KimiAPIProvider!
    private var retryGate: ProviderRetryGate!

    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        retryGate = ProviderRetryGate()
        provider = KimiAPIProvider(session: URLSession(configuration: config), retryGate: retryGate)
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        MockURLProtocol.reset()
        provider = nil
        retryGate = nil
        super.tearDown()
    }

    // MARK: - Request

    func testFetchQuota_issuesAuthenticatedBalanceRequest() async throws {
        _ = try await fetch(fixture("balance-live-whole"))

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.moonshot.ai/v1/users/me/balance")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    func testFetchQuota_followsTheBaseURLOverride() async throws {
        let proxy = try XCTUnwrap(URL(string: "https://kimi-proxy.example.com"))

        let quota = try await fetch(fixture("balance-live-whole"), baseURL: proxy)

        XCTAssertEqual(
            MockURLProtocol.lastRequest?.url?.absoluteString,
            "https://kimi-proxy.example.com/v1/users/me/balance"
        )
        XCTAssertEqual(quota.lines.first?.balance?.unit, .currency("USD"))
    }

    func testAuthShapeIsAPIKey() {
        guard case .apiKey = KimiAPIProvider.authShape else {
            return XCTFail("Expected an API key provider")
        }
    }

    // MARK: - Currency

    func testInternationalHostReportsUSD() async throws {
        let quota = try await fetch(fixture("balance-live-whole"))

        XCTAssertTrue(quota.lines.allSatisfy { $0.balance?.unit == .currency("USD") })
    }

    func testChinaHostReportsCNY() async throws {
        let quota = try await fetch(fixture("balance-live-whole"), baseURL: KimiAPIProvider.chinaBaseURL)

        XCTAssertTrue(quota.lines.allSatisfy { $0.balance?.unit == .currency("CNY") })
    }

    // MARK: - Lines

    func testWholeAmountsMapToThreeLines() async throws {
        let quota = try await fetch(fixture("balance-live-whole"))

        XCTAssertEqual(quota.lines.map(\.id), ["available-balance", "voucher-balance", "cash-balance"])
        XCTAssertEqual(quota.lines.map(\.label.resolved), ["Available balance", "Voucher balance", "Cash balance"])
        XCTAssertEqual(quota.lines.map(\.balance?.amount), [.finite(10), .finite(5), .finite(5)])
    }

    func testFractionalAmountsKeepEveryDecimal() async throws {
        let quota = try await fetch(fixture("balance-live-after-charge"))

        XCTAssertEqual(quota.lines.map(\.balance?.amount), try [
            .finite(decimal("9.999981")),
            .finite(decimal("4.9999905")),
            .finite(decimal("4.9999905")),
        ])
    }

    func testComponentEqualToTheAvailableBalanceIsHidden() async throws {
        let quota = try await fetch(body(available: "10", voucher: "0", cash: "10"))

        XCTAssertEqual(quota.lines.map(\.id), ["available-balance"])
    }

    func testNegativeCashBalanceIsShown() async throws {
        let quota = try await fetch(body(available: "3", voucher: "3", cash: "-2"))

        XCTAssertEqual(quota.lines.map(\.id), ["available-balance", "cash-balance"])
        XCTAssertEqual(quota.lines.last?.balance?.amount, .finite(-2))
    }

    // MARK: - Headline

    func testHeadlineShowsTheAvailableBalance() async throws {
        let quota = try await fetch(body(available: "12.5", voucher: "2.5", cash: "10"))

        XCTAssertEqual(quota.headline.resolved, "$12.50 left")
        XCTAssertEqual(quota.headlineUsageLineId, "available-balance")
    }

    func testZeroBalanceReadsNoBalanceAvailableAndKeepsTheLines() async throws {
        let quota = try await fetch(body(available: "0", voucher: "0", cash: "0"))

        XCTAssertEqual(quota.headline.resolved, "No balance available")
        XCTAssertEqual(quota.lines.map(\.id), ["available-balance"])
    }

    func testOwedCashWithNoVouchersReadsNoBalanceAvailable() async throws {
        let quota = try await fetch(body(available: "0", voucher: "0", cash: "-1.25"))

        XCTAssertEqual(quota.headline.resolved, "No balance available")
        XCTAssertEqual(quota.lines.map(\.id), ["available-balance", "cash-balance"])
    }

    // MARK: - Activity

    func testOnlyTheAvailableBalanceCountsAsActivity() async throws {
        let quota = try await fetch(fixture("balance-live-after-charge"))

        let observation = try XCTUnwrap(quota.activityObservation)
        XCTAssertEqual(observation.freshness, .fresh)
        XCTAssertEqual(observation.metrics.map(\.id), ["available-balance"])
        XCTAssertEqual(observation.metrics.map(\.kind), [.credits])
        XCTAssertEqual(observation.metrics.map(\.value), try [.number(decimal("9.999981"))])
        XCTAssertTrue(observation.metrics.allSatisfy { $0.forecastDescriptor == nil })
    }

    // MARK: - Helpers

    func fetch(_ data: Data, baseURL: URL = KimiAPIProvider.baseURL) async throws -> ProviderQuota {
        MockURLProtocol.responseData = data
        return try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: baseURL)
    }

    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func body(available: String, voucher: String, cash: String) -> Data {
        Data(#"""
        {"code":0,"data":{
          "available_balance":\#(available),"voucher_balance":\#(voucher),"cash_balance":\#(cash)
        },"scode":"0x0","status":true}
        """#.utf8)
    }

    private func decimal(_ value: String) throws -> Decimal {
        try XCTUnwrap(Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")))
    }
}

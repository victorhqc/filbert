import Core
@testable import DeepSeekProvider
import XCTest

final class DeepSeekBalanceLinesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        MockURLProtocol.responseData = nil
        MockURLProtocol.responseStatusCode = 200
        MockURLProtocol.responseError = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testZeroNegativeAndUnparseableBalancesAreOmitted() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "CNY", total: "10.00", granted: "-1.00", toppedUp: "abc"),
        ])

        XCTAssertEqual(quota.lines.map(\.label.resolved), ["Total balance"])
    }

    func testOnlyTheTotalStaysWhenTwoAmountsMatch() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "CNY", total: "20.00", granted: "10.00", toppedUp: "10.00"),
        ])

        XCTAssertEqual(quota.lines.map(\.label.resolved), ["Total balance"])
    }

    func testAmountsAreComparedOnlyWithinOneCurrency() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "CNY", total: "10.00", granted: "0.00", toppedUp: "10.00"),
            BalanceInfo(currency: "USD", total: "10.00", granted: "4.00", toppedUp: "6.00"),
        ])

        XCTAssertEqual(
            quota.lines.map(\.label.resolved),
            ["Total balance", "Total balance", "Granted credits", "Topped up"]
        )
        XCTAssertEqual(quota.lines.map(\.balance?.unit), [
            .currency("CNY"), .currency("USD"), .currency("USD"), .currency("USD"),
        ])
    }

    func testEachLineHasAnIdPerCurrencyAndComponent() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "CNY", total: "10.00", granted: "4.00", toppedUp: "6.00"),
            BalanceInfo(currency: "USD", total: "3.00", granted: "0.00", toppedUp: "3.00"),
        ])

        XCTAssertEqual(quota.lines.map(\.id), [
            "total-balance-cny", "granted-balance-cny", "topped-up-balance-cny", "total-balance-usd",
        ])
    }

    func testTheHeadlineLineIsTheFirstCurrencysTotal() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "CNY", total: "2.97", granted: "1.00", toppedUp: "1.97"),
            BalanceInfo(currency: "USD", total: "3.00", granted: "0.00", toppedUp: "3.00"),
        ])

        let headlineLine = quota.lines.first { $0.id == quota.headlineUsageLineId }
        XCTAssertEqual(headlineLine?.balance, UsageBalance(amount: .finite(Decimal(297) / 100), unit: .currency("CNY")))
    }

    func testThereIsNoHeadlineLineWithoutBalances() async throws {
        let quota = try await fetchQuota([])

        XCTAssertNil(quota.headlineUsageLineId)
    }

    func testTheHeadlineShowsAZeroTotalWithoutLines() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "USD", total: "0.00", granted: "0.00", toppedUp: "0.00"),
        ])

        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertTrue(quota.headline.resolved.hasSuffix(" left"), "headline was: \(quota.headline.resolved)")
        XCTAssertTrue(quota.headline.resolved.contains("0"), "headline was: \(quota.headline.resolved)")
    }

    private struct BalanceInfo {
        let currency: String
        let total: String
        let granted: String
        let toppedUp: String

        var json: String {
            """
            {
              "currency": "\(currency)",
              "total_balance": "\(total)",
              "granted_balance": "\(granted)",
              "topped_up_balance": "\(toppedUp)"
            }
            """
        }
    }

    private func fetchQuota(_ infos: [BalanceInfo]) async throws -> ProviderQuota {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let provider = DeepSeekProvider(session: URLSession(configuration: configuration))
        MockURLProtocol.responseData = Data("""
        {
          "is_available": true,
          "balance_infos": [\(infos.map(\.json).joined(separator: ","))]
        }
        """.utf8)
        MockURLProtocol.responseStatusCode = 200
        return try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: DeepSeekProvider.baseURL)
    }
}

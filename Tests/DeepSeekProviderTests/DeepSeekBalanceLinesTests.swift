import Core
@testable import DeepSeekProvider
import XCTest

final class DeepSeekBalanceLinesTests: XCTestCase {
    override func tearDown() {
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

        XCTAssertEqual(quota.lines.map(\.label), ["Total balance"])
    }

    func testOnlyTheTotalStaysWhenTwoAmountsMatch() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "CNY", total: "20.00", granted: "10.00", toppedUp: "10.00"),
        ])

        XCTAssertEqual(quota.lines.map(\.label), ["Total balance"])
    }

    func testAmountsAreComparedOnlyWithinOneCurrency() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "CNY", total: "10.00", granted: "0.00", toppedUp: "10.00"),
            BalanceInfo(currency: "USD", total: "10.00", granted: "4.00", toppedUp: "6.00"),
        ])

        XCTAssertEqual(quota.lines.map(\.label), ["Total balance", "Total balance", "Granted credits", "Topped up"])
        XCTAssertEqual(quota.lines.map(\.balance?.unit), [
            .currency("CNY"), .currency("USD"), .currency("USD"), .currency("USD"),
        ])
    }

    func testTheHeadlineShowsAZeroTotalWithoutLines() async throws {
        let quota = try await fetchQuota([
            BalanceInfo(currency: "USD", total: "0.00", granted: "0.00", toppedUp: "0.00"),
        ])

        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertTrue(quota.headline.hasSuffix(" left"), "headline was: \(quota.headline)")
        XCTAssertTrue(quota.headline.contains("0"), "headline was: \(quota.headline)")
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

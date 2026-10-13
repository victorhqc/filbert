import Core
@testable import DeepSeekProvider
import XCTest

final class DeepSeekForecastMappingTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_791_882_511)
    private let cents = Decimal(sign: .plus, exponent: -2, significand: 1)

    func testTheTotalBalanceCarriesABalanceDescriptorInItsCurrency() throws {
        let quota = try map(Response(balances: [Balance(currency: "USD", total: "12.93")]))

        let metric = try XCTUnwrap(quota.activityObservation?.metrics.first)
        XCTAssertEqual(metric.forecastDescriptor, AllowanceForecastDescriptor(
            accounting: .balance,
            unit: .currency("USD"),
            resolution: cents,
            timing: .receipt(receivedAt),
            usageLineId: "total-balance-usd"
        ))
        XCTAssertEqual(quota.activityObservation?.freshness, .fresh)
        XCTAssertEqual(quota.lastUpdated, receivedAt)
        XCTAssertTrue(quota.lines.contains { $0.id == metric.forecastDescriptor?.usageLineId })
    }

    func testEachCurrencyIsForecastOnItsOwnAndComponentsAreNot() throws {
        let quota = try map(Response(balances: [
            Balance(currency: "CNY", total: "10.00", granted: "4.00", toppedUp: "6.00"),
            Balance(currency: "USD", total: "3.00", granted: "1.00", toppedUp: "2.00"),
        ]))

        let descriptors = quota.activityObservation?.metrics.compactMap(\.forecastDescriptor)
        XCTAssertEqual(descriptors?.map(\.usageLineId), ["total-balance-cny", "total-balance-usd"])
        XCTAssertEqual(descriptors?.map(\.unit), [.currency("CNY"), .currency("USD")])
    }

    func testAnUnavailableAccountWithABalanceCarriesNoDescriptor() throws {
        let quota = try map(Response(isAvailable: false, balances: [Balance(currency: "USD", total: "12.93")]))

        let metric = try XCTUnwrap(quota.activityObservation?.metrics.first)
        XCTAssertEqual(metric.value, .number(Decimal(1293) / 100))
        XCTAssertNil(metric.forecastDescriptor)
    }

    func testAnUnparseableTotalCarriesNoMetric() throws {
        let quota = try map(Response(balances: [Balance(currency: "USD", total: "n/a")]))

        XCTAssertEqual(quota.activityObservation?.metrics, [])
    }

    func testARepeatedCurrencyCarriesNoDescriptor() throws {
        let quota = try map(Response(balances: [
            Balance(currency: "USD", total: "3.00"),
            Balance(currency: "usd", total: "4.00"),
        ]))

        XCTAssertEqual(quota.activityObservation?.metrics.compactMap(\.forecastDescriptor), [])
    }

    func testSteadyDepletionGivesAnEstimate() throws {
        let states = try states(of: depletingResponses)

        guard case let .estimated(depletesAt)? = states.last else {
            return XCTFail("Expected an estimate, got \(String(describing: states.last))")
        }
        let lastRead = receivedAt.addingTimeInterval(40 * 30)
        // The rate counts from the read before the first drop: 20 cents in 39 reads.
        let secondsPerCent = 39.0 * 30 / 20
        XCTAssertEqual(depletesAt.timeIntervalSince(lastRead), 1273 * secondsPerCent, accuracy: 1)
    }

    func testATopUpOrAGrantStartsANewBaseline() throws {
        for raised in [
            Balance(currency: "USD", total: "22.73", granted: "0.00", toppedUp: "22.73"),
            Balance(currency: "USD", total: "17.73", granted: "5.00", toppedUp: "12.73"),
        ] {
            let states = try states(of: depletingResponses + [Response(balances: [raised])])

            let beforeRaise = states[states.count - 2]
            guard case .estimated? = beforeRaise else {
                return XCTFail("Expected an estimate before the raise, got \(String(describing: beforeRaise))")
            }
            XCTAssertEqual(states.last, .insufficient)
        }
    }

    func testForecastingResumesAfterUnavailabilityFromANewBaseline() throws {
        let unavailable = Response(isAvailable: false, balances: [Balance(currency: "USD", total: "12.73")])
        let resumed = Response(balances: [Balance(currency: "USD", total: "12.72")])

        let states = try states(of: depletingResponses + [unavailable, resumed])

        XCTAssertNil(states[states.count - 2])
        XCTAssertEqual(states.last, .insufficient)
    }

    /// One cent every minute, read every 30 seconds, from 12.93 to 12.73.
    private var depletingResponses: [Response] {
        (0 ... 40).map { read in
            Response(balances: [Balance(currency: "USD", total: "\(Decimal(1293 - read / 2) / 100)")])
        }
    }

    private struct Balance {
        let currency: String
        let total: String
        var granted = "0.00"
        var toppedUp: String?

        var json: String {
            """
            {"currency": "\(currency)", "total_balance": "\(total)",
             "granted_balance": "\(granted)", "topped_up_balance": "\(toppedUp ?? total)"}
            """
        }
    }

    private struct Response {
        var isAvailable = true
        let balances: [Balance]

        var json: Data {
            Data("""
            {"is_available": \(isAvailable), "balance_infos": [\(balances.map(\.json).joined(separator: ","))]}
            """.utf8)
        }
    }

    private func map(_ response: Response, at date: Date? = nil) throws -> ProviderQuota {
        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: response.json)
        return DeepSeekProvider().map(decoded, receivedAt: date ?? receivedAt)
    }

    private func states(of responses: [Response]) throws -> [AllowanceForecast.State?] {
        let providerId = DeepSeekProvider.providerId
        var forecaster = AllowanceForecaster()
        return try responses.enumerated().map { index, response in
            let quota = try map(response, at: receivedAt.addingTimeInterval(TimeInterval(index) * 30))
            forecaster.record(quota.activityObservation, isStale: false, for: providerId, at: quota.lastUpdated)
            return forecaster.forecasts(for: providerId, at: quota.lastUpdated)["total-balance-usd"]?.state
        }
    }
}

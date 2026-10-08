@testable import Core
import Foundation
import XCTest

class AllowanceForecasterTestCase: XCTestCase {
    let origin = Date(timeIntervalSince1970: 1_800_000_000)
    let providerId = "provider"
    var forecaster = AllowanceForecaster()

    override func setUp() {
        super.setUp()
        forecaster = AllowanceForecaster()
    }

    func minute(_ value: Double) -> Date {
        origin.addingTimeInterval(value * 60)
    }

    var defaultReset: Date {
        minute(7 * 24 * 60)
    }

    func fixedPeriodMetric(
        id: String = "five-hour",
        consumed: Decimal,
        at time: Date,
        resetsAt: Date? = nil,
        limit: Decimal = 100,
        resolution: Decimal = 1,
        unit: AllowanceForecastDescriptor.Unit = .percentagePoints,
        approximate: Bool = false
    ) -> ProviderActivityMetric {
        ProviderActivityMetric(
            id: id,
            kind: .usage,
            value: .number(consumed),
            forecastDescriptor: AllowanceForecastDescriptor(
                accounting: .fixedPeriod(limit: limit, resetsAt: resetsAt ?? defaultReset),
                unit: unit,
                resolution: resolution,
                timing: approximate ? .receipt(time) : .source(time),
                usageLineId: id
            )
        )
    }

    func balanceMetric(
        id: String = "balance",
        remaining: Decimal,
        at time: Date,
        currency: String = "USD",
        resolution: Decimal = Decimal(string: "0.01") ?? 0
    ) -> ProviderActivityMetric {
        ProviderActivityMetric(
            id: id,
            kind: .credits,
            value: .number(remaining),
            forecastDescriptor: AllowanceForecastDescriptor(
                accounting: .balance,
                unit: .currency(currency),
                resolution: resolution,
                timing: .source(time),
                usageLineId: id
            )
        )
    }

    func record(
        _ metrics: ProviderActivityMetric...,
        freshness: ProviderActivityFreshness = .fresh,
        receivedAt: Date? = nil,
        providerId: String? = nil
    ) {
        let latestTiming = metrics.compactMap { $0.forecastDescriptor?.timing.date }.max() ?? origin
        forecaster.record(
            ProviderActivityObservation(metrics: metrics, freshness: freshness),
            for: providerId ?? self.providerId,
            at: receivedAt ?? latestTiming
        )
    }

    func recordTrace(_ points: [(minute: Double, consumed: Decimal)], id: String = "five-hour") {
        for point in points {
            record(fixedPeriodMetric(id: id, consumed: point.consumed, at: minute(point.minute)))
        }
    }

    func forecast(
        at time: Date,
        lineId: String = "five-hour",
        providerId: String? = nil
    ) -> AllowanceForecast? {
        forecaster.forecasts(for: providerId ?? self.providerId, at: time)[lineId]
    }

    func state(at time: Date, lineId: String = "five-hour") -> AllowanceForecast.State? {
        forecast(at: time, lineId: lineId)?.state
    }

    func depletion(at time: Date, lineId: String = "five-hour") -> Date? {
        guard case let .estimated(depletesAt) = state(at: time, lineId: lineId) else { return nil }
        return depletesAt
    }
}

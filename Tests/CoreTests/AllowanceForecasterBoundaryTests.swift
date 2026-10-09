@testable import Core
import Foundation
import XCTest

final class AllowanceForecasterBoundaryTests: AllowanceForecasterTestCase {
    private let linearTrace: [(minute: Double, consumed: Decimal)] = [
        (0, 20), (5, 23), (10, 25), (15, 28), (20, 30),
    ]

    func testPassedResetStartsANewPeriod() {
        let firstReset = minute(22)
        for point in linearTrace {
            record(fixedPeriodMetric(consumed: point.consumed, at: minute(point.minute), resetsAt: firstReset))
        }

        record(fixedPeriodMetric(consumed: 1, at: minute(25), resetsAt: minute(322)))

        XCTAssertEqual(state(at: minute(25)), .learning)
        XCTAssertEqual(forecast(at: minute(25))?.observedAt, minute(25))
    }

    func testResetJitterInsideTheToleranceKeepsThePeriod() throws {
        let jitter: [TimeInterval] = [0, 0.4, 60, -60, 299]
        for (point, offset) in zip(linearTrace, jitter) {
            record(fixedPeriodMetric(
                consumed: point.consumed,
                at: minute(point.minute),
                resetsAt: defaultReset.addingTimeInterval(offset)
            ))
        }

        let depletesAt = try XCTUnwrap(depletion(at: minute(20)))

        XCTAssertEqual(depletesAt.timeIntervalSince(minute(20)), 140 * 60, accuracy: 0.001)
    }

    func testResetDriftAcrossManySamplesStartsANewPeriod() {
        for (index, point) in linearTrace.enumerated() {
            record(fixedPeriodMetric(
                consumed: point.consumed,
                at: minute(point.minute),
                resetsAt: defaultReset.addingTimeInterval(Double(index) * 100)
            ))
            if index == 3 {
                XCTAssertNotNil(depletion(at: minute(point.minute)))
            }
        }

        XCTAssertEqual(state(at: minute(20)), .learning)
        XCTAssertEqual(forecast(at: minute(20))?.observedAt, minute(20))
    }

    func testResetMovingBeyondTheToleranceStartsANewPeriod() {
        recordTrace(linearTrace)

        record(fixedPeriodMetric(consumed: 31, at: minute(25), resetsAt: defaultReset.addingTimeInterval(301)))

        XCTAssertEqual(state(at: minute(25)), .learning)
    }

    func testConsumptionDecreaseWithoutAResetIsACorrection() {
        recordTrace(linearTrace)

        recordTrace([(25, 10), (30, 11)])

        XCTAssertEqual(state(at: minute(30)), .learning)
    }

    func testBalanceIncreaseIsATopUpNotConsumption() {
        for (value, remaining) in [(0.0, Decimal(10)), (10, 9), (20, 8)] {
            record(balanceMetric(remaining: remaining, at: minute(value)))
        }
        guard case .estimated = state(at: minute(20), lineId: "balance") else {
            return XCTFail("Expected an estimate before the top-up")
        }

        record(balanceMetric(remaining: 20, at: minute(25)))

        XCTAssertEqual(state(at: minute(25), lineId: "balance"), .learning)
    }

    func testLimitOrUnitChangesClearHistory() {
        recordTrace(linearTrace, providerId: "limit")
        recordTrace(linearTrace, providerId: "unit")

        record(fixedPeriodMetric(consumed: 31, at: minute(25), limit: 200), providerId: "limit")
        record(fixedPeriodMetric(consumed: 31, at: minute(25), unit: .credits), providerId: "unit")

        XCTAssertEqual(state(at: minute(25), providerId: "limit"), .learning)
        XCTAssertEqual(state(at: minute(25), providerId: "unit"), .learning)
    }

    func testMetricArrivingWithoutItsDescriptorClearsHistory() {
        recordTrace(linearTrace)

        record(ProviderActivityMetric(id: "five-hour", kind: .usage, value: .number(31)))

        XCTAssertNil(forecast(at: minute(20)))
        XCTAssertFalse(forecaster.hasHistory(for: providerId))
    }

    func testShortWindowResetLeavesTheWeeklyHistoryIntact() {
        let weeklyReset = minute(3 * 24 * 60)
        for (point, weekly) in zip(linearTrace, [Decimal(40), 42, 44, 46, 48]) {
            record(
                fixedPeriodMetric(consumed: point.consumed, at: minute(point.minute), resetsAt: minute(22)),
                fixedPeriodMetric(id: "weekly", consumed: weekly, at: minute(point.minute), resetsAt: weeklyReset)
            )
        }
        record(
            fixedPeriodMetric(consumed: 0, at: minute(25), resetsAt: minute(322)),
            fixedPeriodMetric(id: "weekly", consumed: 48, at: minute(25), resetsAt: weeklyReset)
        )

        XCTAssertEqual(state(at: minute(25)), .learning)
        XCTAssertNotNil(depletion(at: minute(25), lineId: "weekly"))
        XCTAssertEqual(forecast(at: minute(25), lineId: "weekly")?.evidenceSpan, 25 * 60)
    }

    func testCurrenciesAndPoolsStayIndependent() throws {
        for (value, dollars, euros) in [(0.0, Decimal(10), Decimal(30)), (10, 9, 25), (20, 8, 20)] {
            record(
                balanceMetric(id: "usd", remaining: dollars, at: minute(value), currency: "USD"),
                balanceMetric(id: "eur", remaining: euros, at: minute(value), currency: "EUR")
            )
        }

        let dollars = try XCTUnwrap(depletion(at: minute(20), lineId: "usd"))
        let euros = try XCTUnwrap(depletion(at: minute(20), lineId: "eur"))

        XCTAssertEqual(dollars.timeIntervalSince(minute(100)), 0, accuracy: 0.001)
        XCTAssertEqual(euros.timeIntervalSince(minute(60)), 0, accuracy: 0.001)
    }

    func testMalformedMeasurementsStartNoHistory() {
        recordTrace(linearTrace)

        let malformed: [ProviderActivityMetric] = [
            fixedPeriodMetric(id: "nan", consumed: .nan, at: minute(20)),
            fixedPeriodMetric(id: "zero-limit", consumed: 1, at: minute(20), limit: 0),
            fixedPeriodMetric(id: "negative", consumed: -1, at: minute(20)),
            fixedPeriodMetric(id: "zero-resolution", consumed: 1, at: minute(20), resolution: 0),
            fixedPeriodMetric(id: "passed-reset", consumed: 1, at: minute(20), resetsAt: minute(19)),
            balanceMetric(id: "no-currency", remaining: 5, at: minute(20), currency: ""),
            ProviderActivityMetric(
                id: "discrete",
                kind: .usage,
                value: .discrete("high"),
                forecastDescriptor: fixedPeriodMetric(id: "discrete", consumed: 1, at: minute(20)).forecastDescriptor
            ),
        ]
        for metric in malformed {
            record(metric, fixedPeriodMetric(consumed: 30, at: minute(20)))
        }

        let forecasts = forecaster.forecasts(for: providerId, at: minute(20))
        XCTAssertEqual(Set(forecasts.keys), ["five-hour"])
        XCTAssertEqual(forecast(at: minute(20))?.evidenceSpan, 20 * 60)
    }

    func testResettingAProviderClearsOnlyItsHistory() {
        recordTrace(linearTrace)
        record(fixedPeriodMetric(consumed: 1, at: minute(20)), providerId: "other")

        forecaster.reset(for: providerId)

        XCTAssertFalse(forecaster.hasHistory(for: providerId))
        XCTAssertTrue(forecaster.hasHistory(for: "other"))
    }

    func testRetainedObservationsAreBounded() throws {
        let policy = AllowanceForecastPolicy(maximumRetainedObservations: 5)
        let descriptor = try XCTUnwrap(fixedPeriodMetric(consumed: 0, at: minute(0)).forecastDescriptor)
        var history = AllowanceHistory(
            baseline: AllowanceSample(value: 0, time: minute(0), isApproximate: false),
            descriptor: descriptor
        )

        for value in 1 ... 20 {
            history.record(
                AllowanceSample(value: Decimal(value), time: minute(Double(value)), isApproximate: false),
                descriptor: descriptor,
                policy: policy
            )
        }

        XCTAssertEqual(history.samples.count, 5)
        XCTAssertEqual(history.latest.time, minute(20))
    }
}

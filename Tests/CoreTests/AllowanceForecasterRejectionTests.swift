@testable import Core
import Foundation
import XCTest

final class AllowanceForecasterRejectionTests: AllowanceForecasterTestCase {
    private let linearTrace: [(minute: Double, consumed: Decimal)] = [
        (0, 20), (5, 23), (10, 25), (15, 28), (20, 30),
    ]

    func testRejectedDataPausesTheHistoryUntilTheNextAcceptedSample() {
        recordTrace(linearTrace)
        let rejections = [
            Rejection(metric: fixedPeriodMetric(consumed: 31, at: minute(22)), freshness: .unknown),
            Rejection(metric: fixedPeriodMetric(consumed: 33, at: minute(27)), freshness: .stale),
            Rejection(metric: fixedPeriodMetric(consumed: 35, at: minute(32)), isStale: true),
            Rejection(metric: fixedPeriodMetric(consumed: .nan, at: minute(37))),
            Rejection(metric: fixedPeriodMetric(id: "weekly", consumed: 1, at: minute(42))),
        ]

        for (index, rejection) in rejections.enumerated() {
            let rejectedAt = minute(22 + 5 * Double(index))
            record(rejection.metric, freshness: rejection.freshness, isStale: rejection.isStale)
            XCTAssertEqual(state(at: rejectedAt), .paused, "rejection \(index)")

            let acceptedAt = 25 + 5 * Double(index)
            recordTrace([(acceptedAt, Decimal(32 + 2 * index))])
            XCTAssertNotNil(depletion(at: minute(acceptedAt)), "rejection \(index)")
        }
    }

    func testRejectedFreshnessPausesEveryHistoryOfTheProvider() {
        for point in linearTrace {
            record(
                fixedPeriodMetric(consumed: point.consumed, at: minute(point.minute)),
                fixedPeriodMetric(id: "weekly", consumed: point.consumed, at: minute(point.minute))
            )
        }
        recordTrace(linearTrace, providerId: "other")

        record(fixedPeriodMetric(consumed: 31, at: minute(21)), freshness: .unknown)

        XCTAssertEqual(state(at: minute(21)), .paused)
        XCTAssertEqual(state(at: minute(21), lineId: "weekly"), .paused)
        XCTAssertNotNil(forecaster.forecasts(for: "other", at: minute(21))["five-hour"]?.evidenceSpan)
    }

    func testMissingMetricPausesThenIsRemovedAfterTheMaximumHorizon() {
        recordTrace(linearTrace)

        record(fixedPeriodMetric(id: "weekly", consumed: 40, at: minute(25)))
        XCTAssertEqual(state(at: minute(25)), .paused)

        record(fixedPeriodMetric(id: "weekly", consumed: 40, at: minute(140)))
        XCTAssertEqual(state(at: minute(140)), .paused)

        record(fixedPeriodMetric(id: "weekly", consumed: 40, at: minute(141)))
        XCTAssertNil(forecast(at: minute(141)))
        XCTAssertNotNil(forecast(at: minute(141), lineId: "weekly"))

        record(receivedAt: minute(262))
        XCTAssertFalse(forecaster.hasHistory(for: providerId))
    }

    func testTwoMetricsNamingOneUsageLineProduceNoForecastForThatLine() throws {
        recordTrace(linearTrace)
        let descriptor = try XCTUnwrap(fixedPeriodMetric(consumed: 31, at: minute(25)).forecastDescriptor)
        let copy = ProviderActivityMetric(id: "copy", kind: .usage, value: .number(31), forecastDescriptor: descriptor)

        record(
            fixedPeriodMetric(consumed: 31, at: minute(25)),
            copy,
            fixedPeriodMetric(id: "weekly", consumed: 1, at: minute(25))
        )

        XCTAssertEqual(Set(forecaster.forecasts(for: providerId, at: minute(25)).keys), ["weekly"])
    }

    func testTwoHistoriesNamingOneUsageLineProduceNoForecastForThatLine() throws {
        recordTrace(linearTrace)
        let descriptor = try XCTUnwrap(fixedPeriodMetric(consumed: 31, at: minute(25)).forecastDescriptor)

        record(ProviderActivityMetric(id: "copy", kind: .usage, value: .number(31), forecastDescriptor: descriptor))

        XCTAssertTrue(forecaster.hasHistory(for: providerId))
        XCTAssertNil(forecast(at: minute(25)))
    }

    func testStateOrderPutsAPassedResetFirstThenExhaustionThenInterruption() {
        let resetsAt = minute(60)
        for (value, consumed) in [(0.0, Decimal(90)), (5, 95), (10, 100)] {
            record(fixedPeriodMetric(consumed: consumed, at: minute(value), resetsAt: resetsAt))
        }
        forecaster.interruptAll(at: minute(11))

        XCTAssertEqual(state(at: minute(11)), .exhausted)
        XCTAssertEqual(state(at: minute(59)), .exhausted)
        XCTAssertEqual(state(at: minute(60)), .paused)
    }

    func testInterruptionOutranksUpdatesTooFarApart() {
        recordTrace([(0, 0), (35, 2), (70, 4)])
        XCTAssertEqual(state(at: minute(70)), .tooFarApart)

        forecaster.interruptAll(at: minute(71))

        XCTAssertEqual(state(at: minute(71)), .paused)
    }

    func testRejectionOutranksQuiet() {
        recordTrace(linearTrace)
        recordTrace([(25, 30), (30, 30), (35, 30)])
        XCTAssertEqual(state(at: minute(35)), .quiet)

        record(fixedPeriodMetric(consumed: 30, at: minute(36)), isStale: true)

        XCTAssertEqual(state(at: minute(36)), .paused)
    }
}

private struct Rejection {
    let metric: ProviderActivityMetric
    var freshness: ProviderActivityFreshness = .fresh
    var isStale = false
}

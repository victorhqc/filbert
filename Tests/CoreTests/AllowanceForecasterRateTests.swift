@testable import Core
import Foundation
import XCTest

final class AllowanceForecasterRateTests: AllowanceForecasterTestCase {
    func testLinearTraceProjectsRemainingUseFromTheLatestObservation() throws {
        recordTrace([(0, 20), (5, 23), (10, 25), (15, 28), (20, 30)])

        let forecast = try XCTUnwrap(forecast(at: minute(20)))
        let depletesAt = try XCTUnwrap(depletion(at: minute(20)))

        XCTAssertEqual(depletesAt.timeIntervalSince(minute(20)), 140 * 60, accuracy: 0.001)
        XCTAssertEqual(forecast.evidenceSpan, 20 * 60)
        XCTAssertEqual(forecast.observedAt, minute(20))
        XCTAssertFalse(forecast.isApproximate)
    }

    func testExtraIntermediatePollingProducesTheSameRate() throws {
        func consumed(_ minute: Int) -> Decimal {
            Decimal(20 + minute / 2)
        }
        for value in stride(from: 0, through: 60, by: 5) {
            record(fixedPeriodMetric(consumed: consumed(value), at: minute(Double(value))), providerId: "coarse")
        }
        for value in 0 ... 60 {
            record(fixedPeriodMetric(consumed: consumed(value), at: minute(Double(value))), providerId: "fine")
        }

        let coarse = try XCTUnwrap(forecast(at: minute(60), providerId: "coarse"))
        let fine = try XCTUnwrap(forecast(at: minute(60), providerId: "fine"))

        XCTAssertEqual(coarse.state, fine.state)
        XCTAssertEqual(coarse.evidenceSpan, 30 * 60)
        XCTAssertEqual(fine.evidenceSpan, 30 * 60)
        guard case .estimated = coarse.state else {
            return XCTFail("Expected an estimate, got \(coarse.state)")
        }
    }

    func testRecentEvidenceRatherThanLifetimeHistoryDefinesTheRate() throws {
        recordTrace([(0, 0), (5, 0), (10, 1), (15, 1), (20, 2), (25, 2), (30, 3)])
        recordTrace([(35, 5), (40, 7), (45, 9), (50, 11), (55, 13), (60, 15)])

        let depletesAt = try XCTUnwrap(depletion(at: minute(60)))
        let recentPointsPerMinute = 12.0 / 30
        let remainingPoints = 100.0 - 15

        XCTAssertEqual(
            depletesAt.timeIntervalSince(minute(60)),
            remainingPoints / recentPointsPerMinute * 60,
            accuracy: 0.001
        )
        XCTAssertEqual(forecast(at: minute(60))?.evidenceSpan, 30 * 60)
    }

    func testWindowGrowsInRecentHorizonStepsUntilTheMinimumConsumption() throws {
        for value in stride(from: -30.0, through: 0, by: 5) {
            record(fixedPeriodMetric(consumed: 0, at: minute(value)))
        }
        for value in stride(from: 5.0, through: 40, by: 5) {
            record(fixedPeriodMetric(consumed: 1, at: minute(value)))
        }
        record(fixedPeriodMetric(consumed: 2, at: minute(45)))

        let forecast = try XCTUnwrap(forecast(at: minute(45)))

        XCTAssertEqual(forecast.evidenceSpan, 60 * 60)
        guard case .estimated = forecast.state else {
            return XCTFail("Expected an estimate, got \(forecast.state)")
        }
    }

    func testWholePointPercentagesNeedTwoResolutionStepsOfConsumption() {
        recordTrace([(0, 0), (5, 0), (10, 1), (15, 1), (20, 1)])

        XCTAssertEqual(state(at: minute(20)), .learning)
    }

    func testTooFewObservationsOrTooShortASpanStaysLearning() {
        recordTrace([(0, 0), (12, 5)], providerId: "sparse")
        recordTrace([(0, 0), (3, 2), (6, 4)], providerId: "short")

        XCTAssertEqual(state(at: minute(12), providerId: "sparse"), .learning)
        XCTAssertEqual(state(at: minute(6), providerId: "short"), .learning)
    }

    func testDepletionAfterTheResetIsReportedAsBeyondReset() {
        let resetsAt = minute(120)
        for (value, consumed) in [(0.0, Decimal(10)), (10, 11), (20, 12)] {
            record(fixedPeriodMetric(consumed: consumed, at: minute(value), resetsAt: resetsAt))
        }

        XCTAssertEqual(state(at: minute(20)), .beyondReset(resetsAt: resetsAt))
    }

    func testUnroundedValuesDriveTheRate() throws {
        let resetsAt = minute(2000)
        for (value, consumed) in [(0.0, "10.0"), (5, "10.3"), (10, "10.6")] {
            try record(fixedPeriodMetric(
                consumed: XCTUnwrap(Decimal(string: consumed)),
                at: minute(value),
                resetsAt: resetsAt,
                resolution: XCTUnwrap(Decimal(string: "0.1"))
            ))
        }

        XCTAssertEqual(depletion(at: minute(10)), minute(1500))
    }

    func testWeeklyStyleTraceShowsLearningForTwoHoursThenNoForecastText() {
        let resetsAt = minute(3 * 24 * 60)
        for value in stride(from: 0.0, through: 180, by: 5) {
            let consumed: Decimal = value < 60 ? 7 : 8
            record(fixedPeriodMetric(id: "weekly", consumed: consumed, at: minute(value), resetsAt: resetsAt))

            let expected: AllowanceForecast.State = value < 120 ? .learning : .insufficient
            XCTAssertEqual(state(at: minute(value), lineId: "weekly"), expected, "minute \(value)")
        }
    }

    func testRateThatIsNotFiniteProducesNoEstimate() {
        let resolution = Decimal(sign: .plus, exponent: -100, significand: 1)
        for (value, steps) in [(0.0, Decimal(0)), (10, 2), (20, 4)] {
            record(fixedPeriodMetric(consumed: steps * resolution, at: minute(value), resolution: resolution))
        }

        XCTAssertEqual(state(at: minute(20)), .learning)
    }

    func testBalanceDepletesTowardZeroInItsOwnUnit() throws {
        record(balanceMetric(remaining: 10, at: minute(0)))
        record(balanceMetric(remaining: 9, at: minute(10)))
        record(balanceMetric(remaining: 8, at: minute(20)))

        let depletesAt = try XCTUnwrap(depletion(at: minute(20), lineId: "balance"))

        XCTAssertEqual(depletesAt.timeIntervalSince(minute(100)), 0, accuracy: 0.001)
    }
}

@testable import Core
import Foundation
import XCTest

final class AllowanceForecasterValidityTests: AllowanceForecasterTestCase {
    private let linearTrace: [(minute: Double, consumed: Decimal)] = [
        (0, 20), (5, 23), (10, 25), (15, 28), (20, 30),
    ]

    func testQuietFollowsAUsableRateOnceNoConsumptionReachesTheThreshold() {
        recordTrace(linearTrace)
        recordTrace([(25, 30), (30, 30)])
        guard case .estimated = state(at: minute(30)) else {
            return XCTFail("Expected an estimate before the quiet threshold")
        }

        recordTrace([(35, 30)])

        XCTAssertEqual(state(at: minute(35)), .quiet)
    }

    func testQuietThresholdScalesWithTheLastUsableRate() {
        recordTrace([(0, 0), (5, 0), (10, 1), (15, 1), (20, 1), (25, 2)])
        recordTrace([(30, 2), (35, 2), (40, 2), (45, 2)])
        guard case .estimated = state(at: minute(45)) else {
            return XCTFail("Expected an estimate before the quiet threshold")
        }

        recordTrace([(50, 2), (55, 2)])

        XCTAssertEqual(state(at: minute(55)), .quiet)
    }

    func testNoConsumptionWithoutAPriorRateIsLearningNotQuiet() {
        for value in stride(from: 0.0, through: 60, by: 5) {
            record(fixedPeriodMetric(consumed: 5, at: minute(value)))
            XCTAssertEqual(state(at: minute(value)), .learning)
        }
    }

    func testRenewedActivityStartsANewSegmentWithoutSpanningTheQuietPeriod() {
        recordTrace(linearTrace)
        recordTrace([(25, 30), (30, 30), (35, 30), (40, 30)])
        XCTAssertEqual(state(at: minute(40)), .quiet)

        recordTrace([(45, 32)])
        XCTAssertEqual(state(at: minute(45)), .learning)

        recordTrace([(50, 34)])
        XCTAssertEqual(forecast(at: minute(50))?.evidenceSpan, 10 * 60)

        recordTrace([(55, 36)])
        XCTAssertEqual(forecast(at: minute(55))?.evidenceSpan, 15 * 60)
    }

    func testStoppedObservationsPauseTheEstimate() {
        recordTrace(linearTrace)

        guard case .estimated = state(at: minute(35)) else {
            return XCTFail("Expected an estimate within the maximum gap")
        }
        XCTAssertEqual(state(at: minute(36)), .paused)
    }

    func testRepeatedReadsOfOneCachedObservationAddNoSample() {
        recordTrace([(0, 0), (5, 2), (10, 4)])
        let original = forecast(at: minute(10))

        for received in [12.0, 14] {
            record(fixedPeriodMetric(consumed: 4, at: minute(10)), receivedAt: minute(received))
        }

        XCTAssertEqual(forecast(at: minute(10)), original)
        XCTAssertEqual(forecast(at: minute(14))?.observedAt, minute(10))
        XCTAssertEqual(state(at: minute(26)), .paused)
    }

    func testUnknownAndStaleFreshnessNeverEnterHistory() {
        record(fixedPeriodMetric(consumed: 1, at: minute(0)), freshness: .unknown)
        record(fixedPeriodMetric(consumed: 2, at: minute(5)), freshness: .stale)

        XCTAssertFalse(forecaster.hasHistory(for: providerId))
        XCTAssertNil(forecast(at: minute(5)))
    }

    func testDelayedPublicationKeepsTheSourceTimestamp() {
        record(fixedPeriodMetric(consumed: 1, at: minute(0)), receivedAt: minute(4))

        XCTAssertEqual(forecast(at: minute(4))?.observedAt, minute(0))
        XCTAssertEqual(forecast(at: minute(4))?.observationAge(at: minute(4)), 4 * 60)
    }

    func testReceiptTimingIsMarkedApproximate() {
        for (value, consumed) in [(0.0, Decimal(0)), (5, 2), (10, 4)] {
            record(fixedPeriodMetric(consumed: consumed, at: minute(value), approximate: true))
        }

        XCTAssertEqual(forecast(at: minute(10))?.isApproximate, true)
    }

    func testSleepInterruptionPausesAndRequiresANewBaseline() {
        recordTrace(linearTrace)

        forecaster.interruptAll()
        XCTAssertEqual(state(at: minute(21)), .paused)

        recordTrace([(25, 33), (30, 35)])
        XCTAssertEqual(state(at: minute(30)), .learning)
    }

    func testTwoConsecutiveLongIntervalsReportUpdatesTooFarApart() {
        recordTrace([(0, 0), (20, 2)])
        XCTAssertEqual(state(at: minute(20)), .learning)

        recordTrace([(40, 4)])
        XCTAssertEqual(state(at: minute(40)), .tooFarApart)
        XCTAssertEqual(state(at: minute(59)), .tooFarApart)

        recordTrace([(45, 5)])
        XCTAssertEqual(state(at: minute(45)), .learning)
    }

    func testClockMovingBackwardPausesAndIgnoresOlderObservations() {
        recordTrace(linearTrace)

        record(fixedPeriodMetric(consumed: 50, at: minute(10)), receivedAt: minute(10))

        XCTAssertEqual(forecast(at: minute(20))?.observedAt, minute(20))
        XCTAssertEqual(state(at: minute(10)), .paused)
    }

    func testFutureMeasurementTimesAreRejected() {
        record(fixedPeriodMetric(consumed: 1, at: minute(10)), receivedAt: minute(0))

        XCTAssertFalse(forecaster.hasHistory(for: providerId))
    }

    func testReachingTheProjectionLocallyPausesWithoutReportingExhaustion() {
        recordTrace([(0, 70), (5, 80), (10, 90)])

        XCTAssertEqual(depletion(at: minute(11)), minute(15))
        XCTAssertEqual(depletion(at: minute(14)), minute(15))
        XCTAssertEqual(forecast(at: minute(14))?.remainingUse(at: minute(14)), 60)
        XCTAssertEqual(state(at: minute(15)), .paused)
    }

    func testExhaustionComesOnlyFromAMeasurement() {
        recordTrace([(0, 90), (5, 95), (10, 100)])

        XCTAssertEqual(state(at: minute(10)), .exhausted)
    }
}

@testable import Core
import Foundation
import XCTest

final class AllowanceForecasterNearLimitTests: AllowanceForecasterTestCase {
    private let steepTrace: [(minute: Double, consumed: Decimal)] = [
        (0, 80), (5, 85), (10, 90), (15, 95),
    ]

    func testPausedAfterTheProjectedDepletionIsUncertainNearTheLimit() {
        recordTrace(steepTrace)

        XCTAssertEqual(state(at: minute(19)), .estimated(depletesAt: minute(20)))
        XCTAssertEqual(forecast(at: minute(19))?.isUncertainNearLimit, false)
        XCTAssertEqual(state(at: minute(21)), .paused)
        XCTAssertEqual(forecast(at: minute(21))?.isUncertainNearLimit, true)
    }

    func testPausedBeforeTheProjectedDepletionIsNotUncertainNearTheLimit() {
        recordTrace(steepTrace)

        forecaster.interruptAll(at: minute(16))

        XCTAssertEqual(state(at: minute(17)), .paused)
        XCTAssertEqual(forecast(at: minute(17))?.isUncertainNearLimit, false)
    }

    func testFewerThanTwoResolutionStepsLeftWithoutAnEstimateIsUncertainNearTheLimit() {
        record(
            fixedPeriodMetric(consumed: 99, at: minute(0)),
            fixedPeriodMetric(id: "weekly", consumed: 98, at: minute(0))
        )

        XCTAssertEqual(state(at: minute(1)), .learning)
        XCTAssertEqual(forecast(at: minute(1))?.isUncertainNearLimit, true)
        XCTAssertEqual(forecast(at: minute(1), lineId: "weekly")?.isUncertainNearLimit, false)
    }

    func testAnExhaustedMeasurementIsUncertainNearTheLimit() {
        record(fixedPeriodMetric(consumed: 100, at: minute(0)))

        XCTAssertEqual(state(at: minute(1)), .exhausted)
        XCTAssertEqual(forecast(at: minute(1))?.isUncertainNearLimit, true)
    }

    func testAPassedResetIsNotUncertainNearTheLimit() {
        record(fixedPeriodMetric(consumed: 99, at: minute(0), resetsAt: minute(10)))

        XCTAssertEqual(state(at: minute(11)), .paused)
        XCTAssertEqual(forecast(at: minute(11))?.isUncertainNearLimit, false)
    }
}

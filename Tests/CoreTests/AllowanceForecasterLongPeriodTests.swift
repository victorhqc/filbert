@testable import Core
import Foundation
import XCTest

final class AllowanceForecasterLongPeriodTests: AllowanceForecasterTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    func testALowAveragePaceShouldLastUntilReset() throws {
        let resetsAt = origin.addingTimeInterval(4 * day)
        recordWeekly(consumed: 7, at: origin, resetsAt: resetsAt)

        let forecast = try XCTUnwrap(forecast(at: origin, lineId: "weekly"))

        XCTAssertEqual(forecast.state, .beyondReset(resetsAt: resetsAt))
        XCTAssertEqual(forecast.pace, .periodAverage)
        XCTAssertEqual(try XCTUnwrap(forecast.evidenceSpan), 3 * day, accuracy: 0.001)
    }

    func testAHighAveragePaceRunsOutInCalendarTimeFromOneObservation() {
        recordWeekly(consumed: 60, at: origin, resetsAt: origin.addingTimeInterval(4 * day))

        guard case let .estimated(depletesAt) = state(at: origin, lineId: "weekly") else {
            return XCTFail("Expected an estimate from the average pace")
        }

        XCTAssertEqual(depletesAt.timeIntervalSince(origin), 2 * day, accuracy: 1)
    }

    func testNoConsumptionAfterTheFirstDayShouldLastUntilReset() {
        let resetsAt = origin.addingTimeInterval(4 * day)
        recordWeekly(consumed: 0, at: origin, resetsAt: resetsAt)

        XCTAssertEqual(state(at: origin, lineId: "weekly"), .beyondReset(resetsAt: resetsAt))
    }

    func testTheFirstDayOfThePeriodShowsNoForecast() {
        recordWeekly(consumed: 30, at: origin, resetsAt: origin.addingTimeInterval(6.5 * day))

        XCTAssertEqual(state(at: origin, lineId: "weekly"), .insufficient)
    }

    func testIdleTimeUnderTheLongPeriodMaximumAgeKeepsTheForecast() {
        let resetsAt = origin.addingTimeInterval(4 * day)
        recordWeekly(consumed: 7, at: origin, resetsAt: resetsAt)

        let fiveHoursLater = origin.addingTimeInterval(5 * 60 * 60)
        let sevenHoursLater = origin.addingTimeInterval(7 * 60 * 60)

        XCTAssertEqual(state(at: fiveHoursLater, lineId: "weekly"), .beyondReset(resetsAt: resetsAt))
        XCTAssertEqual(state(at: sevenHoursLater, lineId: "weekly"), .paused)
    }

    func testLongIntervalsWithoutConsumptionAreNeitherQuietNorTooFarApart() {
        let resetsAt = origin.addingTimeInterval(4 * day)
        for value in [0.0, 40, 80, 120] {
            recordWeekly(consumed: 7, at: minute(value), resetsAt: resetsAt)
        }

        XCTAssertEqual(state(at: minute(120), lineId: "weekly"), .beyondReset(resetsAt: resetsAt))
    }

    func testAPassedResetAndAReachedLimitKeepTheirStates() {
        let resetsAt = origin.addingTimeInterval(4 * day)
        recordWeekly(consumed: 100, at: origin, resetsAt: resetsAt)

        XCTAssertEqual(state(at: origin, lineId: "weekly"), .exhausted)
        XCTAssertEqual(state(at: resetsAt.addingTimeInterval(60), lineId: "weekly"), .paused)
    }

    func testAFiveHourWindowKeepsTheRecentPace() throws {
        record(fixedPeriodMetric(consumed: 60, at: origin, resetsAt: origin.addingTimeInterval(60 * 60)))

        let forecast = try XCTUnwrap(forecast(at: origin))

        XCTAssertEqual(forecast.state, .learning)
        XCTAssertEqual(forecast.pace, .recent)
    }

    private func recordWeekly(consumed: Decimal, at time: Date, resetsAt: Date) {
        record(fixedPeriodMetric(
            id: "weekly",
            consumed: consumed,
            at: time,
            resetsAt: resetsAt,
            length: UsageWindowDuration.week
        ))
    }
}

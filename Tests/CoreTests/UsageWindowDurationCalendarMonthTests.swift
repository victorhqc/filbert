import Core
import XCTest

final class UsageWindowDurationCalendarMonthTests: XCTestCase {
    private let day: TimeInterval = 24 * 60 * 60

    func testThePeriodStartsOnTheSameDayOfThePreviousMonth() throws {
        let expectedDays: [(reset: String, days: Double)] = [
            ("2026-11-27T00:00:00.000Z", 31),
            ("2026-10-21T08:15:00.000Z", 30),
            ("2026-09-01T00:00:00.000Z", 31),
            ("2026-03-15T12:00:00.000Z", 28),
            ("2028-03-15T12:00:00.000Z", 29),
            ("2028-02-28T12:00:00.000Z", 31),
        ]
        for (reset, days) in expectedDays {
            XCTAssertEqual(try UsageWindowDuration.calendarMonth(endingAt: date(reset)), days * day, reset)
        }
    }

    func testAStartDayMissingFromThePreviousMonthIsCappedAtItsLastDay() throws {
        let expectedDays: [(reset: String, days: Double)] = [
            ("2026-03-30T12:00:00.000Z", 30),
            ("2026-05-30T12:00:00.000Z", 30),
            ("2027-01-31T12:00:00.000Z", 31),
        ]
        for (reset, days) in expectedDays {
            XCTAssertEqual(try UsageWindowDuration.calendarMonth(endingAt: date(reset)), days * day, reset)
        }
    }

    func testAResetOnTheLastDayOfAMonthStartsOnTheLastDayOfThePreviousMonth() throws {
        let expectedDays: [(reset: String, days: Double)] = [
            ("2026-02-28T12:00:00.000Z", 28),
            ("2028-02-29T12:00:00.000Z", 29),
            ("2026-03-31T12:00:00.000Z", 31),
            ("2026-04-30T12:00:00.000Z", 30),
            ("2026-05-31T12:00:00.000Z", 31),
        ]
        for (reset, days) in expectedDays {
            XCTAssertEqual(try UsageWindowDuration.calendarMonth(endingAt: date(reset)), days * day, reset)
        }
    }

    func testMillisecondJitterKeepsTheLength() throws {
        let resets = ["2026-10-21T08:15:00.000Z", "2026-10-21T08:15:00.734Z", "2026-10-21T08:14:59.987Z"]

        for reset in resets {
            XCTAssertEqual(try UsageWindowDuration.calendarMonth(endingAt: date(reset)), 30 * day, reset)
        }
    }

    func testEveryResetGivesAWholeNumberOfDaysWithinCalendarMonths() throws {
        let start = try date("2026-01-01T06:30:00.000Z")
        for offset in 0 ..< 3 * 366 {
            let reset = start.addingTimeInterval(TimeInterval(offset) * day)
            let length = try XCTUnwrap(UsageWindowDuration.calendarMonth(endingAt: reset))

            XCTAssertTrue(UsageWindowDuration.calendarMonths.contains(length), "\(reset)")
            XCTAssertEqual(length.truncatingRemainder(dividingBy: day), 0, "\(reset)")
        }
    }

    func testCalendarMonthsRunFrom28Through31Days() {
        XCTAssertEqual(UsageWindowDuration.calendarMonths, 28 * day ... 31 * day)
    }

    private func date(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try XCTUnwrap(formatter.date(from: string), string)
    }
}

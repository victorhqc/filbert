import Core
import XCTest
@testable import ZAIProvider

final class ZAIProviderPeakHoursTests: XCTestCase {
    func testPeakHours_legacySchedule_hasNoDateBasedCutoff() {
        let config = ZAIPeakHours.legacyV2

        XCTAssertEqual(config.multiplier(at: shanghaiDate(month: 9, day: 30, hour: 10)), 1)
        XCTAssertEqual(config.multiplier(at: shanghaiDate(month: 10, day: 2, hour: 10)), 1)
        XCTAssertEqual(config.multiplier(at: shanghaiDate(month: 10, day: 2, hour: 15)), 3)
        XCTAssertEqual(config.multiplier(at: shanghaiDate(month: 10, day: 2, hour: 18)), 1)
    }

    func testPeakHours_creditsSchedule_appliesWeekdayWindow() {
        let config = ZAIPeakHours.credits
        // 2026-08-17 is a Monday; 2026-08-22 Saturday; 2026-08-23 Sunday.
        XCTAssertTrue(config.isInPeak(at: singaporeDate(day: 17, hour: 14)))
        XCTAssertFalse(config.isInPeak(at: singaporeDate(day: 17, hour: 13, minute: 59, second: 59)))
        XCTAssertTrue(config.isInPeak(at: singaporeDate(day: 17, hour: 17, minute: 59)))
        XCTAssertFalse(config.isInPeak(at: singaporeDate(day: 17, hour: 18)))
        XCTAssertFalse(config.isInPeak(at: singaporeDate(day: 22, hour: 15)))
        XCTAssertFalse(config.isInPeak(at: singaporeDate(day: 23, hour: 15)))

        XCTAssertEqual(config.rate(at: singaporeDate(day: 17, hour: 15)), .fractionOfStandardRate(1))
        XCTAssertEqual(config.rate(at: singaporeDate(day: 17, hour: 10)), .fractionOfStandardRate(0.5))
        XCTAssertEqual(config.rate(at: singaporeDate(day: 22, hour: 15)), .fractionOfStandardRate(0.5))
        XCTAssertNil(config.multiplier(at: singaporeDate(day: 17, hour: 15)))
    }

    // MARK: - Helpers

    private func singaporeDate(day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendarDate(
            timeZone: TimeZone(identifier: "Asia/Singapore"),
            month: 8,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
    }

    private func shanghaiDate(month: Int, day: Int, hour: Int) -> Date {
        calendarDate(
            timeZone: TimeZone(identifier: "Asia/Shanghai"),
            month: month,
            day: day,
            hour: hour
        )
    }

    private func calendarDate(
        timeZone: TimeZone?,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = timeZone
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }
}

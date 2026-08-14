import Core
import Foundation
import XCTest

final class PeakHoursConfigTests: XCTestCase {
    func testIsInPeak_matchesAnyWindowUsingHalfOpenBoundaries() {
        let config = PeakHoursConfig(
            timeZone: utcTimeZone,
            windows: [
                PeakHoursWindow(startHour: 1, endHour: 4),
                PeakHoursWindow(startHour: 6, endHour: 10),
            ],
            peakMultiplier: 2,
            offPeakMultiplier: 1
        )

        XCTAssertTrue(config.isInPeak(at: utcDate(hour: 1)))
        XCTAssertTrue(config.isInPeak(at: utcDate(hour: 3, minute: 59)))
        XCTAssertFalse(config.isInPeak(at: utcDate(hour: 4)))
        XCTAssertFalse(config.isInPeak(at: utcDate(hour: 5, minute: 59)))
        XCTAssertTrue(config.isInPeak(at: utcDate(hour: 6)))
        XCTAssertTrue(config.isInPeak(at: utcDate(hour: 9, minute: 59)))
        XCTAssertFalse(config.isInPeak(at: utcDate(hour: 10)))
    }

    func testEffectiveDate_defersStatusAndMultiplierUntilActivation() {
        let effectiveDate = utcDate(hour: 1)
        let config = PeakHoursConfig(
            timeZone: utcTimeZone,
            windows: [PeakHoursWindow(startHour: 1, endHour: 4)],
            peakMultiplier: 2,
            offPeakMultiplier: 1,
            effectiveDate: effectiveDate
        )

        let beforeActivation = effectiveDate.addingTimeInterval(-1)
        XCTAssertFalse(config.isScheduleActive(at: beforeActivation))
        XCTAssertFalse(config.isInPeak(at: beforeActivation))
        XCTAssertNil(config.multiplier(at: beforeActivation))

        XCTAssertTrue(config.isScheduleActive(at: effectiveDate))
        XCTAssertTrue(config.isInPeak(at: effectiveDate))
        XCTAssertEqual(config.multiplier(at: effectiveDate), 2)
    }

    func testMultiplier_preservesPeakAndPromotionalOffPeakPrecedence() {
        let promoEndDate = utcDate(day: 2)
        let config = PeakHoursConfig(
            timeZone: utcTimeZone,
            windows: [PeakHoursWindow(startHour: 14, endHour: 18)],
            peakMultiplier: 3,
            offPeakMultiplier: 2,
            promoMultiplier: 1,
            promoEndDate: promoEndDate
        )

        XCTAssertEqual(config.multiplier(at: utcDate(hour: 13)), 1)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 14)), 3)
        XCTAssertEqual(config.multiplier(at: utcDate(hour: 18)), 1)
        XCTAssertEqual(config.multiplier(at: promoEndDate), 2)
    }

    private var utcTimeZone: TimeZone {
        TimeZone(secondsFromGMT: 0)!
    }

    private func utcDate(day: Int = 1, hour: Int = 0, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = utcTimeZone
        components.year = 2026
        components.month = 1
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date!
    }
}

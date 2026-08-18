@testable import App
import Core
import XCTest

final class PeakHoursPresentationTests: XCTestCase {
    func testRateText_multiplierUsesMultiplierFormat() {
        XCTAssertEqual(
            PeakHoursPresentation.rateText(for: .multiplier(3)),
            "3× multiplier"
        )
    }

    func testRateText_standardFraction() {
        XCTAssertEqual(
            PeakHoursPresentation.rateText(for: .fractionOfStandardRate(1)),
            "Standard credit rate"
        )
    }

    func testRateText_discountFractionUsesPercent() {
        let text = PeakHoursPresentation.rateText(for: .fractionOfStandardRate(0.5))

        XCTAssertTrue(text.contains("50"))
        XCTAssertTrue(text.hasSuffix("credit rate"))
    }

    func testWeekdayRangeText_contiguousDaysCollapseToRange() {
        XCTAssertEqual(
            PeakHoursPresentation.weekdayRangeText(for: [2, 3, 4, 5, 6]),
            "Mon–Fri"
        )
    }

    func testWeekdayRangeText_fullWeekAndEmptyReturnNil() {
        XCTAssertNil(PeakHoursPresentation.weekdayRangeText(for: [1, 2, 3, 4, 5, 6, 7]))
        XCTAssertNil(PeakHoursPresentation.weekdayRangeText(for: []))
    }

    func testWeekdayRangeText_disjointDaysAreListed() {
        XCTAssertEqual(
            PeakHoursPresentation.weekdayRangeText(for: [1, 7]),
            "Sun and Sat"
        )
    }
}

import Core
import Foundation
import XCTest

/// Uses a plain import, because providers ask this question from outside Core.
final class AllowanceForecastDescriptorPeriodTests: XCTestCase {
    private let periodResetsAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheSameResetIsTheSamePeriod() {
        XCTAssertTrue(isSamePeriod(offset: 0))
    }

    func testAMinuteFlipInEitherDirectionIsTheSamePeriod() {
        XCTAssertTrue(isSamePeriod(offset: 60))
        XCTAssertTrue(isSamePeriod(offset: -60))
    }

    func testAResetAtTheToleranceIsTheSamePeriod() {
        XCTAssertTrue(isSamePeriod(offset: 5 * 60))
        XCTAssertTrue(isSamePeriod(offset: -5 * 60))
    }

    func testAResetBeyondTheToleranceIsANewPeriod() {
        XCTAssertFalse(isSamePeriod(offset: 5 * 60 + 1))
        XCTAssertFalse(isSamePeriod(offset: -5 * 60 - 1))
    }

    func testANextFiveHourWindowIsANewPeriod() {
        XCTAssertFalse(isSamePeriod(offset: 5 * 60 * 60))
    }

    private func isSamePeriod(offset: TimeInterval) -> Bool {
        AllowanceForecastDescriptor.isSamePeriod(
            resetsAt: periodResetsAt.addingTimeInterval(offset),
            periodResetsAt: periodResetsAt
        )
    }
}

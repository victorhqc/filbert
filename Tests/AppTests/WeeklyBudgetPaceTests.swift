@testable import App
import Core
import XCTest

final class WeeklyBudgetPaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testInitializesWithRemainingBudgetAndDailyAllowance() throws {
        let pace = try XCTUnwrap(pace(usedPercentage: 30, remainingDays: 6))

        XCTAssertEqual(pace.usedPercentage, 30)
        XCTAssertEqual(pace.remainingPercentage, 70)
        XCTAssertEqual(pace.usedFraction, 0.3, accuracy: 0.000_1)
        XCTAssertEqual(pace.elapsedFraction, 1.0 / 7.0, accuracy: 0.000_1)
        XCTAssertEqual(
            try XCTUnwrap(pace.availablePercentagePerDay),
            70.0 / 6.0,
            accuracy: 0.000_1
        )
        XCTAssertEqual(pace.tier, .warn)
    }

    func testWithinOnePercentagePointOfElapsedBudgetIsOnPace() throws {
        let pace = try XCTUnwrap(pace(usedPercentage: 29, remainingDays: 5))

        XCTAssertEqual(pace.tier, .good)
    }

    func testExhaustedBudgetIsCritical() throws {
        let pace = try XCTUnwrap(pace(usedPercentage: 125, remainingDays: 2))

        XCTAssertEqual(pace.usedPercentage, 100)
        XCTAssertEqual(pace.remainingPercentage, 0)
        XCTAssertEqual(pace.tier, .critical)
    }

    func testNegativeUsageClampsToZero() throws {
        let pace = try XCTUnwrap(pace(usedPercentage: -10, remainingDays: 6))

        XCTAssertEqual(pace.usedPercentage, 0)
        XCTAssertEqual(pace.remainingPercentage, 100)
    }

    func testSubDayWindowOmitsDailyAllowance() throws {
        let line = weeklyLine(usedPercentage: 30, resetDate: now.addingTimeInterval(23 * 60 * 60))
        let pace = try XCTUnwrap(WeeklyBudgetPace(line: line, now: now))

        XCTAssertNil(pace.availablePercentagePerDay)
        XCTAssertEqual(pace.remainingPercentage, 70)
    }

    func testRejectsLinesWithoutCompleteSevenDayTiming() {
        XCTAssertNil(WeeklyBudgetPace(
            line: UsageLine(label: "Weekly", percentage: 30),
            now: now
        ))
        XCTAssertNil(WeeklyBudgetPace(
            line: UsageLine(
                label: "5-hour window",
                percentage: 30,
                resetDate: now.addingTimeInterval(60 * 60),
                windowDuration: UsageWindowDuration.fiveHours
            ),
            now: now
        ))
        XCTAssertNil(WeeklyBudgetPace(
            line: weeklyLine(usedPercentage: 30, resetDate: now),
            now: now
        ))
        XCTAssertNil(WeeklyBudgetPace(
            line: weeklyLine(
                usedPercentage: 30,
                resetDate: now.addingTimeInterval(UsageWindowDuration.week + 1)
            ),
            now: now
        ))
    }

    private func pace(usedPercentage: Double, remainingDays: Double) -> WeeklyBudgetPace? {
        WeeklyBudgetPace(
            line: weeklyLine(
                usedPercentage: usedPercentage,
                resetDate: now.addingTimeInterval(remainingDays * 24 * 60 * 60)
            ),
            now: now
        )
    }

    private func weeklyLine(usedPercentage: Double, resetDate: Date) -> UsageLine {
        UsageLine(
            label: "Weekly",
            percentage: usedPercentage,
            resetDate: resetDate,
            windowDuration: UsageWindowDuration.week
        )
    }
}

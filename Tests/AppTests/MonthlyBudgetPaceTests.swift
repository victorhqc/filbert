@testable import App
import Core
import XCTest

final class MonthlyBudgetPaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testMonthlyPaceAtWindowStartCalculatesWeeklyAllowance() throws {
        let pace = try XCTUnwrap(monthlyPace(usedPercentage: 10, remainingDays: 29))

        XCTAssertEqual(pace.remainingPercentage, 90)
        XCTAssertEqual(pace.elapsedFraction, 1.0 / 30.0, accuracy: 0.000_1)
        XCTAssertEqual(
            try XCTUnwrap(allowancePercentage(of: pace, unit: .week)),
            90.0 / (29.0 / 7.0),
            accuracy: 0.000_1
        )
        XCTAssertEqual(pace.tier, .good)
    }

    func testMonthlyPaceMidWindowCalculatesWeeklyAllowance() throws {
        let pace = try XCTUnwrap(monthlyPace(usedPercentage: 30, remainingDays: 26))

        XCTAssertEqual(pace.remainingPercentage, 70)
        XCTAssertEqual(pace.elapsedFraction, 4.0 / 30.0, accuracy: 0.000_1)
        XCTAssertEqual(
            try XCTUnwrap(allowancePercentage(of: pace, unit: .week)),
            70.0 / (26.0 / 7.0),
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            pace.warningBoundary,
            (4.0 / 30.0 * 100) + (70.0 / (26.0 / 7.0)),
            accuracy: 0.000_1
        )
        XCTAssertEqual(pace.tier, .good)
    }

    func testMonthlyUsageBeyondWeeklyAllowanceIsWarn() throws {
        let pace = try XCTUnwrap(monthlyPace(usedPercentage: 45, remainingDays: 26))

        XCTAssertGreaterThan(pace.usedPercentage, pace.warningBoundary + 1)
        XCTAssertEqual(pace.tier, .warn)
    }

    func testMonthlyExhaustedBudgetIsCritical() throws {
        let pace = try XCTUnwrap(monthlyPace(usedPercentage: 125, remainingDays: 26))

        XCTAssertEqual(pace.usedPercentage, 100)
        XCTAssertEqual(pace.remainingPercentage, 0)
        XCTAssertEqual(pace.tier, .critical)
    }

    func testMonthlyClampsOutOfRangePercentages() throws {
        let negative = try XCTUnwrap(monthlyPace(usedPercentage: -10, remainingDays: 26))

        XCTAssertEqual(negative.usedPercentage, 0)
        XCTAssertEqual(negative.remainingPercentage, 100)

        let over = try XCTUnwrap(monthlyPace(usedPercentage: 250, remainingDays: 12))

        XCTAssertEqual(over.usedPercentage, 100)
        XCTAssertEqual(over.remainingPercentage, 0)
    }

    func testDividerFractionsMarkCompletedSegments() {
        XCTAssertEqual(BudgetPace.monthly.dividerFractions, [
            7.0 / 30.0, 14.0 / 30.0, 21.0 / 30.0, 28.0 / 30.0,
        ])
        XCTAssertEqual(BudgetPace.weekly.dividerFractions, (1 ... 6).map { Double($0) / 7.0 })
    }

    func testMonthlyExactlyOneWeekRemainingKeepsWeeklyAllowance() throws {
        let pace = try XCTUnwrap(monthlyPace(usedPercentage: 50, remainingDays: 7))

        XCTAssertEqual(try XCTUnwrap(allowancePercentage(of: pace, unit: .week)), 50, accuracy: 0.000_1)
    }

    func testMonthlyFinalPartialWeekUsesRemainingBudgetUntilReset() throws {
        let line = monthlyLine(
            usedPercentage: 40,
            resetDate: now.addingTimeInterval(6 * 24 * 60 * 60 + 23 * 60 * 60)
        )
        let pace = try XCTUnwrap(BudgetPace(line: line, now: now))

        XCTAssertEqual(pace.allowance, .untilReset(percentage: 60))
        XCTAssertEqual(pace.remainingPercentage, 60)
        XCTAssertEqual(pace.warningBoundary, 100)
        XCTAssertEqual(pace.tier, .good)
    }

    func testMonthlyPaceIsAvailableToAnyProviderSupplyingTheSharedDuration() throws {
        let line = monthlyLine(
            usedPercentage: 30,
            resetDate: now.addingTimeInterval(26 * 24 * 60 * 60)
        )
        let quota = ProviderQuota(
            providerId: "some-future-provider",
            providerName: "Future Provider",
            headline: "30%",
            lines: [line],
            lastUpdated: now
        )

        XCTAssertEqual(try XCTUnwrap(BudgetPace(line: line, now: now)).tier, .good)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: now), .good)
    }

    func testRejectsMonthlyLinesWithMissingOrNonFiniteData() {
        XCTAssertNil(BudgetPace(
            line: UsageLine(label: "Monthly", percentage: 30, windowDuration: UsageWindowDuration.month),
            now: now
        ))
        XCTAssertNil(BudgetPace(
            line: UsageLine(
                label: "Monthly",
                percentage: .nan,
                resetDate: now.addingTimeInterval(26 * 24 * 60 * 60),
                windowDuration: UsageWindowDuration.month
            ),
            now: now
        ))
        XCTAssertNil(BudgetPace(
            line: UsageLine(
                label: "Monthly",
                percentage: .infinity,
                resetDate: now.addingTimeInterval(26 * 24 * 60 * 60),
                windowDuration: UsageWindowDuration.month
            ),
            now: now
        ))
    }

    func testRejectsMonthlyLinesWithInconsistentResets() {
        XCTAssertNil(BudgetPace(
            line: monthlyLine(usedPercentage: 30, resetDate: now),
            now: now
        ))
        XCTAssertNil(BudgetPace(
            line: monthlyLine(usedPercentage: 30, resetDate: now.addingTimeInterval(-60 * 60)),
            now: now
        ))
        XCTAssertNil(BudgetPace(
            line: monthlyLine(
                usedPercentage: 30,
                resetDate: now.addingTimeInterval(UsageWindowDuration.month + 1)
            ),
            now: now
        ))
    }

    func testRejectsMonthlyLinesWithUnsupportedDurations() {
        XCTAssertNil(BudgetPace(
            line: UsageLine(
                label: "Monthly",
                percentage: 30,
                resetDate: now.addingTimeInterval(26 * 24 * 60 * 60),
                windowDuration: 31 * 24 * 60 * 60
            ),
            now: now
        ))
        XCTAssertNil(BudgetPace(
            line: UsageLine(
                label: "Monthly",
                percentage: 30,
                resetDate: now.addingTimeInterval(26 * 24 * 60 * 60),
                windowDuration: 0
            ),
            now: now
        ))
        XCTAssertNil(BudgetPace(
            line: UsageLine(
                label: "Monthly",
                percentage: 30,
                resetDate: now.addingTimeInterval(26 * 24 * 60 * 60),
                windowDuration: -7 * 24 * 60 * 60
            ),
            now: now
        ))
    }

    private func monthlyPace(usedPercentage: Double, remainingDays: Double) -> BudgetPace? {
        BudgetPace(
            line: monthlyLine(
                usedPercentage: usedPercentage,
                resetDate: now.addingTimeInterval(remainingDays * 24 * 60 * 60)
            ),
            now: now
        )
    }

    private func allowancePercentage(
        of pace: BudgetPace,
        unit: BudgetPace.AllowanceUnit
    ) -> Double? {
        guard case let .perUnit(percentage, allowanceUnit) = pace.allowance,
              allowanceUnit == unit
        else {
            return nil
        }
        return percentage
    }

    private func monthlyLine(usedPercentage: Double, resetDate: Date) -> UsageLine {
        UsageLine(
            label: "Monthly",
            percentage: usedPercentage,
            resetDate: resetDate,
            windowDuration: UsageWindowDuration.month
        )
    }
}

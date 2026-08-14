@testable import App
import Core
import XCTest

final class WeeklyBudgetPaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testInitializesWithDynamicWarningBoundary() throws {
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
        XCTAssertEqual(
            pace.warningBoundary,
            (1.0 / 7.0 * 100) + (70.0 / 6.0),
            accuracy: 0.000_1
        )
        XCTAssertEqual(pace.tier, .warn)
    }

    func testEarlyWindowUsageWithinDailyAllowanceIsGood() throws {
        let pace = try XCTUnwrap(pace(usedPercentage: 3, remainingDays: 6 + 23.0 / 24.0))

        XCTAssertGreaterThan(pace.usedFraction, pace.elapsedFraction)
        XCTAssertEqual(try XCTUnwrap(pace.availablePercentagePerDay), 13.94, accuracy: 0.01)
        XCTAssertEqual(pace.warningBoundary, 14.54, accuracy: 0.01)
        XCTAssertEqual(pace.tier, .good)
    }

    func testTierUsesDynamicBoundaryWithOnePercentagePointTolerance() throws {
        let withinTolerance = try XCTUnwrap(pace(usedPercentage: 27.3, remainingDays: 6))
        let aboveTolerance = try XCTUnwrap(pace(usedPercentage: 27.5, remainingDays: 6))

        XCTAssertLessThanOrEqual(withinTolerance.usedPercentage, withinTolerance.warningBoundary + 1)
        XCTAssertEqual(withinTolerance.tier, .good)
        XCTAssertGreaterThan(aboveTolerance.usedPercentage, aboveTolerance.warningBoundary + 1)
        XCTAssertEqual(aboveTolerance.tier, .warn)
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

    func testFinalPartialDayUsesRemainingBudgetUntilReset() throws {
        let line = weeklyLine(usedPercentage: 40, resetDate: now.addingTimeInterval(23 * 60 * 60))
        let pace = try XCTUnwrap(WeeklyBudgetPace(line: line, now: now))

        XCTAssertNil(pace.availablePercentagePerDay)
        XCTAssertEqual(pace.remainingPercentage, 60)
        XCTAssertEqual(pace.warningBoundary, 100)
        XCTAssertEqual(pace.tier, .good)
    }

    func testCompactTierUsesWeeklyPaceForEquivalentProviderLines() {
        let resetDate = now.addingTimeInterval(6 * 24 * 60 * 60 + 23 * 60 * 60)
        let openAIQuota = weeklyQuota(
            providerId: "openai-codex",
            providerName: "OpenAI Codex",
            usedPercentage: 3,
            resetDate: resetDate
        )
        let claudeQuota = weeklyQuota(
            providerId: "claude-code",
            providerName: "Claude Code",
            usedPercentage: 3,
            resetDate: resetDate
        )

        XCTAssertEqual(QuotaStatusResolver.compactTier(for: openAIQuota, at: now), .good)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: claudeQuota, at: now), .good)
    }

    func testCompactTierMatchesExpandedTierAsTimeChanges() throws {
        let resetDate = now.addingTimeInterval(6 * 24 * 60 * 60 + 23 * 60 * 60)
        let line = weeklyLine(usedPercentage: 20, resetDate: resetDate)
        let quota = weeklyQuota(
            providerId: "openai-codex",
            providerName: "OpenAI Codex",
            usedPercentage: 20,
            resetDate: resetDate
        )
        let later = now.addingTimeInterval(24 * 60 * 60)

        XCTAssertEqual(try XCTUnwrap(WeeklyBudgetPace(line: line, now: now)).tier, .warn)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: now), .warn)
        XCTAssertEqual(try XCTUnwrap(WeeklyBudgetPace(line: line, now: later)).tier, .good)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: later), .good)
    }

    func testCompactTierKeepsRawTierWhenThePrimaryLineIsNotWeekly() {
        let quota = ProviderQuota(
            providerId: "claude-code",
            providerName: "Claude Code",
            headline: "29%",
            lines: [
                UsageLine(
                    label: "5-hour window",
                    percentage: 29,
                    resetDate: now.addingTimeInterval(60 * 60),
                    windowDuration: UsageWindowDuration.fiveHours
                ),
                weeklyLine(usedPercentage: 90, resetDate: now.addingTimeInterval(5 * 24 * 60 * 60)),
            ],
            lastUpdated: now
        )

        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: now), .good)
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

    private func weeklyQuota(
        providerId: String,
        providerName: String,
        usedPercentage: Double,
        resetDate: Date
    ) -> ProviderQuota {
        ProviderQuota(
            providerId: providerId,
            providerName: providerName,
            headline: "\(usedPercentage)%",
            lines: [weeklyLine(usedPercentage: usedPercentage, resetDate: resetDate)],
            lastUpdated: now
        )
    }
}

@testable import App
import Core
import XCTest

final class BudgetPaceCompactTierTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testCompactTierUsesPaceForEquivalentProviderLines() {
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

    func testCompactTierMatchesExpandedWeeklyTierAsTimeChanges() throws {
        let resetDate = now.addingTimeInterval(6 * 24 * 60 * 60 + 23 * 60 * 60)
        let line = weeklyLine(usedPercentage: 20, resetDate: resetDate)
        let quota = weeklyQuota(
            providerId: "openai-codex",
            providerName: "OpenAI Codex",
            usedPercentage: 20,
            resetDate: resetDate
        )
        let later = now.addingTimeInterval(24 * 60 * 60)

        XCTAssertEqual(try XCTUnwrap(BudgetPace(line: line, now: now)).tier, .warn)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: now), .warn)
        XCTAssertEqual(try XCTUnwrap(BudgetPace(line: line, now: later)).tier, .good)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: later), .good)
    }

    func testCompactTierMatchesExpandedMonthlyTierAsTimeChanges() throws {
        let resetDate = now.addingTimeInterval(26 * 24 * 60 * 60)
        let line = monthlyLine(usedPercentage: 45, resetDate: resetDate)
        let quota = ProviderQuota(
            providerId: "opencode-go",
            providerName: "OpenCode Go",
            headline: "45%",
            lines: [line],
            lastUpdated: now
        )
        let later = now.addingTimeInterval(7 * 24 * 60 * 60)

        XCTAssertEqual(try XCTUnwrap(BudgetPace(line: line, now: now)).tier, .warn)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: now), .warn)
        XCTAssertEqual(try XCTUnwrap(BudgetPace(line: line, now: later)).tier, .good)
        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: later), .good)
    }

    func testCompactTierKeepsRawTierWhenThePrimaryLineIsNotPaced() {
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

    func testCompactTierKeepsRawTierWhenMonthlyLineIsNotPrimary() {
        let quota = ProviderQuota(
            providerId: "opencode-go",
            providerName: "OpenCode Go",
            headline: "95%",
            lines: [
                UsageLine(
                    label: "5-hour window",
                    percentage: 95,
                    resetDate: now.addingTimeInterval(60 * 60),
                    windowDuration: UsageWindowDuration.fiveHours
                ),
                monthlyLine(usedPercentage: 5, resetDate: now.addingTimeInterval(26 * 24 * 60 * 60)),
            ],
            lastUpdated: now
        )

        XCTAssertEqual(QuotaStatusResolver.compactTier(for: quota, at: now), .critical)
    }

    private func weeklyLine(usedPercentage: Double, resetDate: Date) -> UsageLine {
        UsageLine(
            label: "Weekly",
            percentage: usedPercentage,
            resetDate: resetDate,
            windowDuration: UsageWindowDuration.week
        )
    }

    private func monthlyLine(usedPercentage: Double, resetDate: Date) -> UsageLine {
        UsageLine(
            label: "Monthly",
            percentage: usedPercentage,
            resetDate: resetDate,
            windowDuration: UsageWindowDuration.month
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

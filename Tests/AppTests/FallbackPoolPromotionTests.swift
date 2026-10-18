@testable import App
import Core
import XCTest

final class FallbackPoolPromotionTests: FallbackPoolTestCase {
    func testAnExhaustedGroupPromotesAPoolWithABalanceFromTheFirstMeasurement() {
        XCTAssertEqual(promotedPool(in: quota(fiveHour: 100, credits: decimal("744.30"))), "credits")
    }

    func testUnlimitedCreditsArePromoted() {
        let unlimited = creditsLine(balance: UsageBalance(amount: .unlimited, unit: .credits))

        XCTAssertEqual(promotedPool(in: quota(fiveHour: 100, creditsLine: unlimited)), "credits")
    }

    func testAPoolAtOrBelowZeroIsNotPromoted() {
        XCTAssertNil(promotedPool(in: quota(fiveHour: 100, credits: 0)))
        XCTAssertNil(promotedPool(in: quota(fiveHour: 100, credits: -1)))
    }

    func testAPoolWithAnUnreadableBalanceIsNotPromoted() {
        let unreadable = creditsLine(
            balance: nil,
            details: [UsageDetail(label: DisplayText(verbatim: "Balance"), value: DisplayText(verbatim: "1,159.57"))]
        )

        XCTAssertNil(promotedPool(in: quota(fiveHour: 100, creditsLine: unreadable)))
    }

    func testAPoolWithoutADeclarationIsNeverPromoted() {
        XCTAssertNil(promotedPool(in: quota(fiveHour: 100, credits: 800, declaresFallback: false)))
    }

    func testAPoolIsNotPromotedWhileTheGroupHasRoomLeft() {
        XCTAssertNil(promotedPool(in: quota(fiveHour: 99, credits: 800)))
    }

    func testThePoolStaysPromotedUntilNoLineOfTheGroupIsAtTheLimit() {
        XCTAssertEqual(promotedPool(in: quota(fiveHour: 0, weekly: 100, credits: 800)), "credits")
        XCTAssertNil(promotedPool(in: quota(fiveHour: 0, weekly: 99, credits: 800)))
    }

    func testAFirstReadingAfterTheResetAboveZeroDemotes() {
        XCTAssertNil(promotedPool(in: quota(fiveHour: 4, credits: 800)))
    }

    func testRunningOutOfCreditsWhileExhaustedBringsBackTheWindowLayout() throws {
        let quota = quota(fiveHour: 100, credits: 0)

        XCTAssertEqual(QuotaStatusResolver.resolve(for: quota), .window(percentage: 100))
        let headline = try XCTUnwrap(AllowanceForecastPresentation(quota: quota, forecasts: [:], now: now).headline)
        XCTAssertNil(headline.label)
        XCTAssertEqual(headline.status, "Limit reached")
        XCTAssertEqual(headline.detail, QuotaFormatting.countdown(to: fiveHourReset))
    }

    func testStaleDataKeepsTheLayoutOfTheDisplayedMeasurement() {
        XCTAssertEqual(promotedPool(in: quota(fiveHour: 100, credits: 800, isStale: true)), "credits")
        XCTAssertNil(promotedPool(in: quota(fiveHour: 0, credits: 800, isStale: true)))
    }

    private func promotedPool(in quota: ProviderQuota) -> String? {
        FallbackPoolLayout(lines: quota.lines)?.pool.id
    }
}

import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexForecastMappingTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_791_823_058)
    private var fiveHour: CodexRateLimitWindow {
        window(usedPercent: 12, minutes: 300)
    }

    private var weekly: CodexRateLimitWindow {
        window(usedPercent: 38, minutes: 10080)
    }

    func testObservationIsFreshAndStampedWithTheReceiptTime() {
        let quota = map(primary: fiveHour, secondary: weekly)

        XCTAssertEqual(quota.activityObservation?.freshness, .fresh)
        XCTAssertEqual(quota.lastUpdated, receivedAt)
    }

    func testWindowLinesUseTheirMetricIdsAndShareOneLimitGroup() {
        let quota = map(primary: fiveHour, secondary: weekly)

        XCTAssertEqual(quota.lines.map(\.id), ["primary-window-usage", "secondary-window-usage"])
        XCTAssertEqual(
            quota.activityObservation?.metrics.map(\.id),
            ["primary-window-usage", "secondary-window-usage"]
        )
        XCTAssertEqual(quota.lines.map(\.limitGroup), ["subscription", "subscription"])
    }

    func testTheHeadlineLineIsTheShortestWindow() {
        let quota = map(primary: weekly, secondary: fiveHour)

        XCTAssertEqual(quota.headlineUsageLineId, "secondary-window-usage")
        XCTAssertTrue(quota.headline.hasPrefix("12%"))
    }

    func testASingleWindowIsTheHeadlineLine() {
        let quota = map(primary: nil, secondary: weekly)

        XCTAssertEqual(quota.headlineUsageLineId, "secondary-window-usage")
    }

    func testWithoutAWindowNoLineIsTheHeadline() {
        let quota = map(
            primary: nil,
            secondary: nil,
            credits: CodexCredits(balance: "811.7749020000", unlimited: false)
        )

        XCTAssertNil(quota.headlineUsageLineId)
        XCTAssertEqual(quota.lines.map(\.label), ["Credits"])
        XCTAssertNil(quota.lines.first?.id)
    }

    func testCreditDetailsKeepTheIdentityOfTheFirstWindow() {
        let quota = map(
            primary: fiveHour,
            secondary: weekly,
            credits: CodexCredits(balance: "12.5", unlimited: false)
        )

        XCTAssertEqual(quota.lines.first?.id, "primary-window-usage")
        XCTAssertEqual(quota.lines.first?.limitGroup, "subscription")
        XCTAssertEqual(quota.lines.first?.details?.first?.value, "12.5")
    }

    private func map(
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?,
        credits: CodexCredits? = nil
    ) -> ProviderQuota {
        OpenAICodexProvider().map(
            CodexRateLimitReadResult(
                rateLimits: nil,
                rateLimitsByLimitId: [
                    "codex": CodexRateLimitSnapshot(primary: primary, secondary: secondary, credits: credits),
                ]
            ),
            receivedAt: receivedAt
        )
    }

    private func window(usedPercent: Double, minutes: Int) -> CodexRateLimitWindow {
        CodexRateLimitWindow(
            usedPercent: usedPercent,
            resetsAt: receivedAt.timeIntervalSince1970 + TimeInterval(minutes * 60),
            windowDurationMins: minutes
        )
    }
}

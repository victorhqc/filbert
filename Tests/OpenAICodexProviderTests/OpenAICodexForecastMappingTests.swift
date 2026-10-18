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
        XCTAssertTrue(quota.headline.resolved.hasPrefix("12%"))
    }

    func testASingleWindowIsTheHeadlineLine() {
        let quota = map(primary: nil, secondary: weekly)

        XCTAssertEqual(quota.headlineUsageLineId, "secondary-window-usage")
    }

    func testWithoutAWindowNoLineIsTheHeadline() {
        let quota = map(
            primary: nil,
            secondary: nil,
            credits: CodexCredits(hasCredits: true, balance: "811.7749020000", unlimited: false)
        )

        XCTAssertNil(quota.headlineUsageLineId)
        XCTAssertEqual(quota.lines.map(\.id), ["credits"])
    }

    func testStartedWindowsCarryFixedPeriodDescriptorsWithReceiptTiming() {
        let quota = map(primary: fiveHour, secondary: weekly)

        XCTAssertEqual(quota.activityObservation?.metrics.map(\.forecastDescriptor), [
            descriptor(id: "primary-window-usage", minutes: 300),
            descriptor(id: "secondary-window-usage", minutes: 10080),
        ])
    }

    func testAWindowWithoutAResetOrALengthCarriesNoDescriptor() {
        let quota = map(
            primary: CodexRateLimitWindow(usedPercent: 12, resetsAt: nil, windowDurationMins: 300),
            secondary: CodexRateLimitWindow(usedPercent: 38, resetsAt: weekly.resetsAt, windowDurationMins: nil)
        )

        XCTAssertEqual(quota.activityObservation?.metrics.map(\.value), [.number(12), .number(38)])
        XCTAssertEqual(quota.activityObservation?.metrics.map(\.forecastDescriptor), [nil, nil])
    }

    /// An unused window resets 300 minutes after each read. A read one second
    /// late moves the reset past the 5-minute tolerance.
    func testAnUnusedWindowCarriesNoDescriptorAndItsMovingResetIsNoChange() {
        var policy = SmartRefreshPolicy()
        var classifications: [SmartRefreshPolicy.Classification] = []

        for elapsed in [0, 301, 602] as [TimeInterval] {
            let readAt = receivedAt.addingTimeInterval(elapsed)
            let unused = CodexRateLimitWindow(
                usedPercent: 0,
                resetsAt: readAt.timeIntervalSince1970 + 300 * 60,
                windowDurationMins: 300
            )
            let quota = map(primary: unused, secondary: weekly, readAt: readAt)

            XCTAssertNil(quota.activityObservation?.metrics.first?.forecastDescriptor)
            let decision = policy.recordSuccess(
                quota,
                for: OpenAICodexProvider.providerId,
                at: elapsed,
                quietWindow: 300
            )
            classifications.append(decision.classification)
        }

        XCTAssertEqual(classifications, [.baseline, .unchanged, .unchanged])
    }

    private func map(
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?,
        credits: CodexCredits? = nil,
        readAt: Date? = nil
    ) -> ProviderQuota {
        OpenAICodexProvider().map(
            CodexRateLimitReadResult(
                rateLimits: nil,
                rateLimitsByLimitId: [
                    "codex": CodexRateLimitSnapshot(primary: primary, secondary: secondary, credits: credits),
                ]
            ),
            receivedAt: readAt ?? receivedAt
        )
    }

    private func descriptor(id: String, minutes: Int) -> AllowanceForecastDescriptor {
        let length = TimeInterval(minutes * 60)
        return AllowanceForecastDescriptor(
            accounting: .fixedPeriod(limit: 100, resetsAt: receivedAt.addingTimeInterval(length), length: length),
            unit: .percentagePoints,
            resolution: 1,
            timing: .receipt(receivedAt),
            usageLineId: id
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

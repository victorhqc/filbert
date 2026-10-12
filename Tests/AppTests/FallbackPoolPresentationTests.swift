@testable import App
import Core
import XCTest

final class FallbackPoolPresentationTests: FallbackPoolTestCase {
    private let promoted: Set<String> = ["credits"]

    func testThePromotedLayoutLeadsWithThePoolAndMovesExhaustedLinesUnderIt() throws {
        let layout = try XCTUnwrap(FallbackPoolLayout(
            lines: quota(fiveHour: 100, credits: decimal("803.74")).lines,
            promotedPoolIds: promoted
        ))

        XCTAssertEqual(layout.pool.id, "credits")
        XCTAssertEqual(layout.exhaustedLines.map(\.id), ["five-hour"])
        XCTAssertEqual(layout.otherLines.map(\.id), ["weekly"])
        let detail = try XCTUnwrap(layout.poolLine().details?.last)
        XCTAssertEqual(detail.label, "5-hour window")
        XCTAssertEqual(detail.value, "Limit reached · \(QuotaFormatting.countdown(to: fiveHourReset))")
    }

    func testThereIsNoPromotedLayoutWithoutPromotionOrOnceTheGroupRecovers() {
        XCTAssertNil(FallbackPoolLayout(lines: quota(fiveHour: 100, credits: 800).lines, promotedPoolIds: []))
        XCTAssertNil(FallbackPoolLayout(lines: quota(fiveHour: 0, credits: 800).lines, promotedPoolIds: promoted))
    }

    func testAPassedResetWithoutANewMeasurementKeepsThePromotedLayout() throws {
        let passed = quota(fiveHour: 100, credits: 800).lines.map { line in
            line.id == "five-hour"
                ? UsageLine(
                    label: line.label,
                    percentage: 100,
                    resetDate: now.addingTimeInterval(-60),
                    id: line.id,
                    limitGroup: line.limitGroup
                )
                : line
        }

        let layout = try XCTUnwrap(FallbackPoolLayout(lines: passed, promotedPoolIds: promoted))

        XCTAssertEqual(layout.poolLine().details?.last?.value, "Limit reached · resetting…")
    }

    func testAPromotedCreditsPoolShowsItsAmountWithoutATier() {
        let quota = quota(fiveHour: 100, credits: decimal("803.74"))
        let amount = UsageAmountFormatting.string(
            for: UsageBalance(amount: .finite(decimal("803.74")), unit: .credits)
        )

        let status = QuotaStatusResolver.resolve(for: quota, promotedPoolIds: promoted)

        XCTAssertEqual(status, .credits(formattedAmount: amount))
        XCTAssertNil(QuotaStatusResolver.tier(for: status))
        XCTAssertNil(QuotaStatusResolver.compactTier(for: quota, promotedPoolIds: promoted, at: now))
    }

    func testWithoutPromotionTheExhaustedWindowStillDrivesTheStatus() {
        let quota = quota(fiveHour: 100, credits: 800)

        XCTAssertEqual(QuotaStatusResolver.resolve(for: quota), .window(percentage: 100))
    }

    func testAPromotedCurrencyPoolKeepsItsBalanceTier() throws {
        let amount = try XCTUnwrap(Decimal(string: "12.5"))
        let lines = [
            UsageLine(label: "Plan", percentage: 100, id: "plan", limitGroup: "plan"),
            UsageLine(
                label: "Balance",
                balance: UsageBalance(amount: .finite(amount), unit: .currency("USD")),
                id: "balance",
                fallbackForLimitGroup: "plan"
            ),
        ]
        let quota = ProviderQuota(
            providerId: "money",
            providerName: "Money",
            headline: "",
            lines: lines,
            lastUpdated: now
        )

        let status = QuotaStatusResolver.resolve(for: quota, promotedPoolIds: ["balance"])

        guard case let .balance(value, _) = status else {
            return XCTFail("Expected a balance status, got \(status)")
        }
        XCTAssertEqual(value, 12.5)
        XCTAssertNotNil(QuotaStatusResolver.tier(for: status))
    }

    func testTheMenuBarNamesTheCreditsInUse() throws {
        let resolved = try XCTUnwrap(MenuBarProviderPresentation.resolve(
            providerInfo: codexInfo(),
            providerState: .loaded(quota(fiveHour: 100, credits: decimal("803.74"))),
            isFastRefreshActive: false,
            promotedPoolIds: promoted
        ))

        let label = MenuBarProviderPresentation.accessibilityLabel(for: resolved)

        XCTAssertTrue(label.hasPrefix("OpenAI Codex: "), label)
        XCTAssertTrue(label.hasSuffix(" credits remaining"), label)
        XCTAssertNil(MenuBarStatusVisual.statusImage(for: resolved.status, isVintageMacEnabled: false))
    }

    func testThePromotedHeadlineSpeaksForThePoolWithItsEstimate() throws {
        let presentation = present(credits: estimated(remaining: 4 * 60 * 60, span: 10 * 60))

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.label, "Credits")
        let remaining = CoarseDurationFormatting.string(from: 4 * 60 * 60)
        XCTAssertEqual(headline.status, "About \(remaining) of use remaining")
        XCTAssertEqual(headline.detail, "Based on the last \(CoarseDurationFormatting.evidenceSpan(10 * 60))")
        XCTAssertEqual(Array(headline.accessibilitySentences.prefix(2)), [
            "Using Credits",
            "5-hour window limit reached, \(QuotaFormatting.countdown(to: fiveHourReset))",
        ])
        XCTAssertNil(presentation.rowLines["credits"])
        XCTAssertNotNil(presentation.rowLines["weekly"])
    }

    func testAPromotedPoolWithoutAnEstimateShowsItsAmountAndLearnsInItsRow() throws {
        let learning = AllowanceForecast(usageLineId: "credits", state: .learning, observedAt: now)
        let presentation = present(credits: learning)

        let headline = try XCTUnwrap(presentation.headline)
        XCTAssertEqual(headline.label, "Credits")
        XCTAssertNil(headline.status)
        XCTAssertNil(headline.detail)
        XCTAssertEqual(presentation.rowLines["credits"]?.text, "Learning your usage rate…")
    }

    private func present(credits forecast: AllowanceForecast) -> AllowanceForecastPresentation {
        let quota = quota(fiveHour: 100, credits: decimal("803.74"))
        return AllowanceForecastPresentation(
            quota: quota,
            forecasts: [
                "credits": forecast,
                "weekly": AllowanceForecast(
                    usageLineId: "weekly",
                    state: .estimated(depletesAt: now.addingTimeInterval(18 * 60 * 60)),
                    observedAt: now,
                    evidenceSpan: 35 * 60 * 60,
                    pace: .periodAverage
                ),
            ],
            now: now,
            fallbackPool: FallbackPoolLayout(lines: quota.lines, promotedPoolIds: promoted)
        )
    }

    private func codexInfo() -> ProviderInfo {
        ProviderInfo(
            id: providerId,
            displayName: "OpenAI Codex",
            glyph: .sfSymbol("sparkles"),
            description: "Test provider",
            defaultBaseURL: URL(string: "https://example.com")!,
            authShape: .apiKeyFree
        )
    }

    private func estimated(remaining: TimeInterval, span: TimeInterval) -> AllowanceForecast {
        AllowanceForecast(
            usageLineId: "credits",
            state: .estimated(depletesAt: now.addingTimeInterval(remaining)),
            observedAt: now,
            evidenceSpan: span
        )
    }
}

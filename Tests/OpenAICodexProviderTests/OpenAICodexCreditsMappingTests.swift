import Core
import Foundation
@testable import OpenAICodexProvider
import XCTest

final class OpenAICodexCreditsMappingTests: XCTestCase {
    private let receivedAt = Date(timeIntervalSince1970: 1_791_823_058)

    func testCreditsAreTheirOwnRowAfterTheWindows() {
        let quota = map(credits: credits(balance: "811.7749020000"))

        XCTAssertEqual(quota.lines.map(\.id), ["primary-window-usage", "secondary-window-usage", "credits"])
        XCTAssertTrue(quota.lines.allSatisfy { $0.details == nil })
        let row = quota.lines[2]
        XCTAssertEqual(row.label, "Credits")
        XCTAssertEqual(row.balance, UsageBalance(amount: .finite(decimal("811.774902")), unit: .credits))
        XCTAssertNil(row.limitGroup)
        XCTAssertEqual(row.fallbackForLimitGroup, "subscription")
        XCTAssertEqual(quota.headlineUsageLineId, "primary-window-usage")
    }

    func testTheCreditsRowCarriesNothingThatRanksAProvider() {
        let row = map(credits: credits(balance: "12.5")).lines[2]

        XCTAssertNil(row.percentage)
        XCTAssertNil(row.used)
        XCTAssertNil(row.total)
        XCTAssertNil(row.unit)
        XCTAssertEqual(row.balance?.unit, .credits)
    }

    func testFiniteCreditsCarryABalanceDescriptorWithReceiptTiming() throws {
        let metric = try XCTUnwrap(creditsMetric(in: map(credits: credits(balance: "811.7749020000"))))

        XCTAssertEqual(metric.kind, .credits)
        XCTAssertEqual(metric.value, .number(decimal("811.774902")))
        XCTAssertEqual(metric.forecastDescriptor, AllowanceForecastDescriptor(
            accounting: .balance,
            unit: .credits,
            resolution: decimal("0.0000000001"),
            timing: .receipt(receivedAt),
            usageLineId: "credits"
        ))
    }

    func testTheResolutionStaysFixedWhateverTheDecimalsOfTheBalance() {
        let balances = ["80", "12.5", "1159.5692275000"]

        let metrics = balances.compactMap { creditsMetric(in: map(credits: credits(balance: $0))) }

        XCTAssertEqual(metrics.map(\.value), [.number(80), .number(decimal("12.5")), .number(decimal("1159.5692275"))])
        XCTAssertEqual(Set(metrics.map(\.forecastDescriptor?.resolution)), [decimal("0.0000000001")])
    }

    func testACreditPurchaseKeepsTheSameDescriptor() {
        let before = creditsMetric(in: map(credits: credits(balance: "80")))?.forecastDescriptor
        let after = creditsMetric(in: map(credits: credits(balance: "1080")))?.forecastDescriptor

        XCTAssertNotNil(before)
        XCTAssertEqual(before, after)
    }

    func testUnlimitedCreditsShowUnlimitedWithoutADescriptor() {
        for hasCredits in [true, false, nil] {
            let quota = map(credits: CodexCredits(hasCredits: hasCredits, balance: nil, unlimited: true))

            XCTAssertEqual(quota.lines.last?.balance, UsageBalance(amount: .unlimited, unit: .credits))
            XCTAssertEqual(
                creditsMetric(in: quota),
                ProviderActivityMetric(id: "credits", kind: .credits, value: .discrete("unlimited"))
            )
        }
    }

    func testAbsentCreditsAndCreditsTheAccountDoesNotHaveProduceNoRow() {
        let snapshots: [CodexCredits?] = [
            nil,
            CodexCredits(hasCredits: false, balance: "0", unlimited: false),
            CodexCredits(hasCredits: false, balance: "0", unlimited: nil),
            CodexCredits(hasCredits: true, balance: nil, unlimited: false),
        ]

        for snapshot in snapshots {
            let quota = map(credits: snapshot)

            XCTAssertEqual(quota.lines.map(\.id), ["primary-window-usage", "secondary-window-usage"])
            XCTAssertNil(creditsMetric(in: quota))
        }
    }

    func testAResponseWithoutHasCreditsShowsItsBalance() {
        let quota = map(credits: CodexCredits(hasCredits: nil, balance: "12.5", unlimited: nil))

        XCTAssertEqual(quota.lines.last?.balance, UsageBalance(amount: .finite(decimal("12.5")), unit: .credits))
        XCTAssertNotNil(creditsMetric(in: quota)?.forecastDescriptor)
    }

    func testAnUnparseableBalanceShowsTheRawStringWithoutAMetric() {
        for raw in ["1,159.57", "12.5 credits", "unknown"] {
            let row = map(credits: credits(balance: raw)).lines.last

            XCTAssertEqual(row?.id, "credits")
            XCTAssertNil(row?.balance)
            XCTAssertEqual(row?.details?.map(\.value), [raw])
            XCTAssertNil(creditsMetric(in: map(credits: credits(balance: raw))))
        }
    }

    private func map(credits: CodexCredits?) -> ProviderQuota {
        let fiveHour = CodexRateLimitWindow(usedPercent: 12, resetsAt: 1_791_841_058, windowDurationMins: 300)
        let weekly = CodexRateLimitWindow(usedPercent: 38, resetsAt: 1_792_317_872, windowDurationMins: 10080)
        return OpenAICodexProvider().map(
            CodexRateLimitReadResult(
                rateLimits: CodexRateLimitSnapshot(primary: fiveHour, secondary: weekly, credits: credits),
                rateLimitsByLimitId: nil
            ),
            receivedAt: receivedAt
        )
    }

    private func credits(balance: String) -> CodexCredits {
        CodexCredits(hasCredits: true, balance: balance, unlimited: false)
    }

    private func creditsMetric(in quota: ProviderQuota) -> ProviderActivityMetric? {
        quota.activityObservation?.metrics.first { $0.id == "credits" }
    }

    private func decimal(_ value: String) -> Decimal {
        Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))!
    }
}

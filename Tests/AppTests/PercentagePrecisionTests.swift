@testable import App
import Core
import XCTest

final class PercentagePrecisionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        super.tearDown()
    }

    func testPercentagesShowTheRequestedDecimals() {
        XCTAssertEqual(QuotaFormatting.percentage(43.72), "44%")
        XCTAssertEqual(QuotaFormatting.percentage(43.72, fractionLength: 2), "43.72%")
        XCTAssertEqual(QuotaFormatting.percentage(3.3, fractionLength: 2), "3.30%")
        XCTAssertEqual(QuotaFormatting.percentage(100, fractionLength: 2), "100.00%")
    }

    func testPacedRowUsedTextFollowsTheLine() throws {
        XCTAssertEqual(try pacedText(fractionLength: 0).used, "44% used")
        XCTAssertEqual(try pacedText(fractionLength: 2).used, "43.72% used")
    }

    func testPacedRowAllowanceKeepsItsPrecision() throws {
        XCTAssertEqual(try pacedText(fractionLength: 2).allowance, try pacedText(fractionLength: 0).allowance)
    }

    func testLimitReachedHeadlineFollowsTheLine() {
        XCTAssertEqual(limitReachedHeadlineValue(fractionLength: 0), "100%")
        XCTAssertEqual(limitReachedHeadlineValue(fractionLength: 2), "100.00%")
    }

    private func line(fractionLength: Int) -> UsageLine {
        UsageLine(
            label: DisplayText(verbatim: "Monthly"),
            percentage: 43.72,
            percentageFractionLength: fractionLength,
            resetDate: now.addingTimeInterval(10 * 24 * 3600),
            windowDuration: UsageWindowDuration.month
        )
    }

    private func limitReachedHeadlineValue(fractionLength: Int) -> String? {
        let line = UsageLine(
            label: DisplayText(verbatim: "5-hour window"),
            percentage: 100,
            percentageFractionLength: fractionLength,
            id: "five-hour"
        )
        let quota = ProviderQuota(
            providerId: "provider",
            providerName: "Provider",
            headline: DisplayText(verbatim: "100%"),
            lines: [line],
            lastUpdated: now,
            headlineUsageLineId: "five-hour"
        )
        return AllowanceForecastPresentation(quota: quota, forecasts: [:], now: now).headline?.value
    }

    private func pacedText(fractionLength: Int) throws -> PacedUsageLineText {
        let pace = try XCTUnwrap(BudgetPace(line: line(fractionLength: fractionLength), now: now))
        return PacedUsageLineText(pace: pace, forecast: nil)
    }
}

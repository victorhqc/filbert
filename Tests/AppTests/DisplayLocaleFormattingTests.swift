@testable import App
import Core
import Foundation
import XCTest

final class DisplayLocaleFormattingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "de-DE"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "de_DE") }
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        super.tearDown()
    }

    func testDurationsUseTheDisplayLanguage() {
        XCTAssertEqual(CoarseDurationFormatting.string(from: 80 * 60, unitsStyle: .full), "1 Stunde und 20 Minuten")
        XCTAssertEqual(CoarseDurationFormatting.evidenceSpan(20 * 60), "20 Minuten")
        XCTAssertEqual(refreshDurationText(30), "30 Sekunden")
        XCTAssertEqual(refreshDurationText(5 * 60), "5 Minuten")
    }

    func testNumbersUseTheDisplayLanguage() throws {
        XCTAssertEqual(QuotaFormatting.percentage(42), "42\u{00A0}%")
        XCTAssertEqual(PeakHoursPresentation.rateText(for: .multiplier(2)), "2× Multiplikator")
        let amount = try XCTUnwrap(Decimal(string: "1159.57"))
        let credits = UsageBalance(amount: .finite(amount), unit: .credits)
        XCTAssertEqual(UsageAmountFormatting.string(for: credits), "1.159,57")
    }

    func testWeekdaysUseTheDisplayLanguage() {
        XCTAssertEqual(PeakHoursPresentation.weekdayRangeText(for: [2, 3, 4, 5, 6]), "Mo.–Fr.")
        XCTAssertEqual(PeakHoursPresentation.weekdayRangeText(for: [1, 7]), "So. und Sa.")
    }

    func testALanguageSwitchKeepsTheRegionFormats() {
        DisplayLanguage.selectedLanguageCode = "es-MX"

        XCTAssertEqual(refreshDurationText(30), "30 segundos")
        XCTAssertEqual(QuotaFormatting.percentage(42), "42\u{00A0}%")
    }
}

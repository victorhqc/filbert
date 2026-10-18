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

    func testCountedStringsAgreeWithTheCount() {
        let expected = [
            "en": ["1 second", "2 seconds", "1 minute", "2 minutes", "5 minutes", "21 minutes"],
            "de-DE": ["1 Sekunde", "2 Sekunden", "1 Minute", "2 Minuten", "5 Minuten", "21 Minuten"],
            "es-MX": ["1 segundo", "2 segundos", "1 minuto", "2 minutos", "5 minutos", "21 minutos"],
            "es-ES": ["1 segundo", "2 segundos", "1 minuto", "2 minutos", "5 minutos", "21 minutos"],
            "pt-BR": ["1 segundo", "2 segundos", "1 minuto", "2 minutos", "5 minutos", "21 minutos"],
            "pt-PT": ["1 segundo", "2 segundos", "1 minuto", "2 minutos", "5 minutos", "21 minutos"],
            "ru": ["1 секунда", "2 секунды", "1 минута", "2 минуты", "5 минут", "21 минута"],
            "zh-Hans": ["1 秒", "2 秒", "1 分钟", "2 分钟", "5 分钟", "21 分钟"],
        ]
        for (language, texts) in expected {
            DisplayLanguage.selectedLanguageCode = language
            let shown = [1, 2, 60, 120, 300, 21 * 60].map { refreshDurationText(TimeInterval($0)) }
            XCTAssertEqual(shown, texts, language)
        }
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

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

    func testDurationsOfAWeekOrMoreUseDays() {
        let expected = ["en": "9d", "de-DE": "9d", "ru": "9 д.", "zh-Hans": "9天", "ja": "9日"]
        for (language, text) in expected {
            DisplayLanguage.selectedLanguageCode = language

            XCTAssertEqual(CoarseDurationFormatting.string(from: 9 * 24 * 3600 + 3600), text, language)
        }
    }

    func testRefreshIntervalsAgreeWithTheCount() {
        let expected = [
            "en": ["every second", "every 30 seconds", "every minute", "every 5 minutes"],
            "de-DE": ["jede Sekunde", "alle 30 Sekunden", "jede Minute", "alle 5 Minuten"],
            "ru": ["раз в 1 секунду", "раз в 30 секунд", "раз в 1 минуту", "раз в 5 минут"],
            "ja": ["1秒ごと", "30秒ごと", "1分ごと", "5分ごと"],
        ]
        for (language, texts) in expected {
            DisplayLanguage.selectedLanguageCode = language
            let shown = [1, 30, 60, 300].map { refreshIntervalText(TimeInterval($0)) }
            XCTAssertEqual(shown, texts, language)
        }
        DisplayLanguage.selectedLanguageCode = "ru"
        XCTAssertEqual(refreshIntervalText(21 * 60), "раз в 21 минуту")
    }

    func testRangesUseEachLanguagesRangeForm() {
        let expected = ["de-DE": "Mo.–Fr.", "zh-Hans": "周一至周五", "ja": "月〜金"]
        for (language, text) in expected {
            DisplayLanguage.selectedLanguageCode = language

            XCTAssertEqual(PeakHoursPresentation.weekdayRangeText(for: [2, 3, 4, 5, 6]), text, language)
        }
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
            "ja": ["1秒", "2秒", "1分", "2分", "5分", "21分"],
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

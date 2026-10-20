import Core
import Foundation
import XCTest
@testable import ZAIProvider

final class ZAIWindowLabelTests: XCTestCase {
    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        super.tearDown()
    }

    func testTheHourWindowAgreesWithTheCount() {
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        let expected = [
            "en": ["1-hour window", "5-hour window"],
            "de-DE": ["1-Stunden-Fenster", "5-Stunden-Fenster"],
            "es-MX": ["Ventana de 1 hora", "Ventana de 5 horas"],
            "es-ES": ["Ventana de 1 hora", "Ventana de 5 horas"],
            "pt-BR": ["Janela de 1 hora", "Janela de 5 horas"],
            "pt-PT": ["Janela de 1 hora", "Janela de 5 horas"],
            "ru": ["1-часовое окно", "5-часовое окно"],
            "zh-Hans": ["1 小时窗口", "5 小时窗口"],
            "zh-Hant": ["1小時時段", "5小時時段"],
            "ja": ["1時間枠", "5時間枠"],
        ]
        for (language, labels) in expected {
            DisplayLanguage.selectedLanguageCode = language
            XCTAssertEqual([1, 5].map(hourWindowLabel), labels, language)
        }
    }

    private func hourWindowLabel(_ hours: Int) -> String? {
        let limit = ZAILimit(
            type: ZAILimitType.tokens.rawValue,
            unit: 3,
            number: hours,
            percentage: nil,
            usage: nil,
            currentValue: nil,
            remaining: nil,
            nextResetTime: nil,
            usageDetails: nil
        )
        return ZAIWindowDescriptor.recognize(limit)?.label.resolved
    }
}

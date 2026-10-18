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

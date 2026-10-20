@testable import Core
import XCTest

final class DisplayLanguageTests: XCTestCase {
    private let available = ["en", "de-DE", "es-ES", "es-MX", "pt-BR", "pt-PT", "ru", "zh-Hans", "zh-Hant", "ja"]

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        DisplayLanguage.setSystemPreferences { Locale.preferredLanguages }
        super.tearDown()
    }

    func testSystemOrder_skipsUnsupportedLanguages() {
        let locale = resolve(selectedLanguageCode: nil, preferences: ["fr-FR", "es-MX"])

        assertLanguage(locale, "es-MX")
    }

    func testSelection_overridesSystemOrder() {
        let locale = resolve(selectedLanguageCode: "ru", preferences: ["de-DE"])

        assertLanguage(locale, "ru")
    }

    func testSelection_keepsTheMacOSRegion() {
        let locale = resolve(selectedLanguageCode: "es-MX", preferences: [], current: Locale(identifier: "de_DE"))

        assertLanguage(locale, "es-MX")
        XCTAssertEqual(locale.region, Locale.Region("DE"))
    }

    func testRegionalVariants_matchTheirCatalogLanguage() {
        let expected = [
            "es": "es-ES", "es-ES": "es-ES", "es-MX": "es-MX", "es-419": "es-MX",
            "pt": "pt-BR", "pt-BR": "pt-BR", "pt-PT": "pt-PT",
            "ru-RU": "ru", "zh-Hans-CN": "zh-Hans", "zh-CN": "zh-Hans", "zh-SG": "zh-Hans",
            "zh-Hant": "zh-Hant", "zh-Hant-TW": "zh-Hant", "zh-TW": "zh-Hant", "zh-HK": "zh-Hant", "zh-MO": "zh-Hant",
            "ja": "ja", "ja-JP": "ja", "en-JP": "en",
        ]
        for (preferred, shown) in expected {
            assertLanguage(resolve(selectedLanguageCode: nil, preferences: [preferred]), shown)
        }
    }

    func testUnsupportedLanguage_fallsBackToEnglish() {
        for preferred in ["fr", "fr-CA"] {
            assertLanguage(resolve(selectedLanguageCode: nil, preferences: [preferred]), "en")
        }
        assertLanguage(resolve(selectedLanguageCode: "fr", preferences: []), "en")
    }

    func testLookup_findsEachNewLanguage() {
        let expected = [
            "pt-BR": "redefinindo…", "pt-PT": "a repor…", "ru": "сброс…", "zh-Hans": "正在重置…", "zh-Hant": "正在重設⋯",
            "ja": "リセット中…",
        ]
        for (language, text) in expected {
            DisplayLanguage.selectedLanguageCode = language
            XCTAssertEqual(QuotaFormatting.countdown(to: .distantPast), text, language)
        }
    }

    func testResetCountdownsShowTheTimeLeftInEachLanguage() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let expected = [
            "en": "resets in 2 hours",
            "de-DE": "noch 2 Stunden bis zum Zurücksetzen",
            "es-ES": "2 horas para restablecerse",
            "es-MX": "2 horas para restablecerse",
            "pt-BR": "redefinição em 2 horas",
            "pt-PT": "repõe-se dentro de 2 horas",
            "ru": "до сброса 2 часа",
            "zh-Hans": "2小时后重置",
            "zh-Hant": "2小時後重設",
            "ja": "リセットまであと2時間",
        ]
        for (language, text) in expected {
            DisplayLanguage.selectedLanguageCode = language

            XCTAssertEqual(QuotaFormatting.countdown(to: now.addingTimeInterval(2 * 3600), now: now), text, language)
        }
    }

    func testResetCountdownsRoundToTheNearestSingleUnit() {
        DisplayLanguage.selectedLanguageCode = "en"
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let expected: [(TimeInterval, String)] = [
            (30, "resets in 1 minute"),
            (45 * 60, "resets in 45 minutes"),
            (59 * 60 + 30, "resets in 1 hour"),
            (100 * 60, "resets in 2 hours"),
            (23 * 3600 + 40 * 60, "resets in 1 day"),
            (6 * 86400 + 13 * 3600, "resets in 7 days"),
        ]
        for (remaining, text) in expected {
            XCTAssertEqual(QuotaFormatting.countdown(to: now.addingTimeInterval(remaining), now: now), text)
        }
    }

    func testRussianResetCountdownsKeepTheDurationInTheNominative() {
        DisplayLanguage.selectedLanguageCode = "ru"
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let expected: [(TimeInterval, String)] = [
            (60, "до сброса 1 минута"),
            (21 * 3600, "до сброса 21 час"),
            (6 * 86400, "до сброса 6 дней"),
        ]
        for (remaining, text) in expected {
            XCTAssertEqual(QuotaFormatting.countdown(to: now.addingTimeInterval(remaining), now: now), text)
        }
    }

    func testLookup_followsSelectionWithoutRelaunch() {
        DisplayLanguage.selectedLanguageCode = "de-DE"
        XCTAssertEqual(QuotaFormatting.countdown(to: .distantPast), "wird zurückgesetzt…")

        DisplayLanguage.selectedLanguageCode = "en"

        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        XCTAssertEqual(QuotaFormatting.countdown(to: .distantPast), "resetting…")
    }

    func testLookup_followsSystemOrderWithoutSelection() {
        DisplayLanguage.setSystemPreferences { ["fr-FR", "de-DE"] }

        XCTAssertEqual(
            ProviderSetupError.notSupported.errorDescription,
            "Dieser Anbieter unterstützt diese Aktion nicht."
        )
    }

    private func assertLanguage(_ locale: Locale, _ expected: String, line: UInt = #line) {
        XCTAssertEqual(
            locale.language.maximalIdentifier,
            Locale.Language(identifier: expected).maximalIdentifier,
            line: line
        )
    }

    private func resolve(
        selectedLanguageCode: String?,
        preferences: [String],
        current: Locale = Locale(identifier: "en_US")
    ) -> Locale {
        DisplayLanguage.resolve(
            selectedLanguageCode: selectedLanguageCode,
            preferences: preferences,
            available: available,
            current: current
        )
    }
}

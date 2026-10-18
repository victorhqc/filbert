@testable import Core
import XCTest

final class DisplayLanguageTests: XCTestCase {
    private let available = ["en", "de-DE", "es-ES", "es-MX", "pt-BR", "pt-PT", "ru", "zh-Hans", "ja"]

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
            "ru-RU": "ru", "zh-Hans-CN": "zh-Hans", "zh-CN": "zh-Hans",
            "ja": "ja", "ja-JP": "ja", "en-JP": "en",
        ]
        for (preferred, shown) in expected {
            assertLanguage(resolve(selectedLanguageCode: nil, preferences: [preferred]), shown)
        }
    }

    func testUnsupportedLanguage_fallsBackToEnglish() {
        for preferred in ["zh-Hant", "zh-Hant-TW", "zh-HK", "fr"] {
            assertLanguage(resolve(selectedLanguageCode: nil, preferences: [preferred]), "en")
        }
        assertLanguage(resolve(selectedLanguageCode: "fr", preferences: []), "en")
    }

    func testLookup_findsEachNewLanguage() {
        let expected = [
            "pt-BR": "redefinindo…", "pt-PT": "a repor…", "ru": "сброс…", "zh-Hans": "正在重置…", "ja": "リセット中…",
        ]
        for (language, text) in expected {
            DisplayLanguage.selectedLanguageCode = language
            XCTAssertEqual(QuotaFormatting.countdown(to: .distantPast), text, language)
        }
    }

    func testRelativeTime_joinsChineseWithoutASpace() {
        DisplayLanguage.selectedLanguageCode = "zh-Hans"

        let countdown = QuotaFormatting.countdown(to: Date().addingTimeInterval(2 * 3600 + 60))

        XCTAssertEqual(countdown, "2小时后重置")
    }

    func testRelativeTime_comesBeforeTheJapaneseVerb() {
        DisplayLanguage.selectedLanguageCode = "ja"

        let countdown = QuotaFormatting.countdown(to: Date().addingTimeInterval(2 * 3600 + 60))

        XCTAssertEqual(countdown, "2 時間後にリセット")
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

    func testRelativeTime_usesTheDisplayLanguage() {
        DisplayLanguage.selectedLanguageCode = "de-DE"

        let countdown = QuotaFormatting.countdown(to: Date().addingTimeInterval(2 * 3600 + 60))

        XCTAssertTrue(countdown.hasPrefix("zurückgesetzt in 2 Stunden"), countdown)
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

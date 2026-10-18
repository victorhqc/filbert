@testable import Core
import XCTest

final class DisplayLanguageTests: XCTestCase {
    private let available = ["en", "de-DE", "es-ES", "es-MX", "pt-BR", "pt-PT", "ru", "zh-Hans"]

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
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
        assertLanguage(resolve(selectedLanguageCode: nil, preferences: ["es"]), "es-ES")
        assertLanguage(resolve(selectedLanguageCode: nil, preferences: ["es-419"]), "es-MX")
        assertLanguage(resolve(selectedLanguageCode: nil, preferences: ["pt"]), "pt-BR")
        assertLanguage(resolve(selectedLanguageCode: nil, preferences: ["zh-Hans-CN"]), "zh-Hans")
    }

    func testUnsupportedLanguage_fallsBackToEnglish() {
        assertLanguage(resolve(selectedLanguageCode: nil, preferences: ["zh-Hant"]), "en")
        assertLanguage(resolve(selectedLanguageCode: "fr", preferences: []), "en")
    }

    func testLookup_followsSelectionWithoutRelaunch() {
        DisplayLanguage.selectedLanguageCode = "de-DE"
        XCTAssertEqual(QuotaFormatting.countdown(to: .distantPast), "wird zurückgesetzt…")

        DisplayLanguage.selectedLanguageCode = "en"
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

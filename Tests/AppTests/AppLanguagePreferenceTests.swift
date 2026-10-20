@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class AppLanguagePreferenceTests: XCTestCase {
    private let suiteName = "filbert-language-tests-\(UUID().uuidString)"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        DisplayLanguage.setSystemPreferences { Locale.preferredLanguages }
        super.tearDown()
    }

    func testAFreshInstallFollowsMacOSAndStoresNothing() {
        let model = makeModel(global: ["de-DE", "en-US"])

        XCTAssertNil(model.selectedLanguageCode)
        XCTAssertEqual(model.locale.language.languageCode, "de")
        XCTAssertNil(storedLanguages)
    }

    func testTheSelectionPersistsAcrossLaunches() {
        makeModel(global: ["en-US"]).select("de-DE")

        let relaunched = makeModel(global: ["en-US"])

        XCTAssertEqual(storedLanguages, ["de-DE"])
        XCTAssertEqual(relaunched.selectedLanguageCode, "de-DE")
        XCTAssertEqual(relaunched.locale.language.languageCode, "de")
    }

    func testSystemDefaultRemovesTheValueAndFollowsMacOSAtOnce() {
        let model = makeModel(global: ["es-MX", "en-US"])
        model.select("de-DE")

        model.select(nil)

        XCTAssertNil(storedLanguages)
        XCTAssertNil(model.selectedLanguageCode)
        XCTAssertEqual(model.locale.language.languageCode, "es")
    }

    func testAValueFromSystemSettingsShowsInThePicker() {
        defaults.set(["es-419"], forKey: AppLanguagePreference.key)

        let model = makeModel(global: ["en-US"])

        XCTAssertEqual(model.selectedLanguageCode, "es-MX")
    }

    func testAnUnsupportedStoredValueShowsSystemDefaultInEnglish() {
        defaults.set(["fr"], forKey: AppLanguagePreference.key)

        let model = makeModel(global: ["de-DE"])

        XCTAssertNil(model.selectedLanguageCode)
        XCTAssertEqual(model.locale.language.languageCode, "en")
    }

    func testWithoutABundleIdentifierTheSelectionLastsTheSession() {
        let preference = AppLanguagePreference(defaults: defaults, domainName: nil, globalLanguages: { ["en-US"] })
        let model = DisplayLanguageModel(preference: preference, notificationCenter: NotificationCenter())

        model.select("de-DE")

        XCTAssertEqual(model.locale.language.languageCode, "de")
        XCTAssertNil(storedLanguages)
    }

    func testTheRestartNoteShowsOnlyAfterAChangeThatPersists() {
        let model = makeModel(global: ["en-US"])
        XCTAssertFalse(model.changesSystemTextAtNextLaunch)

        model.select("de-DE")
        XCTAssertTrue(model.changesSystemTextAtNextLaunch)

        model.select(nil)
        XCTAssertFalse(model.changesSystemTextAtNextLaunch)

        let sessionOnly = DisplayLanguageModel(
            preference: AppLanguagePreference(defaults: defaults, domainName: nil, globalLanguages: { ["en-US"] }),
            notificationCenter: NotificationCenter()
        )
        sessionOnly.select("de-DE")
        XCTAssertFalse(sessionOnly.changesSystemTextAtNextLaunch)
    }

    func testThePickerListsEachLanguageInItsOwnName() {
        XCTAssertEqual(
            SupportedLanguage.all.map(\.autonym),
            [
                "English", "Deutsch", "Español (México)", "Español (España)",
                "Português (Brasil)", "Português (Portugal)", "Русский", "简体中文", "繁體中文", "日本語",
            ]
        )
    }

    func testTraditionalChineseFromSystemSettingsShowsInThePicker() {
        for stored in ["zh-Hant-TW", "zh-Hant-HK"] {
            defaults.set([stored], forKey: AppLanguagePreference.key)

            let model = makeModel(global: ["en-US"])

            XCTAssertEqual(model.selectedLanguageCode, "zh-Hant", stored)
        }
    }

    private var storedLanguages: [String]? {
        defaults.persistentDomain(forName: suiteName)?[AppLanguagePreference.key] as? [String]
    }

    @discardableResult
    private func makeModel(global: [String]) -> DisplayLanguageModel {
        let preference = AppLanguagePreference(defaults: defaults, domainName: suiteName, globalLanguages: { global })
        return DisplayLanguageModel(preference: preference, notificationCenter: NotificationCenter())
    }
}

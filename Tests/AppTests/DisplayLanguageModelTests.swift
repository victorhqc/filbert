@testable import App
import Core
import Foundation
import Observation
import XCTest

@MainActor
final class DisplayLanguageModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        DisplayLanguage.setSystemPreferences { Locale.preferredLanguages }
        super.tearDown()
    }

    func testSelectingALanguageChangesTheLocaleTheViewsRead() {
        let model = makeModel()
        let changed = expectation(description: "Views rebuild")
        withObservationTracking { _ = model.locale } onChange: { changed.fulfill() }

        model.select("de-DE")

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(model.locale.language.languageCode, "de")
        XCTAssertEqual(model.selectedLanguageCode, "de-DE")
        XCTAssertEqual(String(displayLocalized: "Refresh", bundle: .module), "Aktualisieren")
    }

    func testSelectingTheSameLanguageKeepsTheViews() {
        let model = makeModel()
        model.select("en")
        let changed = expectation(description: "Views rebuild")
        changed.isInverted = true
        withObservationTracking { _ = model.locale } onChange: { changed.fulfill() }

        model.select("en")

        wait(for: [changed], timeout: 0.1)
    }

    func testWithNoSelectionAMacOSLanguageChangeChangesTheLocale() {
        let center = NotificationCenter()
        let model = makeModel(notificationCenter: center)
        let changed = expectation(description: "Views rebuild")
        withObservationTracking { _ = model.locale } onChange: { changed.fulfill() }

        DisplayLanguage.setSystemPreferences { ["es-MX", "en-US"] }
        center.post(name: NSLocale.currentLocaleDidChangeNotification, object: nil)

        wait(for: [changed], timeout: 1)
        XCTAssertEqual(model.locale.language.maximalIdentifier, Locale.Language(identifier: "es-MX").maximalIdentifier)
    }

    private func makeModel(notificationCenter: NotificationCenter = NotificationCenter()) -> DisplayLanguageModel {
        let preference = AppLanguagePreference(domainName: nil, globalLanguages: { ["en-US"] })
        return DisplayLanguageModel(preference: preference, notificationCenter: notificationCenter)
    }
}

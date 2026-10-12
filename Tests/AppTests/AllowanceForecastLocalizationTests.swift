import Foundation
import XCTest

final class AllowanceForecastLocalizationTests: XCTestCase {
    private let forecastKeys = [
        "Forecast headline format",
        "Forecast labeled value format",
        "About %@ of use remaining",
        "Based on the last %@",
        "Not expected to run out",
        "before reset at recent pace",
        "About %1$@ of use remaining · last %2$@",
        "Not expected to run out before reset · last %@",
        "Learning your usage rate…",
        "No recent consumption detected",
        "Updates too far apart to estimate",
        "Forecast paused until fresh data arrives",
        "About %1$@ of use remaining at recent pace, based on the last %2$@",
        "Not expected to run out before reset at recent pace, based on the last %@",
        "Timing is approximate",
        "Limit reached",
        "Limit reached, no more use available until reset",
        "More than %@ of use remaining",
        "More than %1$@ of use remaining · last %2$@",
        "More than %1$@ of use remaining at recent pace, based on the last %2$@",
    ]

    func testEveryForecastStringIsTranslatedWithMatchingPlaceholders() throws {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../Sources/App/Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))

        for key in forecastKeys {
            let entry = try XCTUnwrap(catalog.strings[key], key)
            let english = try XCTUnwrap(entry.localizations["en"]?.stringUnit.value, key)
            for language in ["de-DE", "en", "es-ES", "es-MX"] {
                let unit = try XCTUnwrap(entry.localizations[language]?.stringUnit, "\(key) [\(language)]")
                XCTAssertEqual(unit.state, "translated", "\(key) [\(language)]")
                XCTAssertEqual(placeholders(in: unit.value), placeholders(in: english), "\(key) [\(language)]")
            }
        }
    }

    private func placeholders(in value: String) -> [String] {
        let pattern = #/%(\d\$)?@/#
        return value.matches(of: pattern).map { String($0.output.0) }.sorted()
    }
}

private struct Catalog: Decodable {
    let strings: [String: Entry]

    struct Entry: Decodable {
        let localizations: [String: Localization]
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit
    }

    struct StringUnit: Decodable {
        let state: String
        let value: String
    }
}

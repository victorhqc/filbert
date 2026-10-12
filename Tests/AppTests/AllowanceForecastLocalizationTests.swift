import Foundation
import XCTest

final class AllowanceForecastLocalizationTests: XCTestCase {
    private let forecastKeys = [
        "Forecast headline format",
        "About %@ of use remaining",
        "Based on the last %@",
        "Should last until reset",
        "At your pace over the last %@",
        "About %1$@ of use remaining · last %2$@",
        "Should last until reset · last %@",
        "Learning your usage rate…",
        "No recent consumption detected",
        "Updates too far apart to estimate",
        "Forecast paused until fresh data arrives",
        "About %1$@ of use remaining at recent pace, based on the last %2$@",
        "Should last until reset at your pace over the last %@",
        "Runs out in about %@",
        "At your average pace over the last %@",
        "Runs out in about %1$@ · last %2$@",
        "Runs out in about %1$@ at your average pace over the last %2$@",
        "Should last until reset at your average pace over the last %@",
        "Timing is approximate",
        "Limit reached",
        "Limit reached, no more use available until reset",
        "More than %@ of use remaining",
        "More than %1$@ of use remaining · last %2$@",
        "More than %1$@ of use remaining at recent pace, based on the last %2$@",
        "Promoted pool value format",
        "Using %@",
        "%@ limit reached",
        "%1$@ limit reached, %2$@",
        "Limit reached · %@",
        "%@: %@ credits remaining",
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

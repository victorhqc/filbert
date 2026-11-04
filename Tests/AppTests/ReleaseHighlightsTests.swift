@testable import App
import Foundation
import XCTest

final class ReleaseHighlightsTests: XCTestCase {
    func testReleaseVersionsAcceptOnlyPlainTripleNumbers() {
        XCTAssertEqual(ReleaseVersion("0.26.0")?.description, "0.26.0")
        XCTAssertNil(ReleaseVersion("0.26"))
        XCTAssertNil(ReleaseVersion("v0.26.0"))
        XCTAssertNil(ReleaseVersion("0.26.0-beta"))
        XCTAssertNil(ReleaseVersion("0.+1.0"))
        XCTAssertNil(ReleaseVersion("0..0"))
    }

    func testReleaseVersionsCompareNumerically() throws {
        try XCTAssertLessThan(XCTUnwrap(ReleaseVersion("0.9.0")), XCTUnwrap(ReleaseVersion("0.10.0")))
        try XCTAssertLessThan(XCTUnwrap(ReleaseVersion("0.26.9")), XCTUnwrap(ReleaseVersion("1.0.0")))
    }

    func testDecodedReleasesAreNewestFirst() throws {
        let highlights = try fixture()

        XCTAssertEqual(highlights.releases.map(\.version.description), ["0.26.0", "0.25.1", "0.25.0", "0.24.0"])
    }

    func testReleasesInARangeSkipEntriesWithNothingToShow() throws {
        let highlights = try fixture()

        let lower = try XCTUnwrap(ReleaseVersion("0.24.0"))
        let releases = highlights.releases(after: lower, through: ReleaseVersion("0.26.0"))

        XCTAssertEqual(releases.map(\.version.description), ["0.26.0", "0.25.0"])
    }

    func testRecentReleasesStopAtTheUpperVersionAndLimit() throws {
        let highlights = try fixture()

        XCTAssertEqual(
            highlights.recentReleases(through: ReleaseVersion("0.25.1"), limit: 3).map(\.version.description),
            ["0.25.0", "0.24.0"]
        )
        XCTAssertEqual(
            highlights.recentReleases(through: nil, limit: 1).map(\.version.description),
            ["0.26.0"]
        )
    }

    func testItemsSplitIntoFeaturesAndFixes() throws {
        let release = try XCTUnwrap(fixture().releases.first)

        XCTAssertEqual(release.features.count, 1)
        XCTAssertEqual(release.fixes.count, 1)
    }

    func testTextFollowsTheDisplayLanguageAndItsRegionalVariant() throws {
        let item = try XCTUnwrap(fixture().releases.first?.features.first)

        XCTAssertEqual(item.text(for: displayLocale("es-MX")), "Nueva función en México.")
        XCTAssertEqual(item.text(for: displayLocale("es-ES")), "Nueva función en España.")
        XCTAssertEqual(item.text(for: displayLocale("en")), "A new feature.")
    }

    func testEverySupportedLanguagePicksItsOwnText() {
        let codes = SupportedLanguage.all.map(\.code)
        let item = ReleaseHighlight(kind: .feature, text: Dictionary(uniqueKeysWithValues: codes.map { ($0, $0) }))

        for code in codes {
            XCTAssertEqual(item.text(for: displayLocale(code)), code)
        }
    }

    func testMissingLanguageFallsBackToEnglish() throws {
        let item = try XCTUnwrap(fixture().releases.first?.features.first)

        XCTAssertEqual(item.text(for: displayLocale("ja")), "A new feature.")
    }

    func testBundledHighlightsHaveEveryLanguage() {
        let languages = Set(SupportedLanguage.all.map(\.code))
        let releases = ReleaseHighlights.bundled.releases
        XCTAssertFalse(releases.isEmpty)

        var failures: [String] = []
        for release in releases {
            for (index, item) in release.items.enumerated() {
                let present = Set(item.text.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }.keys)
                let location = "\(release.version) item \(index)"
                failures += languages.subtracting(present).sorted().map { "\(location) lacks \($0)" }
                failures += present.subtracting(languages).sorted().map { "\(location) has \($0)" }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testBundledHighlightsFollowTheGlossary() {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        var failures: [String] = []
        for release in ReleaseHighlights.bundled.releases {
            for (index, item) in release.items.enumerated() {
                for (language, patterns) in StringCatalogCoverageTests.deniedTerms {
                    guard let value = item.text[language] else { continue }
                    failures += patterns
                        .filter { value.range(of: $0, options: options) != nil }
                        .map { "\(release.version) item \(index) in \(language) matches \($0)" }
                }
                let value = item.text["zh-Hant"] ?? ""
                if let traditional = StringCatalogCoverageTests.traditionalChineseCorrection(of: value) {
                    failures.append("\(release.version) item \(index) in zh-Hant: \(value) → \(traditional)")
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    /// Built as the display language builds it: the language from the selection, the region from macOS.
    private func displayLocale(_ languageCode: String) -> Locale {
        var components = Locale.Components(locale: Locale(identifier: "de_DE"))
        components.languageComponents = Locale.Language.Components(identifier: languageCode)
        components.region = Locale.Region("DE")
        return Locale(components: components)
    }

    private func fixture() throws -> ReleaseHighlights {
        try ReleaseHighlights(data: Data(#"""
        [
          {"version": "0.25.0", "items": [{"kind": "fix", "text": {"en": "A fix."}}]},
          {"version": "0.26.0", "items": [
            {"kind": "feature", "text": {
              "en": "A new feature.",
              "es-MX": "Nueva función en México.",
              "es-ES": "Nueva función en España."
            }},
            {"kind": "fix", "text": {"en": "Another fix."}}
          ]},
          {"version": "0.25.1", "items": []},
          {"version": "0.24.0", "items": [{"kind": "feature", "text": {"en": "An old feature."}}]}
        ]
        """#.utf8))
    }
}

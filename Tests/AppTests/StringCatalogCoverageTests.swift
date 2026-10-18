@testable import App
import Foundation
import XCTest

final class StringCatalogCoverageTests: XCTestCase {
    private let languages = SupportedLanguage.all.map(\.code)

    private let modules = [
        "Sources/Core",
        "Sources/App",
        "Sources/Providers/ClaudeCode",
        "Sources/Providers/Cursor",
        "Sources/Providers/DeepSeek",
        "Sources/Providers/GeminiCLI",
        "Sources/Providers/OpenAICodex",
        "Sources/Providers/OpenCodeGo",
        "Sources/Providers/ZAI",
    ].map { Module(sources: $0, catalog: "\($0)/Resources/Localizable.xcstrings") }

    private let bypassingLookups = [
        #"String\(\s*localized:"#,
        #"NSLocalizedString\("#,
        #"\b(Text|Button|Toggle|Label|Section|Picker|Link|Menu|LabeledContent|TextField|SecureField)\(\s*""#,
        #"\.(navigationTitle|help|accessibilityLabel|accessibilityHint|accessibilityValue)\(\s*""#,
    ]

    func testEveryLookupUsesTheDisplayLookupWithItsModuleBundle() throws {
        var failures: [String] = []
        for module in modules {
            for (file, source) in try sources(of: module) {
                for pattern in bypassingLookups {
                    for line in try lines(of: source, matching: pattern) {
                        failures.append("\(file):\(line) bypasses the display lookup")
                    }
                }
                failures += LocalizedSourceScanner.lookups(in: source, file: file)
                    .filter { !$0.arguments.contains("bundle: .module") }
                    .map { "\($0.location) does not pass bundle: .module" }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryKeyIsTranslatedInItsModuleCatalog() throws {
        var failures: [String] = []
        for module in modules {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url(module.catalog)))
            for (file, source) in try sources(of: module) {
                for lookup in LocalizedSourceScanner.lookups(in: source, file: file) {
                    guard let key = lookup.key else {
                        failures.append("\(lookup.location) has no literal key")
                        continue
                    }
                    guard let (catalogKey, entry) = catalog.strings.first(where: { key.matches($0.key) }) else {
                        failures.append("\(lookup.location) has no key in \(module.catalog)")
                        continue
                    }
                    failures += translationFailures(for: catalogKey, entry: entry, at: lookup.location)
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryCatalogKeyHasALookup() throws {
        var failures: [String] = []
        for module in modules {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url(module.catalog)))
            let keys = try sources(of: module).flatMap { file, source in
                LocalizedSourceScanner.lookups(in: source, file: file).compactMap(\.key)
            }
            failures += catalog.strings.keys.sorted()
                .filter { catalogKey in !keys.contains { $0.matches(catalogKey) } }
                .map { "\(module.catalog) \"\($0)\" has no lookup" }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    /// The deny lists in `docs/localization-glossary.md`.
    private let deniedTerms = [
        "es-MX": [
            #"\bajustes\b"#, #"\bordenador"#, #"\bañad"#, #"\bicono"#, #"\bcompr(?:ob|ueb)"#, #"\bhoras? punta\b"#,
            #"\b\w+(?:áis|éis)\b"#, #"\bvosotr"#, #"\bvuestr"#, #"\bllave de API\b"#, #"\brefresc"#,
            #"\bcoste\b"#, #"\b(?:el|del) Mac\b"#,
        ],
        "es-ES": [
            #"\bConfiguración del Sistema\b"#, #"\bcomputadora"#, #"\bagreg"#, #"\bícono"#, #"\bhoras? pico\b"#,
            #"\bla Mac\b"#, #"\bllave de API\b"#,
        ],
    ]

    func testEachSpanishVariantAvoidsTheOtherVariantsTerms() throws {
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        var failures: [String] = []
        for module in modules {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url(module.catalog)))
            for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
                for (language, patterns) in deniedTerms {
                    let values = entry.localizations?[language]?.units.map(\.value) ?? []
                    failures += patterns
                        .filter { pattern in values.contains { $0.range(of: pattern, options: options) != nil } }
                        .map { "\(module.catalog) \"\(key)\" in \(language) matches \($0)" }
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryCatalogLanguageIsSupported() throws {
        var failures: [String] = []
        for module in modules {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url(module.catalog)))
            let catalogLanguages = Set(catalog.strings.values.flatMap { $0.localizations?.keys ?? [:].keys })
            failures += catalogLanguages.subtracting(languages).sorted()
                .map { "\(module.catalog) has \($0), which SupportedLanguage does not list" }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    private func translationFailures(for key: String, entry: Catalog.Entry, at location: String) -> [String] {
        let english = entry.localizations?["en"]?.units.first?.value ?? key
        return languages.flatMap { language -> [String] in
            guard let units = entry.localizations?[language]?.units, !units.isEmpty else {
                return ["\(location) \"\(key)\" has no \(language) translation"]
            }
            return units.compactMap { unit in
                if unit.state != "translated" {
                    return "\(location) \"\(key)\" is not translated in \(language)"
                }
                if placeholders(in: unit.value) != placeholders(in: english) {
                    return "\(location) \"\(key)\" has different placeholders in \(language)"
                }
                return nil
            }
        }
    }

    /// Positional placeholders compare by position, so `%@ %lld` equals `%1$@ %2$lld`.
    private func placeholders(in value: String) -> [String] {
        let unescaped = value.replacingOccurrences(of: "%%", with: "")
        let matches = unescaped.matches(of: #/%(?:(\d+)\$)?(@|lld|ld|d|lf|f|llu|lu)/#)
        return matches.enumerated()
            .map { index, match in (position: match.output.1.flatMap { Int($0) } ?? index + 1, type: match.output.2) }
            .sorted { $0.position < $1.position }
            .map { String($0.type) }
    }

    private func sources(of module: Module) throws -> [(file: String, source: String)] {
        let root = url(module.sources)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        return try (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }
            .map { try ("\(module.sources)/\($0.path.dropFirst(root.path.count + 1))", String(contentsOf: $0)) }
    }

    /// Matches across line breaks, so a call split after `String(` is still found.
    private func lines(of source: String, matching pattern: String) throws -> [Int] {
        let code = source.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).hasPrefix("//") ? "" : $0 }
            .joined(separator: "\n")
        return try code.ranges(of: Regex(pattern)).map { match in
            code[..<match.lowerBound].filter { $0 == "\n" }.count + 1
        }
    }

    private func url(_ repositoryPath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../\(repositoryPath)")
            .standardizedFileURL
    }
}

private struct Module {
    let sources: String
    let catalog: String
}

private struct Catalog: Decodable {
    let strings: [String: Entry]

    struct Entry: Decodable {
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        let stringUnit: StringUnit?
        let variations: Variations?

        var units: [StringUnit] {
            [stringUnit].compactMap { $0 } + (variations?.plural?.values.map(\.stringUnit) ?? [])
        }
    }

    struct Variations: Decodable {
        let plural: [String: Variant]?
    }

    struct Variant: Decodable {
        let stringUnit: StringUnit
    }

    struct StringUnit: Decodable {
        let state: String
        let value: String
    }
}

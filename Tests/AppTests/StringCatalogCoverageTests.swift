import Foundation
import XCTest

final class StringCatalogCoverageTests: XCTestCase {
    private let languages = ["de-DE", "en", "es-ES", "es-MX"]

    private let modules = [
        Module(sources: "Sources/Core", catalog: "Sources/Core/Resources/Localizable.xcstrings"),
        Module(sources: "Sources/App", catalog: "Sources/App/Resources/Localizable.xcstrings"),
    ]

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
                    for line in lines(of: source, matching: pattern) {
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

    private func lines(of source: String, matching pattern: String) -> [Int] {
        source.components(separatedBy: "\n").enumerated()
            .filter { !$0.element.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .filter { $0.element.range(of: pattern, options: .regularExpression) != nil }
            .map { $0.offset + 1 }
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

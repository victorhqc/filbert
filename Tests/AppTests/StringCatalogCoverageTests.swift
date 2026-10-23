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
        "Sources/Providers/KimiAPI",
        "Sources/Providers/KimiCode",
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
        // Case-sensitive, because lowercase "sie" means "them".
        "de-DE": [#"(?-i)\b(?:Sie|Ihnen|Ihre?[mnrs]?)\b"#, #"\bnochmal\b"#],
        // Kana and kanji ranges, because ICU's \p{Han} also matches " · ".
        "ja": [
            "あなた", "[「」]", "[？！：]",
            #"[\u3040-\u30FF\u4E00-\u9FFF] [A-Za-z0-9%]"#, #"[A-Za-z0-9@] [\u3040-\u30FF\u4E00-\u9FFF]"#,
        ],
        "zh-Hant": [
            "設置", "默認", "菜單", "軟件", "信息", "網絡",
            "賬號", "賬戶", "屏幕", "程序", "數據", "服務器",
            "接口", "登錄", "質量", "優化", "鏈接", "用戶",
            "保存", "加載", "刷新", "充值", "窗口", "提供商",
            "密鑰", "激活", "運行", "實時", "在線", "緩存",
            "圖標", "智能", "按需", "點擊", "鑰匙串", "您",
            "[“”…]",
            #"[\u3400-\u9FFF][,?!:;()]"#, #"[,?!:;()][\u3400-\u9FFF]"#,
            #"[\u3400-\u9FFF] [A-Za-z0-9%]"#, #"[A-Za-z0-9@] [\u3400-\u9FFF]"#,
        ],
    ]

    /// Traditional characters that ICU's `Hans-Hant` transform changes anyway. Each one needs a source in
    /// `docs/localization-glossary.md`.
    private let traditionalChineseExceptions: Set<Character> = []

    func testTraditionalChineseHasNoSimplifiedCharacters() throws {
        var failures: [String] = []
        for module in modules {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url(module.catalog)))
            for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
                for value in entry.localizations?["zh-Hant"]?.units.map(\.value) ?? [] {
                    // ICU converts some characters only in context (周 alone stays, 周一 becomes 週一).
                    let traditional = value.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? value
                    let changed = zip(value, traditional).filter { original, converted in
                        original != converted && !traditionalChineseExceptions.contains(original)
                    }
                    if value.count != traditional.count || !changed.isEmpty {
                        failures.append("\(module.catalog) \"\(key)\" in zh-Hant: \(value) → \(traditional)")
                    }
                }
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    func testEveryLanguageAvoidsItsDeniedTerms() throws {
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

    /// The CLDR plural categories that integer counts reach in each language.
    private let pluralForms: [String: Set<String>] = [
        "ru": ["one", "few", "many", "other"],
        "zh-Hans": ["other"],
        "zh-Hant": ["other"],
        "ja": ["other"],
    ]

    /// Languages whose `one` category holds only the count 1, so its form may say "every minute" without the number.
    /// In Russian `one` also holds 21, 31, and 41, so its form must keep the count.
    private let languagesWhereOneIsOnlyOne: Set = ["en", "de-DE", "es-ES", "es-MX", "pt-BR", "pt-PT"]

    func testEveryPluralHasTheFormsItsLanguageNeeds() throws {
        var failures: [String] = []
        for module in modules {
            let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url(module.catalog)))
            for (key, entry) in catalog.strings.sorted(by: { $0.key < $1.key }) {
                for (language, localization) in entry.localizations ?? [:] {
                    guard let plural = localization.variations?.plural else { continue }
                    let needed = pluralForms[language] ?? ["one", "other"]
                    let missing = needed.subtracting(plural.keys).sorted()
                    if !missing.isEmpty {
                        failures.append("\(module.catalog) \"\(key)\" in \(language) lacks \(missing)")
                    }
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
        let english = entry.localizations?["en"]?.otherUnit?.value ?? key
        return languages.flatMap { language -> [String] in
            guard let forms = entry.localizations?[language]?.forms, !forms.isEmpty else {
                return ["\(location) \"\(key)\" has no \(language) translation"]
            }
            return forms.compactMap { category, unit in
                if unit.state != "translated" {
                    return "\(location) \"\(key)\" is not translated in \(language)"
                }
                let mayOmitCount = category == "one" && languagesWhereOneIsOnlyOne.contains(language)
                    && placeholders(in: unit.value).isEmpty
                if !mayOmitCount, placeholders(in: unit.value) != placeholders(in: english) {
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
            forms.map(\.unit)
        }

        var forms: [(category: String?, unit: StringUnit)] {
            [stringUnit].compactMap { $0 }.map { (nil, $0) }
                + (variations?.plural?.map { ($0.key, $0.value.stringUnit) } ?? [])
        }

        var otherUnit: StringUnit? {
            stringUnit ?? variations?.plural?["other"]?.stringUnit
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

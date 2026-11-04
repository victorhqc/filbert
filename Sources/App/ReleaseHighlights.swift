import Foundation

struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    private let components: [Int]

    init?(_ rawVersion: String) {
        let parts = rawVersion.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { part in
            part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil
        }
        guard parts.count == 3, numbers.count == 3 else {
            return nil
        }
        components = numbers
    }

    var description: String {
        components.map(String.init).joined(separator: ".")
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

struct ReleaseHighlights: Equatable, Sendable {
    static let fallbackLanguage = "en"

    struct Release: Equatable, Identifiable, Sendable {
        let version: ReleaseVersion
        let items: [ReleaseHighlight]

        var id: ReleaseVersion {
            version
        }

        var features: [ReleaseHighlight] {
            items.filter { $0.kind == .feature }
        }

        var fixes: [ReleaseHighlight] {
            items.filter { $0.kind == .fix }
        }
    }

    /// Newest version first.
    let releases: [Release]

    init(releases: [Release]) {
        self.releases = releases.sorted { $0.version > $1.version }
    }

    init(data: Data) throws {
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        try self.init(releases: entries.map { entry in
            guard let version = ReleaseVersion(entry.version) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Invalid release version \(entry.version)"
                ))
            }
            return Release(version: version, items: entry.items)
        })
    }

    static let bundled: ReleaseHighlights = {
        guard let url = Bundle.module.url(forResource: "ReleaseHighlights", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let highlights = try? ReleaseHighlights(data: data)
        else {
            return ReleaseHighlights(releases: [])
        }
        return highlights
    }()

    /// Releases after `lower`, up to and including `upper`, that have something to show.
    func releases(after lower: ReleaseVersion?, through upper: ReleaseVersion?) -> [Release] {
        releases.filter { release in
            !release.items.isEmpty
                && lower.map { release.version > $0 } ?? true
                && upper.map { release.version <= $0 } ?? true
        }
    }

    func recentReleases(through upper: ReleaseVersion?, limit: Int) -> [Release] {
        Array(releases(after: nil, through: upper).prefix(limit))
    }

    private struct Entry: Decodable {
        let version: String
        let items: [ReleaseHighlight]
    }
}

struct ReleaseHighlight: Decodable, Equatable, Sendable {
    enum Kind: String, Decodable, Sendable {
        case feature
        case fix
    }

    let kind: Kind
    let text: [String: String]

    func text(for locale: Locale) -> String {
        let language = Bundle.preferredLocalizations(
            from: Array(text.keys).sorted(),
            forPreferences: Self.preferences(for: locale.language)
        ).first
        return language.flatMap { text[$0] } ?? text[ReleaseHighlights.fallbackLanguage] ?? ""
    }

    /// A script-qualified identifier such as `es-Latn-MX` matches `es-ES` before `es-MX`,
    /// so the language with its region comes first.
    private static func preferences(for language: Locale.Language) -> [String] {
        let general = [language.minimalIdentifier, language.maximalIdentifier]
        guard let code = language.languageCode?.identifier, let region = language.region?.identifier else {
            return general
        }
        return ["\(code)-\(region)"] + general
    }
}

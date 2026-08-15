import Foundation

enum AppVersion {
    private static let shortVersionKey = "CFBundleShortVersionString"

    static var currentPresentation: String {
        presentation(bundle: .main)
    }

    static func presentation(bundle: Bundle) -> String {
        presentation(shortVersion: bundle.object(forInfoDictionaryKey: shortVersionKey) as? String)
    }

    static func presentation(shortVersion: String?) -> String {
        guard let shortVersion,
              let version = normalizedVersion(from: shortVersion)
        else {
            return String(localized: "filbert development")
        }

        return String.localizedStringWithFormat(String(localized: "filbert v%@"), version)
    }

    private static func normalizedVersion(from rawVersion: String) -> String? {
        let trimmedVersion = rawVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = trimmedVersion.first?.lowercased() == "v"
            ? String(trimmedVersion.dropFirst())
            : trimmedVersion

        guard version != "0.0.0", isSemanticVersion(version) else {
            return nil
        }

        return version
    }

    private static func isSemanticVersion(_ version: String) -> Bool {
        let pattern = #"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)"#
            + #"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"#
        return version.range(of: pattern, options: .regularExpression) != nil
    }
}

import Foundation

// `@unchecked`: `UserDefaults` is documented as thread-safe but is not marked `Sendable`.
/// macOS keeps a per-app language in `AppleLanguages` in the app's own domain. System Settings
/// writes the same key, and macOS reads it at launch for system and Sparkle text.
struct AppLanguagePreference: @unchecked Sendable {
    static let key = "AppleLanguages"

    private let defaults: UserDefaults
    /// `nil` under `swift run`, which has no bundle identifier. The choice then lasts one session.
    private let domainName: String?
    private let supportedLanguageCodes: [String]
    private let globalLanguages: @Sendable () -> [String]

    init(
        defaults: UserDefaults = .standard,
        domainName: String? = Bundle.main.bundleIdentifier,
        supportedLanguageCodes: [String] = SupportedLanguage.all.map(\.code),
        globalLanguages: @escaping @Sendable () -> [String] = { AppLanguagePreference.globalDomainLanguages() }
    ) {
        self.defaults = defaults
        self.domainName = domainName
        self.supportedLanguageCodes = supportedLanguageCodes
        self.globalLanguages = globalLanguages
    }

    /// The supported language that the stored value names, or `nil` for System Default.
    var selectedLanguageCode: String? {
        guard let stored = storedLanguages?.first,
              let match = Bundle.preferredLocalizations(from: supportedLanguageCodes, forPreferences: [stored]).first,
              Locale.Language(identifier: match).languageCode == Locale.Language(identifier: stored).languageCode
        else {
            return nil
        }
        return match
    }

    /// `Locale.preferredLanguages` puts the app's own value first, so System Default reads the
    /// global order. An unsupported stored value, such as `fr`, stays in charge, so the text falls
    /// back to English as macOS does.
    func systemLanguages() -> [String] {
        storedLanguages ?? globalLanguages()
    }

    var persistsSelection: Bool {
        domainName != nil
    }

    func store(_ languageCode: String?) {
        guard domainName != nil else { return }
        if let languageCode {
            defaults.set([languageCode], forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    private var storedLanguages: [String]? {
        let stored = domainName.flatMap { defaults.persistentDomain(forName: $0)?[Self.key] as? [String] }
        return stored?.isEmpty == false ? stored : nil
    }

    static func globalDomainLanguages() -> [String] {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? [String]
            ?? Locale.preferredLanguages
    }
}

import Foundation

public enum DisplayLanguage {
    private static let state = DisplayLanguageState()

    public static var selectedLanguageCode: String? {
        get { state.selectedLanguageCode }
        set { state.selectedLanguageCode = newValue }
    }

    public static var locale: Locale {
        state.locale()
    }

    public static func setSystemPreferences(_ preferences: @escaping @Sendable () -> [String]) {
        state.setSystemPreferences(preferences)
    }

    public static func setCurrentLocale(_ current: @escaping @Sendable () -> Locale) {
        state.setCurrentLocale(current)
    }

    static func resolve(
        selectedLanguageCode: String?,
        preferences: [String],
        available: [String],
        current: Locale
    ) -> Locale {
        let candidates = selectedLanguageCode.map { [$0] } ?? preferences
        let language = Bundle.preferredLocalizations(from: available, forPreferences: candidates).first ?? "en"
        var components = Locale.Components(locale: current)
        components.languageComponents = Locale.Language.Components(identifier: language)
        // `es-MX` brings region MX. Formats keep the macOS region, as macOS does for a per-app language.
        components.region = current.region
        return Locale(components: components)
    }
}

private struct DisplayLanguageCacheKey: Equatable {
    let selectedLanguageCode: String?
    let preferences: [String]
    let current: String
}

private final class DisplayLanguageState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedLanguageCode: String?
    private var systemPreferences: @Sendable () -> [String] = { Locale.preferredLanguages }
    private var currentLocale: @Sendable () -> Locale = { Locale.current }
    private var cache: (key: DisplayLanguageCacheKey, locale: Locale)?

    var selectedLanguageCode: String? {
        get { lock.withLock { storedLanguageCode } }
        set { lock.withLock { storedLanguageCode = newValue } }
    }

    func setSystemPreferences(_ preferences: @escaping @Sendable () -> [String]) {
        lock.withLock {
            systemPreferences = preferences
            cache = nil
        }
    }

    func setCurrentLocale(_ current: @escaping @Sendable () -> Locale) {
        lock.withLock {
            currentLocale = current
            cache = nil
        }
    }

    func locale() -> Locale {
        lock.withLock {
            let current = currentLocale()
            let key = DisplayLanguageCacheKey(
                selectedLanguageCode: storedLanguageCode,
                preferences: systemPreferences(),
                current: current.identifier
            )
            if let cache, cache.key == key {
                return cache.locale
            }
            let locale = DisplayLanguage.resolve(
                selectedLanguageCode: key.selectedLanguageCode,
                preferences: key.preferences,
                // Every catalog has the same languages, so Core's list stands for all.
                available: Bundle.module.localizations,
                current: current
            )
            cache = (key, locale)
            return locale
        }
    }
}

public extension String {
    /// `String(localized:bundle:locale:)` ignores `locale` when it picks the language.
    init(
        displayLocalized key: String.LocalizationValue,
        table: String? = nil,
        bundle: Bundle,
        comment: StaticString? = nil
    ) {
        self.init(displayLocalized: LocalizedStringResource(
            key,
            table: table,
            bundle: .atURL(bundle.bundleURL),
            comment: comment
        ))
    }

    init(displayLocalized resource: LocalizedStringResource) {
        var resource = resource
        resource.locale = DisplayLanguage.locale
        self.init(localized: resource)
    }
}

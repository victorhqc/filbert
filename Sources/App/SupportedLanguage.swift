struct SupportedLanguage: Identifiable, Equatable {
    /// The catalog language code.
    let code: String
    /// The language's name in that language, so a reader finds it in any display language.
    let autonym: String

    var id: String {
        code
    }

    static let all = [
        SupportedLanguage(code: "en", autonym: "English"),
        SupportedLanguage(code: "de-DE", autonym: "Deutsch"),
        SupportedLanguage(code: "es-MX", autonym: "Español (México)"),
        SupportedLanguage(code: "es-ES", autonym: "Español (España)"),
        SupportedLanguage(code: "pt-BR", autonym: "Português (Brasil)"),
        SupportedLanguage(code: "pt-PT", autonym: "Português (Portugal)"),
        SupportedLanguage(code: "ru", autonym: "Русский"),
        SupportedLanguage(code: "zh-Hans", autonym: "简体中文"),
        SupportedLanguage(code: "zh-Hant", autonym: "繁體中文"),
        SupportedLanguage(code: "ja", autonym: "日本語"),
    ]
}

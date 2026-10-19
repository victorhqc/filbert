import Core
import SwiftUI

@MainActor
struct LanguagePicker: View {
    let displayLanguage: DisplayLanguageModel

    var body: some View {
        Picker(
            String(displayLocalized: "Language", bundle: .module),
            selection: Binding(
                get: { displayLanguage.selectedLanguageCode },
                set: { displayLanguage.select($0) }
            )
        ) {
            Text(String(displayLocalized: "System Default", bundle: .module))
                .tag(String?.none)
            ForEach(SupportedLanguage.all) { language in
                Text(autonym(of: language))
                    .tag(Optional(language.code))
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel(String(displayLocalized: "Language", bundle: .module))

        if displayLanguage.changesSystemTextAtNextLaunch {
            Text(String(displayLocalized: "Some system dialogs change after Filbert restarts.", bundle: .module))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// VoiceOver reads each name in its own language.
    private func autonym(of language: SupportedLanguage) -> AttributedString {
        var autonym = AttributedString(language.autonym)
        autonym[AttributeScopes.FoundationAttributes.LanguageIdentifierAttribute.self] = language.code
        return autonym
    }
}

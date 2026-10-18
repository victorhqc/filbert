import Core
import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginController
    let displayLanguage: DisplayLanguageModel

    var body: some View {
        SettingsScrollColumn {
            SettingsCard(
                heading: String(displayLocalized: "Startup", bundle: .module),
                description: String(
                    displayLocalized: "Start Filbert in the menu bar after you sign in to your Mac.",
                    bundle: .module
                )
            ) {
                Toggle(
                    String(displayLocalized: "Launch at login", bundle: .module),
                    isOn: Binding(
                        get: { launchAtLogin.isRegistered },
                        set: { launchAtLogin.setRegistered($0) }
                    )
                )
                .disabled(!launchAtLogin.isAvailable)
                .accessibilityValue(statusDescription)

                Text(statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if launchAtLogin.status == .requiresApproval {
                    Button(String(displayLocalized: "Open Login Items Settings", bundle: .module)) {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }

                if let errorMessage = launchAtLogin.errorMessage?.resolved {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(errorMessage)
                }
            }

            languageCard
        }
        .navigationTitle(String(displayLocalized: "General", bundle: .module))
        .onAppear {
            launchAtLogin.refreshStatus()
        }
    }

    private var languageCard: some View {
        SettingsCard(
            heading: String(displayLocalized: "Language", bundle: .module),
            description: String(displayLocalized: "Choose the language Filbert uses.", bundle: .module)
        ) {
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
    }

    /// VoiceOver reads each name in its own language.
    private func autonym(of language: SupportedLanguage) -> AttributedString {
        var autonym = AttributedString(language.autonym)
        autonym[AttributeScopes.FoundationAttributes.LanguageIdentifierAttribute.self] = language.code
        return autonym
    }

    private var statusDescription: String {
        switch launchAtLogin.status {
        case .notRegistered:
            String(displayLocalized: "Filbert will not start at login.", bundle: .module)
        case .enabled:
            String(displayLocalized: "Filbert will start at login.", bundle: .module)
        case .requiresApproval:
            String(
                displayLocalized: "Filbert is registered, but macOS approval is required before it can start at login.",
                bundle: .module
            )
        case .notFound:
            String(
                displayLocalized: "macOS could not find Filbert's login item. Enable Launch at login to register it.",
                bundle: .module
            )
        case .unavailable:
            String(displayLocalized: "Launch at login requires an installed Filbert app.", bundle: .module)
        }
    }
}

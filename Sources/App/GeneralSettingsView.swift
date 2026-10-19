import Core
import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginController
    let displayLanguage: DisplayLanguageModel
    let welcomeWindow: WelcomeWindowController

    var body: some View {
        SettingsScrollColumn {
            SettingsCard(
                heading: String(displayLocalized: "Startup", bundle: .module),
                description: String(
                    displayLocalized: "Start Filbert in the menu bar after you sign in to your Mac.",
                    bundle: .module
                )
            ) {
                LaunchAtLoginControls(launchAtLogin: launchAtLogin)
            }

            SettingsCard(
                heading: String(displayLocalized: "Language", bundle: .module),
                description: String(displayLocalized: "Choose the language Filbert uses.", bundle: .module)
            ) {
                LanguagePicker(displayLanguage: displayLanguage)
            }

            SettingsCard(
                heading: String(displayLocalized: "Welcome", bundle: .module),
                description: String(
                    displayLocalized: "See the introduction to Filbert again.",
                    bundle: .module
                )
            ) {
                Button(String(displayLocalized: "Show Welcome Window", bundle: .module)) {
                    welcomeWindow.show()
                }
            }
        }
        .navigationTitle(String(displayLocalized: "General", bundle: .module))
        .onAppear {
            launchAtLogin.refreshStatus()
        }
    }
}

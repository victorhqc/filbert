import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    let launchAtLogin: LaunchAtLoginController

    var body: some View {
        SettingsScrollColumn {
            SettingsCard(
                heading: String(localized: "Startup", bundle: .module),
                description: String(
                    localized: "Start Filbert in the menu bar after you sign in to your Mac.",
                    bundle: .module
                )
            ) {
                Toggle(
                    String(localized: "Launch at login", bundle: .module),
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
                    Button(String(localized: "Open Login Items Settings", bundle: .module)) {
                        launchAtLogin.openLoginItemsSettings()
                    }
                }

                if let errorMessage = launchAtLogin.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(errorMessage)
                }
            }
        }
        .navigationTitle(String(localized: "General", bundle: .module))
        .onAppear {
            launchAtLogin.refreshStatus()
        }
    }

    private var statusDescription: String {
        switch launchAtLogin.status {
        case .notRegistered:
            String(localized: "Filbert will not start at login.", bundle: .module)
        case .enabled:
            String(localized: "Filbert will start at login.", bundle: .module)
        case .requiresApproval:
            String(
                localized: "Filbert is registered, but macOS approval is required before it can start at login.",
                bundle: .module
            )
        case .notFound:
            String(
                localized: "macOS could not find Filbert's login item. Enable Launch at login to register it.",
                bundle: .module
            )
        case .unavailable:
            String(localized: "Launch at login requires an installed Filbert app.", bundle: .module)
        }
    }
}

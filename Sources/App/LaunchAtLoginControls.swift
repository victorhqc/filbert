import Core
import SwiftUI

@MainActor
struct LaunchAtLoginControls: View {
    let launchAtLogin: LaunchAtLoginController

    var body: some View {
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

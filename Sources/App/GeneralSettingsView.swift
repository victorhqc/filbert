import Core
import SwiftUI

@MainActor
struct GeneralSettingsView: View {
    let viewModel: QuotaViewModel
    let sleepPrevention: SleepPreventionController
    let launchAtLogin: LaunchAtLoginController
    let displayLanguage: DisplayLanguageModel

    var body: some View {
        SettingsForm {
            Section {
                launchAtLoginRows
                LabeledContent(String(displayLocalized: "Language", bundle: .module)) {
                    VStack(alignment: .trailing, spacing: 4) {
                        LanguagePicker(displayLanguage: displayLanguage)
                    }
                }
            }

            UsageChecksSettingsSection(viewModel: viewModel)

            keepMacAwakeSection
        }
        .navigationTitle(String(displayLocalized: "General", bundle: .module))
        .onAppear {
            launchAtLogin.refreshStatus()
        }
    }

    @ViewBuilder
    private var launchAtLoginRows: some View {
        let statusDescription = LaunchAtLoginControls.statusDescription(for: launchAtLogin.status)
        Toggle(
            isOn: Binding(
                get: { launchAtLogin.isRegistered },
                set: { launchAtLogin.setRegistered($0) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(displayLocalized: "Launch at login", bundle: .module))
                SettingsCaption(statusDescription)
            }
        }
        .disabled(!launchAtLogin.isAvailable)
        .accessibilityValue(statusDescription)

        if launchAtLogin.status == .requiresApproval {
            HStack {
                Spacer()
                Button(String(displayLocalized: "Open Login Items Settings", bundle: .module)) {
                    launchAtLogin.openLoginItemsSettings()
                }
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

    private var keepMacAwakeSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { sleepPrevention.isFeatureVisible },
                    set: { sleepPrevention.setFeatureVisible($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(displayLocalized: "Show Keep Mac Awake", bundle: .module))
                    SettingsCaption(String(
                        displayLocalized: "Show a Keep Mac Awake timer in Filbert's panel",
                        bundle: .module
                    ))
                }
            }

            Toggle(
                isOn: Binding(
                    get: { sleepPrevention.remembersUntilTurnedOff },
                    set: { sleepPrevention.setRemembersUntilTurnedOff($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(displayLocalized: "Remember “Until turned off”", bundle: .module))
                    SettingsCaption(String(
                        displayLocalized: """
                        After a restart, Filbert turns Keep Mac Awake back on \
                        if it was set to Until turned off.
                        """,
                        bundle: .module
                    ))
                }
            }
            .disabled(!sleepPrevention.isFeatureVisible)
        } header: {
            Text(String(displayLocalized: "Keep Mac Awake", bundle: .module))
        }
    }
}

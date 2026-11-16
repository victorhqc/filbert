import AppKit
import Core
import SwiftUI

@MainActor
struct ProviderConnectionSection: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo

    var body: some View {
        switch provider.authShape {
        case .apiKey:
            APIKeyConnectionSection(viewModel: viewModel, provider: provider)
        case .apiKeyFree:
            APIKeyFreeConnectionSection(viewModel: viewModel, provider: provider)
        }
    }
}

private struct ConnectionSectionHeader: View {
    var body: some View {
        Text(String(displayLocalized: "Connection", bundle: .module))
    }
}

@MainActor
private struct ProviderDashboardRow: View {
    let provider: ProviderInfo

    @Environment(\.openURL) private var openURL

    var body: some View {
        if let accountLink = provider.accountLink {
            LabeledContent(String(displayLocalized: "Dashboard", bundle: .module)) {
                Button {
                    openURL(accountLink.url)
                } label: {
                    Label(String(displayLocalized: "Open", bundle: .module), systemImage: "arrow.up.right")
                }
                .accessibilityLabel(String.localizedStringWithFormat(
                    String(displayLocalized: "Open the %@ dashboard", bundle: .module),
                    provider.displayName
                ))
            }
        }
    }
}

@MainActor
private struct APIKeyConnectionSection: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo

    @State private var entry = APIKeyEntryState()

    var body: some View {
        let state = viewModel.providerStates[provider.id] ?? .unconfigured
        let isConfigured = QuotaViewModel.isConfiguredState(state)
        Section {
            ProviderStatusRow(status: ProviderStatusPresentation(state: state, isEnabled: true))

            if isConfigured {
                stateMessage(for: state)
                savedKeyRow
            } else {
                keyEntryRow
            }

            if let errorMessage = entry.errorMessage {
                SettingsErrorMessage(message: errorMessage, errorLog: viewModel.errorLog)
            }

            ProviderDashboardRow(provider: provider)
        } header: {
            ConnectionSectionHeader()
        } footer: {
            if !isConfigured {
                SettingsCaption(String(displayLocalized: "Filbert saves the key in your Keychain.", bundle: .module))
            }
        }
    }

    private var apiKeyLabel: String {
        String(displayLocalized: "API Key", bundle: .module)
    }

    @ViewBuilder
    private func stateMessage(for state: ProviderState) -> some View {
        if case let .error(message) = state {
            SettingsErrorMessage(message: message.resolved, errorLog: viewModel.errorLog)
        } else if let refreshError = viewModel.refreshErrors[provider.id]?.resolved {
            SettingsErrorMessage(message: refreshError, errorLog: viewModel.errorLog)
        } else if case .loading = state {
            SettingsWorkingIndicator()
        }
    }

    private var savedKeyRow: some View {
        LabeledContent(apiKeyLabel) {
            HStack(spacing: 8) {
                Text(String(displayLocalized: "Saved in Keychain", bundle: .module))
                    .foregroundStyle(.secondary)
                Button(String(displayLocalized: "Remove", bundle: .module), role: .destructive) {
                    entry.clear(using: { try viewModel.deleteKey(for: provider.id) })
                }
                .accessibilityLabel(String.localizedStringWithFormat(
                    String(displayLocalized: "Remove the %@ API key", bundle: .module),
                    provider.displayName
                ))
            }
        }
    }

    private var keyEntryRow: some View {
        LabeledContent(apiKeyLabel) {
            HStack(spacing: 6) {
                SecureField(
                    apiKeyLabel,
                    text: Binding(
                        get: { entry.input },
                        set: { entry.updateInput($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(minWidth: 160)
                .onSubmit { save() }
                Button(String(displayLocalized: "Save", bundle: .module)) {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .disabled(entry.input.isEmpty)
            }
        }
    }

    private func save() {
        entry.save(using: { try viewModel.saveKey($0, for: provider.id) })
    }
}

@MainActor
private struct APIKeyFreeConnectionSection: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo

    var body: some View {
        let state = viewModel.providerStates[provider.id] ?? .unconfigured
        Section {
            ProviderStatusRow(status: ProviderStatusPresentation(state: state, isEnabled: true))
            stateRows(for: state)
            actionsRow(for: state)
            ProviderDashboardRow(provider: provider)
        } header: {
            ConnectionSectionHeader()
        }
    }

    private var canInstall: Bool {
        viewModel.canInstallHelper(for: provider.id)
    }

    private var canRemove: Bool {
        viewModel.canRemoveHelper(for: provider.id)
    }

    private var credentialImportActionTitle: String? {
        viewModel.credentialImportActionTitle(for: provider.id)
    }

    @ViewBuilder
    private func stateRows(for state: ProviderState) -> some View {
        switch state {
        case .loading:
            SettingsWorkingIndicator()
        case let .setup(reason):
            setupReasonRow(reason.resolved)
            if canInstall {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsCaption(String(
                        displayLocalized: "Filbert reads your Claude Code usage by hooking into its status line.",
                        bundle: .module
                    ))
                    SettingsCaption(String(
                        displayLocalized: "This adds a small helper script to ~/.claude/.",
                        bundle: .module
                    ))
                }
            }
        case .loaded:
            if canRemove {
                LabeledContent(String(displayLocalized: "Helper", bundle: .module)) {
                    Text(String(displayLocalized: "Installed", bundle: .module))
                }
            }
            if let refreshError = viewModel.refreshErrors[provider.id]?.resolved {
                SettingsErrorMessage(message: refreshError, errorLog: viewModel.errorLog)
            }
        case let .error(message):
            SettingsErrorMessage(message: message.resolved, errorLog: viewModel.errorLog)
        case .unconfigured:
            EmptyView()
        }
    }

    private func setupReasonRow(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsCaption(reason)
            if let setupHelp = provider.setupHelp {
                Button {
                    NSWorkspace.shared.open(setupHelp.url)
                } label: {
                    Label(setupHelp.linkLabel, systemImage: "arrow.up.right")
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private func actionsRow(for state: ProviderState) -> some View {
        let actions = APIKeyFreeManagementAction.connectionActions(
            for: state,
            canInstall: canInstall,
            canRemove: canRemove,
            canImportCredentials: credentialImportActionTitle != nil
        )
        if !actions.isEmpty {
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                ForEach(actions, id: \.self) { action in
                    actionButton(action)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: APIKeyFreeManagementAction) -> some View {
        switch action {
        case .installHelper:
            Button(String(displayLocalized: "Install Helper", bundle: .module)) {
                Task { await viewModel.installHelper(for: provider.id) }
            }
            .buttonStyle(.borderedProminent)
        case .removeHelper:
            Button(String(displayLocalized: "Remove Helper", bundle: .module), role: .destructive) {
                Task { await viewModel.removeHelper(for: provider.id) }
            }
        case .importCredentials:
            if let credentialImportActionTitle {
                Button(credentialImportActionTitle) {
                    Task { await viewModel.importCredentials(for: provider.id) }
                }
            }
        }
    }
}

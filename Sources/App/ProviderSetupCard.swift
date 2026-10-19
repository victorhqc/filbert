import AppKit
import Core
import SwiftUI

@MainActor
struct ProviderSetupCard: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo

    var body: some View {
        let state = viewModel.providerStates[provider.id] ?? .unconfigured
        let isEnabled = viewModel.isEnabled(provider.id)
        SettingsCard {
            providerSettingsRow(for: provider, state: state, isEnabled: isEnabled)
            providerDisclaimer(for: provider)
        }
    }

    @ViewBuilder
    private func providerSettingsRow(
        for provider: ProviderInfo,
        state: ProviderState,
        isEnabled: Bool
    ) -> some View {
        switch provider.authShape {
        case .apiKey:
            apiKeySettingsRow(for: provider, state: state, isEnabled: isEnabled)
        case .apiKeyFree:
            apiKeyFreeSettingsRow(for: provider, state: state, isEnabled: isEnabled)
        }
    }

    private func apiKeySettingsRow(
        for provider: ProviderInfo,
        state: ProviderState,
        isEnabled: Bool
    ) -> ProviderSettingsRow {
        ProviderSettingsRow(
            provider: provider,
            state: state,
            isEnabled: isEnabled,
            overrideURL: viewModel.overrideURL(for: provider.id),
            errorLog: viewModel.errorLog,
            refreshError: viewModel.refreshErrors[provider.id]?.resolved,
            onEnabledChange: { enabled in
                viewModel.setProviderEnabled(enabled, for: provider.id)
            },
            onSaveKey: { key in
                try viewModel.saveKey(key, for: provider.id)
            },
            onClearKey: {
                try viewModel.deleteKey(for: provider.id)
            },
            onSaveOverride: { url in
                try viewModel.saveOverrideURL(url, for: provider.id)
            }
        )
    }

    private func apiKeyFreeSettingsRow(
        for provider: ProviderInfo,
        state: ProviderState,
        isEnabled: Bool
    ) -> APIKeyFreeSettingsRow {
        APIKeyFreeSettingsRow(
            provider: provider,
            state: state,
            isEnabled: isEnabled,
            canInstall: isEnabled && viewModel.canInstallHelper(for: provider.id),
            canRemove: isEnabled && viewModel.canRemoveHelper(for: provider.id),
            credentialImportActionTitle: isEnabled
                ? viewModel.credentialImportActionTitle(for: provider.id)
                : nil,
            errorLog: viewModel.errorLog,
            refreshError: viewModel.refreshErrors[provider.id]?.resolved,
            onEnabledChange: { enabled in
                viewModel.setProviderEnabled(enabled, for: provider.id)
            },
            onInstall: {
                Task { await viewModel.installHelper(for: provider.id) }
            },
            onRemove: {
                Task { await viewModel.removeHelper(for: provider.id) }
            },
            onImportCredentials: {
                Task { await viewModel.importCredentials(for: provider.id) }
            }
        )
    }

    @ViewBuilder
    private func providerDisclaimer(for provider: ProviderInfo) -> some View {
        if let disclaimer = provider.disclaimer {
            Divider()
            Label(disclaimer, systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
private struct ProviderSettingsRow: View {
    let provider: ProviderInfo
    let state: ProviderState
    let isEnabled: Bool
    let overrideURL: URL?
    let errorLog: ErrorLog
    let refreshError: String?
    let onEnabledChange: @MainActor @Sendable (Bool) -> Void
    let onSaveKey: (String) throws -> Void
    let onClearKey: () throws -> Void
    let onSaveOverride: (URL?) throws -> Void

    @State private var apiKeyEntryState = APIKeyEntryState()
    @State private var advancedExpanded: Bool = false
    @State private var overrideInput: String = ""
    @State private var overrideErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCardHeader(
                provider: provider,
                status: isEnabled ? ProviderStatusPresentation.apiKey(state) : .disabled,
                isEnabled: isEnabled,
                onEnabledChange: onEnabledChange,
                supplementaryLabel: overrideURL == nil ? nil : String(displayLocalized: "custom URL", bundle: .module)
            )
            Divider()
            if isEnabled, isConfigured {
                configuredContent
            } else {
                keyEntry
            }
            advancedDisclosure
        }
    }

    @ViewBuilder
    private var configuredContent: some View {
        if case let .error(message) = state {
            Label(message.resolved, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
            ErrorLogLink(errorLog: errorLog)
        } else if let refreshError {
            Label(refreshError, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
            ErrorLogLink(errorLog: errorLog)
        } else if case .loading = state {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(displayLocalized: "Working…", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Button(String(displayLocalized: "Clear Key", bundle: .module), role: .destructive) {
            clearKey()
        }
        .controlSize(.small)
        if let errorMessage = apiKeyEntryState.errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
            ErrorLogLink(errorLog: errorLog)
        }
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SecureField(String(displayLocalized: "API Key", bundle: .module), text: apiKeyBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveKeyIfValid() }
                Button(String(displayLocalized: "Save", bundle: .module)) {
                    saveKeyIfValid()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyEntryState.input.isEmpty)
            }
            if let errorMessage = apiKeyEntryState.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                ErrorLogLink(errorLog: errorLog)
            }
        }
        .controlSize(.regular)
    }

    private var isConfigured: Bool {
        switch state {
        case .unconfigured, .setup:
            false
        case .loading, .loaded, .error:
            true
        }
    }

    private var advancedDisclosure: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                advancedExpanded.toggle()
                if advancedExpanded {
                    refreshOverrideInput()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(displayLocalized: "Advanced", bundle: .module))
                    Image(systemName: advancedExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            if advancedExpanded {
                overrideEditor
            }
        }
    }

    private var overrideEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(String(displayLocalized: "Default:", bundle: .module))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(provider.defaultBaseURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                TextField(
                    String(displayLocalized: "Custom base URL (proxy)", bundle: .module),
                    text: $overrideInput
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveOverride() }
                .onChange(of: overrideInput) { _, _ in
                    overrideErrorMessage = nil
                }
                Button(String(displayLocalized: "Save", bundle: .module)) {
                    saveOverride()
                }
                .buttonStyle(.borderedProminent)
                Button(String(displayLocalized: "Use Default", bundle: .module)) {
                    resetOverride()
                }
                .disabled(overrideURL == nil)
            }
            if let overrideErrorMessage {
                Text(overrideErrorMessage)
                    .font(.caption)
                    .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                ErrorLogLink(errorLog: errorLog)
            }
        }
        .padding(.top, 2)
    }

    private func saveKeyIfValid() {
        apiKeyEntryState.save(using: onSaveKey)
    }

    private func clearKey() {
        apiKeyEntryState.clear(using: onClearKey)
    }

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { apiKeyEntryState.input },
            set: { apiKeyEntryState.updateInput($0) }
        )
    }

    private func saveOverride() {
        let trimmed = overrideInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: URL?
        if trimmed.isEmpty {
            resolved = nil
        } else if let url = URL(string: trimmed) {
            resolved = url
        } else {
            errorLog.record(
                component: "app",
                operation: "save-override",
                code: "invalid-url",
                providerID: provider.id
            )
            overrideErrorMessage = String(displayLocalized: "Only https URLs are allowed.", bundle: .module)
            return
        }

        do {
            try onSaveOverride(resolved)
            overrideErrorMessage = nil
        } catch {
            overrideErrorMessage = String(displayLocalized: "Only https URLs are allowed.", bundle: .module)
        }
    }

    private func resetOverride() {
        do {
            try onSaveOverride(nil)
            overrideInput = ""
            overrideErrorMessage = nil
        } catch {
            overrideErrorMessage = String(displayLocalized: "Only https URLs are allowed.", bundle: .module)
        }
    }

    private func refreshOverrideInput() {
        overrideInput = overrideURL?.absoluteString ?? ""
        overrideErrorMessage = nil
    }
}

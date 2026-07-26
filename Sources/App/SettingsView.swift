import AppKit
import Core
import SwiftUI

@MainActor
struct SettingsView: View {
    let viewModel: QuotaViewModel

    var body: some View {
        TabView {
            providersTab
                .tabItem {
                    Label(String(localized: "Providers"), systemImage: "key.fill")
                }

            AppearanceTab(viewModel: viewModel)
                .tabItem {
                    Label(String(localized: "Appearance"), systemImage: "list.bullet.indent")
                }
        }
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: .infinity,
            minHeight: 420,
            idealHeight: 520,
            maxHeight: .infinity
        )
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var providersTab: some View {
        SettingsScrollColumn {
            ForEach(viewModel.registeredProvidersOrdered) { provider in
                providerCard(for: provider)
            }
        }
        .navigationTitle(String(localized: "Providers"))
    }

    @ViewBuilder
    private func providerCard(for provider: ProviderInfo) -> some View {
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
            credentialImportActionTitle: isEnabled
                ? viewModel.credentialImportActionTitle(for: provider.id)
                : nil,
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
                supplementaryLabel: overrideURL == nil ? nil : String(localized: "custom URL")
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
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
        } else if case .loading = state {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Working…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Button(String(localized: "Clear Key"), role: .destructive) {
            clearKey()
        }
        .controlSize(.small)
    }

    private var keyEntry: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SecureField(String(localized: "API Key"), text: apiKeyBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveKeyIfValid() }
                Button(String(localized: "Save")) {
                    saveKeyIfValid()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyEntryState.input.isEmpty)
            }
            if let errorMessage = apiKeyEntryState.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
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
                    Text(String(localized: "Advanced"))
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
                Text(String(localized: "Default:"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(provider.defaultBaseURL.absoluteString)
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                TextField(
                    String(localized: "Custom base URL (proxy)"),
                    text: $overrideInput
                )
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveOverride() }
                .onChange(of: overrideInput) { _, _ in
                    overrideErrorMessage = nil
                }
                Button(String(localized: "Save")) {
                    saveOverride()
                }
                .buttonStyle(.borderedProminent)
                Button(String(localized: "Reset")) {
                    resetOverride()
                }
                .disabled(overrideURL == nil)
            }
            if let overrideErrorMessage {
                Text(overrideErrorMessage)
                    .font(.caption)
                    .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
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
            overrideErrorMessage = String(localized: "Only https URLs are allowed.")
            return
        }

        do {
            try onSaveOverride(resolved)
            overrideErrorMessage = nil
        } catch {
            overrideErrorMessage = String(localized: "Only https URLs are allowed.")
        }
    }

    private func resetOverride() {
        do {
            try onSaveOverride(nil)
            overrideInput = ""
            overrideErrorMessage = nil
        } catch {
            overrideErrorMessage = String(localized: "Only https URLs are allowed.")
        }
    }

    private func refreshOverrideInput() {
        overrideInput = overrideURL?.absoluteString ?? ""
        overrideErrorMessage = nil
    }
}

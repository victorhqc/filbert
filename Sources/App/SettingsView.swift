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
                let state = viewModel.providerStates[provider.id] ?? .unconfigured
                SettingsCard {
                    switch provider.authShape {
                    case .apiKey:
                        ProviderSettingsRow(
                            provider: provider,
                            state: state,
                            overrideURL: viewModel.overrideURL(for: provider.id),
                            onSaveKey: { key in
                                try? viewModel.saveKey(key, for: provider.id)
                            },
                            onClearKey: {
                                try? viewModel.deleteKey(for: provider.id)
                            },
                            onSaveOverride: { url in
                                try viewModel.saveOverrideURL(url, for: provider.id)
                            }
                        )
                    case .apiKeyFree:
                        APIKeyFreeSettingsRow(
                            provider: provider,
                            state: state,
                            canInstall: viewModel.canInstallHelper(for: provider.id),
                            onInstall: {
                                Task { await viewModel.installHelper(for: provider.id) }
                            },
                            onRemove: {
                                Task { await viewModel.removeHelper(for: provider.id) }
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Providers"))
    }
}

@MainActor
private struct ProviderSettingsRow: View {
    let provider: ProviderInfo
    let state: ProviderState
    let overrideURL: URL?
    let onSaveKey: (String) -> Void
    let onClearKey: () -> Void
    let onSaveOverride: (URL?) throws -> Void

    @State private var apiKey: String = ""
    @State private var advancedExpanded: Bool = false
    @State private var overrideInput: String = ""
    @State private var overrideErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCardHeader(
                provider: provider,
                status: ProviderStatusPresentation.apiKey(state),
                supplementaryLabel: overrideURL == nil ? nil : String(localized: "custom URL")
            )

            Divider()

            if isConfigured {
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
            onClearKey()
        }
        .controlSize(.small)
    }

    private var keyEntry: some View {
        HStack(spacing: 6) {
            SecureField(String(localized: "API Key"), text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveKeyIfValid() }

            Button(String(localized: "Save")) {
                saveKeyIfValid()
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKey.isEmpty)
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
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSaveKey(trimmed)
        apiKey = ""
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

@MainActor
private struct APIKeyFreeSettingsRow: View {
    let provider: ProviderInfo
    let state: ProviderState
    let canInstall: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCardHeader(
                provider: provider,
                status: ProviderStatusPresentation.apiKeyFree(state)
            )

            Divider()

            switch state {
            case .loading:
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Working…"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case let .setup(reason):
                if canInstall {
                    installPromptView(reason: reason)
                } else {
                    setupReasonView(reason: reason)
                }
            case .loaded:
                removeHelperView
            case let .error(message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
            case .unconfigured:
                Text(String(localized: "Not configured"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func installPromptView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            setupReasonView(reason: reason)

            Text(String(localized: "AI Usage reads your Claude Code usage by hooking into its status line."))
                .font(.caption)
                .foregroundColor(.secondary)
            Text(String(localized: "This adds a small helper script to ~/.claude/."))
                .font(.caption)
                .foregroundColor(.secondary)

            Button(String(localized: "Install Helper")) {
                onInstall()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func setupReasonView(reason: String) -> some View {
        HStack(spacing: 6) {
            if let setupHelp = provider.setupHelp {
                Button {
                    NSWorkspace.shared.open(setupHelp.url)
                } label: {
                    Label(setupHelp.linkLabel, systemImage: "arrow.up.right")
                }
                .font(.caption)
                .buttonStyle(.link)
                .layoutPriority(1)
            }

            Text(reason)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
    }

    private var removeHelperView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Helper installed and active."))
                .font(.caption)
                .foregroundColor(.secondary)

            Button(String(localized: "Remove Helper"), role: .destructive) {
                onRemove()
            }
        }
    }
}

import AppKit
import Core
import SwiftUI

@MainActor
struct APIKeyFreeSettingsRow: View {
    let provider: ProviderInfo
    let state: ProviderState
    let isEnabled: Bool
    let canInstall: Bool
    let canRemove: Bool
    let credentialImportActionTitle: String?
    let errorLog: ErrorLog
    let refreshError: String?
    let onEnabledChange: @MainActor @Sendable (Bool) -> Void
    let onInstall: () -> Void
    let onRemove: () -> Void
    let onImportCredentials: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingsCardHeader(
                provider: provider,
                status: isEnabled ? ProviderStatusPresentation.apiKeyFree(state) : .disabled,
                isEnabled: isEnabled,
                onEnabledChange: onEnabledChange
            )

            Divider()

            if !isEnabled {
                Text(String(displayLocalized: "Enable this provider to view setup options.", bundle: .module))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                switch state {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(String(displayLocalized: "Working…", bundle: .module))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case let .setup(reason):
                    VStack(alignment: .leading, spacing: 8) {
                        if canInstall {
                            installPromptView(reason: reason.resolved)
                        } else {
                            setupReasonView(reason: reason.resolved)
                        }
                        if canRemove {
                            removeButton
                        }
                        credentialImportButton
                    }
                case .loaded:
                    if canRemove {
                        removeHelperView
                    }
                    if let refreshError {
                        Label(refreshError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                        ErrorLogLink(errorLog: errorLog)
                    }
                case let .error(message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message.resolved, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                        ErrorLogLink(errorLog: errorLog)
                        if canInstall {
                            installButton
                        }
                        if canRemove {
                            removeButton
                        }
                        credentialImportButton
                    }
                case .unconfigured:
                    Text(String(displayLocalized: "Not configured", bundle: .module))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func installPromptView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            setupReasonView(reason: reason)

            Text(String(
                displayLocalized: "Filbert reads your Claude Code usage by hooking into its status line.",
                bundle: .module
            ))
            .font(.caption)
            .foregroundColor(.secondary)
            Text(String(displayLocalized: "This adds a small helper script to ~/.claude/.", bundle: .module))
                .font(.caption)
                .foregroundColor(.secondary)

            installButton
        }
    }

    private var installButton: some View {
        Button(String(displayLocalized: "Install Helper", bundle: .module)) {
            onInstall()
        }
        .buttonStyle(.borderedProminent)
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

    @ViewBuilder
    private var credentialImportButton: some View {
        if let credentialImportActionTitle {
            Button(credentialImportActionTitle) {
                onImportCredentials()
            }
            .buttonStyle(.bordered)
        }
    }

    private var removeHelperView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(displayLocalized: "Helper installed and active.", bundle: .module))
                .font(.caption)
                .foregroundColor(.secondary)

            removeButton
        }
    }

    private var removeButton: some View {
        Button(String(displayLocalized: "Remove Helper", bundle: .module), role: .destructive) {
            onRemove()
        }
    }
}

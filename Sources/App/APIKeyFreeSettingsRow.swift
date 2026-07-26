import AppKit
import Core
import SwiftUI

@MainActor
struct APIKeyFreeSettingsRow: View {
    let provider: ProviderInfo
    let state: ProviderState
    let isEnabled: Bool
    let canInstall: Bool
    let credentialImportActionTitle: String?
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
                Text(String(localized: "Enable this provider to view setup options."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
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
                    VStack(alignment: .leading, spacing: 8) {
                        if canInstall {
                            installPromptView(reason: reason)
                        } else {
                            setupReasonView(reason: reason)
                        }
                        credentialImportButton
                    }
                case .loaded:
                    removeHelperView
                case let .error(message):
                    VStack(alignment: .leading, spacing: 8) {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                        credentialImportButton
                    }
                case .unconfigured:
                    Text(String(localized: "Not configured"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func installPromptView(reason: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            setupReasonView(reason: reason)

            Text(String(localized: "Filbert reads your Claude Code usage by hooking into its status line."))
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
            Text(String(localized: "Helper installed and active."))
                .font(.caption)
                .foregroundColor(.secondary)

            Button(String(localized: "Remove Helper"), role: .destructive) {
                onRemove()
            }
        }
    }
}

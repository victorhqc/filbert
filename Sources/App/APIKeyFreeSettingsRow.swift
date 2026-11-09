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
                    }
                case .loaded:
                    if canRemove {
                        Text(String(displayLocalized: "Helper installed and active.", bundle: .module))
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    }
                case .unconfigured:
                    Text(String(displayLocalized: "Not configured", bundle: .module))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if !managementActionKinds.isEmpty || (isEnabled && provider.accountLink != nil) {
                HStack(spacing: 8) {
                    managementActions
                    Spacer(minLength: 8)
                    ProviderAccountButton(provider: provider, isEnabled: isEnabled)
                }
                .controlSize(.small)
            }
        }
    }

    private var managementActionKinds: [APIKeyFreeManagementAction] {
        APIKeyFreeManagementAction.actions(
            for: state,
            isEnabled: isEnabled,
            canInstall: canInstall,
            canRemove: canRemove,
            canImportCredentials: credentialImportActionTitle != nil
        )
    }

    private var managementActions: some View {
        ForEach(managementActionKinds, id: \.self) { action in
            switch action {
            case .installHelper:
                Button(String(displayLocalized: "Install Helper", bundle: .module), action: onInstall)
                    .buttonStyle(.borderedProminent)
            case .removeHelper:
                Button(String(displayLocalized: "Remove Helper", bundle: .module), role: .destructive, action: onRemove)
            case .importCredentials:
                credentialImportButton
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

    private var removeButton: some View {
        Button(String(displayLocalized: "Remove Helper", bundle: .module), role: .destructive) {
            onRemove()
        }
    }
}

/// Each management action appears once, in the card's bottom action row.
enum APIKeyFreeManagementAction: Hashable {
    case installHelper
    case removeHelper
    case importCredentials

    static func actions(
        for state: ProviderState,
        isEnabled: Bool,
        canInstall: Bool,
        canRemove: Bool,
        canImportCredentials: Bool
    ) -> [Self] {
        guard isEnabled else { return [] }
        let candidates: [(Self, Bool)] = switch state {
        case .loaded:
            [(.removeHelper, canRemove)]
        case .setup:
            [(.installHelper, canInstall), (.importCredentials, canImportCredentials)]
        case .error:
            [(.importCredentials, canImportCredentials)]
        case .loading, .unconfigured:
            []
        }
        return candidates.filter(\.1).map(\.0)
    }
}

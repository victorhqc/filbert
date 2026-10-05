import Core
import SwiftUI

@MainActor
struct RefreshSettingsProviderRow: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let status = providerStatus {
                Label(status, systemImage: providerStatusSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(status)
            }

            if let disclosureText {
                Label(disclosureText, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(disclosureText)
            }

            if showsSmartStatus {
                smartStatus
            }
        }
        .padding(.vertical, 2)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            ProviderLogoBadge(glyph: provider.glyph)
            Text(provider.displayName)
                .font(.headline)
            Spacer()
            Toggle(
                String(localized: "Automatic refresh"),
                isOn: Binding(
                    get: { viewModel.isAutoRefreshEnabled(for: provider.id) },
                    set: { viewModel.setAutoRefreshEnabled($0, for: provider.id) }
                )
            )
            .toggleStyle(.switch)
            .accessibilityLabel(
                String.localizedStringWithFormat(
                    String(localized: "Automatic refresh for %@"),
                    provider.displayName
                )
            )
            .accessibilityValue(
                isEnabled ? String(localized: "Enabled") : String(localized: "Disabled")
            )
            .accessibilityHint(disclosureText ?? String(localized: "Toggle periodic refresh for this provider."))
            .help(String(localized: "Toggle periodic refresh for this provider."))
        }
    }

    private var smartStatus: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                if let override = effectiveIntervalOverrideText {
                    overrideLabel(override)
                }
                fastStatus
                extensionMenu
            }
        }
    }

    @ViewBuilder
    private var fastStatus: some View {
        if let remaining = viewModel.smartExtensionRemaining(for: provider.id) {
            extensionStatus(remaining)
        } else if viewModel.isFastAutomaticRefreshActive(for: provider.id) {
            Label(
                String(localized: "Fast checks are on due to recent activity."),
                systemImage: "bolt.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(localized: "Fast checks are on due to recent activity."))
        }
    }

    private var extensionMenu: some View {
        Menu {
            ForEach(AutoRefreshPreferences.smartExtensionOptions, id: \.self) { duration in
                Button(refreshDurationText(duration)) {
                    viewModel.startSmartExtension(for: provider.id, duration: duration)
                }
            }
        } label: {
            Text(String(localized: "Keep checking"))
        }
        .fixedSize()
        .accessibilityLabel(
            String.localizedStringWithFormat(
                String(localized: "Keep checking for %@"),
                provider.displayName
            )
        )
    }

    private func overrideLabel(_ text: String) -> some View {
        Label(text, systemImage: "speedometer")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }

    private func extensionStatus(_ remaining: TimeInterval) -> some View {
        let remainingText = extensionRemainingText(remaining)
        return HStack(spacing: 10) {
            Label(remainingText, systemImage: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(remainingText)
            Spacer()
            Button(String(localized: "Stop extension")) {
                viewModel.stopSmartExtension(for: provider.id)
            }
            .buttonStyle(.borderless)
            .accessibilityHint(stopExtensionHint)
            .help(stopExtensionHint)
        }
    }

    private var isEnabled: Bool {
        viewModel.isAutoRefreshEnabled(for: provider.id)
    }

    private var showsSmartStatus: Bool {
        viewModel.autoRefreshMode == .smart
            && isEnabled
            && viewModel.isEnabled(provider.id)
    }

    private var providerStatus: String? {
        guard viewModel.isEnabled(provider.id) else {
            return String(localized: "Automatic refresh is paused because this provider is disabled.")
        }
        guard QuotaViewModel.isConfiguredState(viewModel.providerStates[provider.id]) else {
            return String(localized: "Automatic refresh is waiting for setup.")
        }
        return nil
    }

    private var providerStatusSymbol: String {
        viewModel.isEnabled(provider.id) ? "clock" : "pause.circle"
    }

    private var disclosureText: String? {
        guard let command = provider.automaticRefreshDisclosure else {
            return costDisclosure
        }
        return String.localizedStringWithFormat(
            String(
                localized: """
                %1$@ runs %2$@ in the background. These checks may use some of your \
                %3$@ quota. Shorter Smart intervals can increase the number of checks.
                """
            ),
            provider.displayName,
            command.command,
            command.quotaName
        )
    }

    private var costDisclosure: String? {
        switch provider.refreshCharacteristics.costEvidence {
        case .possibleConsumption:
            String.localizedStringWithFormat(
                String(localized: "These checks may use some of your %@ quota."),
                provider.displayName
            )
        case .unknown:
            String(localized: "The quota cost of these checks is unknown.")
        case .documentedNonConsumption:
            String(
                localized: "These checks are documented as not using quota. Frequency limits may still apply."
            )
        }
    }

    private var effectiveIntervalOverrideText: String? {
        guard viewModel.providerMinimumIntervalOverridesFastRefresh(for: provider.id) else {
            return nil
        }
        return String.localizedStringWithFormat(
            String(localized: "Provider limit: checks no more often than every %@."),
            refreshDurationText(viewModel.effectiveFastInterval(for: provider.id))
        )
    }

    private func extensionRemainingText(_ remaining: TimeInterval) -> String {
        String.localizedStringWithFormat(
            String(localized: "Keep checking: %@ left."),
            refreshDurationText(remaining)
        )
    }

    private var stopExtensionHint: String {
        String(localized: "Stop extension keeps automatic refresh on.")
    }
}

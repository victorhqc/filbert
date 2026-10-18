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
                String(displayLocalized: "Automatic refresh", bundle: .module),
                isOn: Binding(
                    get: { viewModel.isAutoRefreshEnabled(for: provider.id) },
                    set: { viewModel.setAutoRefreshEnabled($0, for: provider.id) }
                )
            )
            .toggleStyle(.switch)
            .accessibilityLabel(
                String.localizedStringWithFormat(
                    String(displayLocalized: "Automatic refresh for %@", bundle: .module),
                    provider.displayName
                )
            )
            .accessibilityValue(
                isEnabled
                    ? String(displayLocalized: "Enabled", bundle: .module)
                    : String(displayLocalized: "Disabled", bundle: .module)
            )
            .accessibilityHint(disclosureText ?? String(
                displayLocalized: "Toggle periodic refresh for this provider.",
                bundle: .module
            ))
            .help(String(displayLocalized: "Toggle periodic refresh for this provider.", bundle: .module))
        }
    }

    private var smartStatus: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            VStack(alignment: .leading, spacing: 8) {
                if let override = effectiveIntervalOverrideText {
                    overrideLabel(override)
                }
                fastStatus
                if fastRefreshMatchesSlowInterval {
                    caption(
                        String(
                            displayLocalized: """
                            Fast and slow checks use the same interval, so fast checks are not more frequent.
                            """,
                            bundle: .module
                        )
                    )
                }
                extensionMenu
                caption(keepCheckingExplanation)
            }
        }
    }

    @ViewBuilder
    private var fastStatus: some View {
        if let remaining = viewModel.smartExtensionRemaining(for: provider.id) {
            VStack(alignment: .leading, spacing: 8) {
                extensionStatus(remaining)
                caption(stopExplanation)
            }
        } else if viewModel.isFastAutomaticRefreshActive(for: provider.id) {
            Label(
                String(displayLocalized: "Fast checks are on due to recent activity.", bundle: .module),
                systemImage: "bolt.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String(displayLocalized: "Fast checks are on due to recent activity.", bundle: .module))
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
            Text(String(displayLocalized: "Keep checking", bundle: .module))
        }
        .fixedSize()
        .accessibilityLabel(
            String.localizedStringWithFormat(
                String(displayLocalized: "Keep checking %@", bundle: .module),
                provider.displayName
            )
        )
        .accessibilityHint(keepCheckingExplanation)
        .help(keepCheckingExplanation)
    }

    private func overrideLabel(_ text: String) -> some View {
        Label(text, systemImage: "speedometer")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(text)
    }

    private func extensionStatus(_ remaining: TimeInterval) -> some View {
        let remainingText = extensionStatusText(remaining)
        return HStack(spacing: 10) {
            Label(remainingText, systemImage: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(remainingText)
            Spacer()
            Button(String(displayLocalized: "Stop fast checks", bundle: .module)) {
                viewModel.stopSmartExtension(for: provider.id)
            }
            .buttonStyle(.borderless)
            .accessibilityHint(stopExplanation)
            .help(stopExplanation)
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
            return String(
                displayLocalized: "Automatic refresh is paused because this provider is disabled.",
                bundle: .module
            )
        }
        guard QuotaViewModel.isConfiguredState(viewModel.providerStates[provider.id]) else {
            return String(displayLocalized: "Automatic refresh is waiting for setup.", bundle: .module)
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
                displayLocalized: """
                Filbert runs %2$@ in the background to check %1$@ usage. These checks may use \
                some of your %3$@ quota. Shorter Smart intervals can increase the number of checks.
                """,
                bundle: .module
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
                String(displayLocalized: "These checks may use some of your %@ quota.", bundle: .module),
                provider.displayName
            )
        case .unknown:
            String(displayLocalized: "The quota cost of these checks is unknown.", bundle: .module)
        case .documentedNonConsumption:
            String(
                displayLocalized: "These checks are documented as not using quota. Frequency limits may still apply.",
                bundle: .module
            )
        }
    }

    private var fastRefreshMatchesSlowInterval: Bool {
        viewModel.fastRefreshMatchesSlowInterval(for: provider.id)
    }

    private var effectiveIntervalOverrideText: String? {
        guard viewModel.providerMinimumIntervalOverridesFastRefresh(for: provider.id) else {
            return nil
        }
        return String.localizedStringWithFormat(
            String(displayLocalized: "Provider limit: checks no more often than %@.", bundle: .module),
            refreshIntervalText(viewModel.effectiveFastInterval(for: provider.id))
        )
    }

    private var keepCheckingExplanation: String {
        String.localizedStringWithFormat(
            String(
                displayLocalized: "Checks %@ for the time you choose, even when usage does not change.",
                bundle: .module
            ),
            refreshIntervalText(viewModel.effectiveFastInterval(for: provider.id))
        )
    }

    private var stopExplanation: String {
        String(
            displayLocalized: """
            Stopping ends the fast checks early. Automatic refresh stays on and the normal \
            Smart timing resumes.
            """,
            bundle: .module
        )
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func extensionStatusText(_ remaining: TimeInterval) -> String {
        String.localizedStringWithFormat(
            String(displayLocalized: "Fast checks for %@ more.", bundle: .module),
            refreshDurationText(remaining)
        )
    }
}

import Core
import SwiftUI

@MainActor
struct RefreshSettingsView: View {
    let viewModel: QuotaViewModel

    var body: some View {
        SettingsScrollColumn {
            SettingsCard(
                heading: String(localized: "Automatic refresh"),
                description: String(
                    localized: "Choose which providers refresh automatically. Mode and intervals control how often."
                )
            ) {
                Picker(String(localized: "Refresh mode"), selection: modeBinding) {
                    Text(String(localized: "Regular")).tag(AutoRefreshMode.regular)
                    Text(String(localized: "Smart")).tag(AutoRefreshMode.smart)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(localized: "Refresh mode"))
                .accessibilityValue(modeDescription)
                .help(String(localized: "Choose a shared cadence for opted-in providers."))

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                intervalControl(
                    title: String(localized: "Slow interval"),
                    values: AutoRefreshPreferences.slowIntervalOptions,
                    selectedValue: viewModel.autoRefreshSlowInterval,
                    setValue: viewModel.setAutoRefreshSlowInterval
                )

                if viewModel.autoRefreshMode == .smart {
                    intervalControl(
                        title: String(localized: "Fast interval"),
                        values: AutoRefreshPreferences.fastIntervalOptions,
                        selectedValue: viewModel.autoRefreshFastInterval,
                        setValue: viewModel.setAutoRefreshFastInterval
                    )
                }
            }

            SettingsCard(
                heading: String(localized: "Providers"),
                description: String(
                    localized: "Turn on automatic refresh for each provider you want to check."
                )
            ) {
                ForEach(viewModel.registeredProvidersOrdered) { provider in
                    providerRow(for: provider)
                    if provider.id != viewModel.registeredProvidersOrdered.last?.id {
                        Divider()
                    }
                }
            }
        }
        .navigationTitle(String(localized: "Refresh Settings"))
    }

    private var modeBinding: Binding<AutoRefreshMode> {
        Binding(
            get: { viewModel.autoRefreshMode },
            set: { viewModel.setAutoRefreshMode($0) }
        )
    }

    private var modeDescription: String {
        switch viewModel.autoRefreshMode {
        case .regular:
            String.localizedStringWithFormat(
                String(localized: "Regular refresh checks opted-in providers every %@."),
                durationText(viewModel.autoRefreshSlowInterval)
            )
        case .smart:
            String.localizedStringWithFormat(
                String(
                    localized: """
                    Smart refresh starts every %@. Usage changes switch that provider to every %@; \
                    three unchanged checks return it to slow.
                    """
                ),
                durationText(viewModel.autoRefreshSlowInterval),
                durationText(viewModel.autoRefreshFastInterval)
            )
        }
    }

    private func intervalControl(
        title: String,
        values: [TimeInterval],
        selectedValue: TimeInterval,
        setValue: @escaping (TimeInterval) -> Void
    ) -> some View {
        let selectedIndex = values.firstIndex(of: selectedValue) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(durationText(selectedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(
                value: Binding(
                    get: { Double(selectedIndex) },
                    set: { index in
                        let resolvedIndex = min(
                            max(Int(index.rounded()), 0),
                            values.count - 1
                        )
                        setValue(values[resolvedIndex])
                    }
                ),
                in: 0 ... Double(values.count - 1),
                step: 1
            )
            .accessibilityLabel(title)
            .accessibilityValue(durationText(selectedValue))
            .help(
                String.localizedStringWithFormat(
                    String(localized: "Selected interval: %@"),
                    durationText(selectedValue)
                )
            )
        }
    }

    private func providerRow(for provider: ProviderInfo) -> some View {
        let isEnabled = viewModel.isAutoRefreshEnabled(for: provider.id)
        let status = providerStatus(for: provider)
        let disclosureText = automaticRefreshDisclosure(for: provider)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ProviderLogoBadge(glyph: provider.glyph)
                Text(provider.displayName)
                    .font(.headline)
                Spacer()
                Toggle(
                    String(localized: "Automatic refresh"),
                    isOn: Binding(
                        get: { isEnabled },
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

            if let status {
                Label(status, systemImage: providerStatusSymbol(for: provider))
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
        }
        .padding(.vertical, 2)
    }

    private func providerStatus(for provider: ProviderInfo) -> String? {
        guard viewModel.isEnabled(provider.id) else {
            return String(localized: "Automatic refresh is paused because this provider is disabled.")
        }
        guard QuotaViewModel.isConfiguredState(viewModel.providerStates[provider.id]) else {
            return String(localized: "Automatic refresh is waiting for setup.")
        }
        return nil
    }

    private func automaticRefreshDisclosure(for provider: ProviderInfo) -> String? {
        provider.automaticRefreshDisclosure.map {
            String.localizedStringWithFormat(
                String(
                    localized: """
                    %1$@ runs %2$@ in the background. These checks may use some of your \
                    %3$@ quota. Shorter Smart intervals can increase the number of checks.
                    """
                ),
                provider.displayName,
                $0.command,
                $0.quotaName
            )
        }
    }

    private func providerStatusSymbol(for provider: ProviderInfo) -> String {
        viewModel.isEnabled(provider.id) ? "clock" : "pause.circle"
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        if seconds < 60 {
            return String.localizedStringWithFormat(
                String(localized: "%lld seconds"),
                seconds
            )
        }

        let minutes = seconds / 60
        if minutes == 1 {
            return String(localized: "1 minute")
        }
        return String.localizedStringWithFormat(
            String(localized: "%lld minutes"),
            minutes
        )
    }
}

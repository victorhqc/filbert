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

                    intervalControl(
                        title: String(localized: "Quiet window"),
                        values: AutoRefreshPreferences.quietWindowOptions,
                        selectedValue: viewModel.autoRefreshQuietWindow,
                        setValue: viewModel.setAutoRefreshQuietWindow
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
                    RefreshSettingsProviderRow(viewModel: viewModel, provider: provider)
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
                refreshDurationText(viewModel.autoRefreshSlowInterval)
            )
        case .smart:
            String.localizedStringWithFormat(
                String(
                    localized: """
                    Smart refresh checks every %1$@. After a usage change, a provider checks every %2$@ \
                    for %3$@, then every %4$@ once more before returning to the slow interval.
                    """
                ),
                refreshDurationText(viewModel.autoRefreshSlowInterval),
                refreshDurationText(viewModel.autoRefreshFastInterval),
                refreshDurationText(viewModel.autoRefreshQuietWindow),
                refreshDurationText(viewModel.autoRefreshCooldownInterval)
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
                Text(refreshDurationText(selectedValue))
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
            .accessibilityValue(refreshDurationText(selectedValue))
            .help(
                String.localizedStringWithFormat(
                    String(localized: "Selected interval: %@"),
                    refreshDurationText(selectedValue)
                )
            )
        }
    }
}

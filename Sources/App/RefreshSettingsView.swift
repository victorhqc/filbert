import Core
import SwiftUI

@MainActor
struct RefreshSettingsView: View {
    let viewModel: QuotaViewModel

    var body: some View {
        SettingsScrollColumn {
            SettingsCard(
                heading: String(displayLocalized: "Automatic refresh", bundle: .module),
                description: String(
                    displayLocalized: """
                    Choose which providers refresh automatically. Mode and intervals control how often.
                    """,
                    bundle: .module
                )
            ) {
                Picker(String(displayLocalized: "Refresh mode", bundle: .module), selection: modeBinding) {
                    Text(String(displayLocalized: "Regular", bundle: .module)).tag(AutoRefreshMode.regular)
                    Text(String(displayLocalized: "Smart", bundle: .module)).tag(AutoRefreshMode.smart)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(String(displayLocalized: "Refresh mode", bundle: .module))
                .accessibilityValue(modeDescription)
                .help(String(displayLocalized: "Choose a shared cadence for opted-in providers.", bundle: .module))

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                intervalControl(
                    title: String(displayLocalized: "Slow interval", bundle: .module),
                    values: AutoRefreshPreferences.slowIntervalOptions,
                    selectedValue: viewModel.autoRefreshSlowInterval,
                    setValue: viewModel.setAutoRefreshSlowInterval
                )

                if viewModel.autoRefreshMode == .smart {
                    intervalControl(
                        title: String(displayLocalized: "Fast interval", bundle: .module),
                        values: AutoRefreshPreferences.fastIntervalOptions,
                        selectedValue: viewModel.autoRefreshFastInterval,
                        setValue: viewModel.setAutoRefreshFastInterval
                    )

                    intervalControl(
                        title: String(displayLocalized: "Fast-check duration", bundle: .module),
                        values: AutoRefreshPreferences.quietWindowOptions,
                        selectedValue: viewModel.autoRefreshQuietWindow,
                        setValue: viewModel.setAutoRefreshQuietWindow
                    )
                }
            }

            SettingsCard(
                heading: String(displayLocalized: "Providers", bundle: .module),
                description: String(
                    displayLocalized: "Turn on automatic refresh for each provider you want to check.",
                    bundle: .module
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
        .navigationTitle(String(displayLocalized: "Refresh Settings", bundle: .module))
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
                String(displayLocalized: "Regular refresh checks opted-in providers every %@.", bundle: .module),
                refreshDurationText(viewModel.autoRefreshSlowInterval)
            )
        case .smart:
            String.localizedStringWithFormat(
                String(
                    displayLocalized: """
                    Smart refresh checks every %1$@. After a usage change, a provider checks every %2$@ \
                    for %3$@, then every %4$@ for another %3$@ before returning to the slow interval.
                    """,
                    bundle: .module
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
                    String(displayLocalized: "Selected interval: %@", bundle: .module),
                    refreshDurationText(selectedValue)
                )
            )
        }
    }
}

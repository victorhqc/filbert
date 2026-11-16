import Core
import SwiftUI

@MainActor
struct UsageChecksSettingsSection: View {
    let viewModel: QuotaViewModel

    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    var body: some View {
        Section {
            DurationMenuPicker(
                title: String(displayLocalized: "Check every", bundle: .module),
                presets: SettingsDurationOptions.slowIntervalPresets,
                selection: viewModel.autoRefreshSlowInterval,
                onSelect: viewModel.setAutoRefreshSlowInterval
            )

            LabeledContent {
                Toggle(checksFasterLabel, isOn: checksFasterBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text(checksFasterLabel)
                    SettingsInfoButton(
                        label: String(displayLocalized: "About faster checks", bundle: .module),
                        explanation: fasterChecksExplanation
                    )
                }
            }

            if viewModel.autoRefreshMode == .smart {
                DurationMenuPicker(
                    title: String(displayLocalized: "Faster checks every", bundle: .module),
                    presets: SettingsDurationOptions.fastIntervalPresets,
                    selection: viewModel.autoRefreshFastInterval,
                    onSelect: viewModel.setAutoRefreshFastInterval
                )

                DurationMenuPicker(
                    title: String(displayLocalized: "Stay fast for", bundle: .module),
                    presets: SettingsDurationOptions.quietWindowPresets,
                    selection: viewModel.autoRefreshQuietWindow,
                    onSelect: viewModel.setAutoRefreshQuietWindow
                )
            }
        } header: {
            Text(String(displayLocalized: "Usage checks", bundle: .module))
        } footer: {
            Button {
                navigation?.open(SettingsDestination(tab: .providers))
            } label: {
                Label(
                    String(displayLocalized: "Turn checks on for each provider in Providers.", bundle: .module),
                    systemImage: "arrow.right.circle"
                )
                .multilineTextAlignment(.leading)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    private var checksFasterLabel: String {
        String(displayLocalized: "Check faster while you work", bundle: .module)
    }

    private var checksFasterBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoRefreshMode == .smart },
            set: { viewModel.setAutoRefreshMode($0 ? .smart : .regular) }
        )
    }

    private var fasterChecksExplanation: String {
        String.localizedStringWithFormat(
            String(
                displayLocalized: """
                When a provider's usage changes, Filbert checks it %1$@ for %2$@, then %3$@ for another %2$@. \
                Then it goes back to checking %4$@.
                """,
                bundle: .module
            ),
            refreshIntervalText(viewModel.autoRefreshFastInterval),
            refreshDurationText(viewModel.autoRefreshQuietWindow),
            refreshIntervalText(viewModel.autoRefreshCooldownInterval),
            refreshIntervalText(viewModel.autoRefreshSlowInterval)
        )
    }
}

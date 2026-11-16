import Core
import SwiftUI

@MainActor
struct ProviderUsageChecksSection: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo
    let isActivityDetectionFocused: AccessibilityFocusState<Bool>.Binding

    /// Re-reads the fast-check countdown, which the view model does not publish
    /// on each passing minute.
    @State private var clockTick = 0

    var body: some View {
        _ = clockTick
        return Section {
            Toggle(
                isOn: Binding(
                    get: { isAutoRefreshEnabled },
                    set: { viewModel.setAutoRefreshEnabled($0, for: provider.id) }
                )
            ) {
                Text(String(displayLocalized: "Check automatically", bundle: .module))
            }
            .toggleStyle(.switch)
            .accessibilityLabel(String.localizedStringWithFormat(
                String(displayLocalized: "Check %@ automatically", bundle: .module),
                provider.displayName
            ))
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    clockTick &+= 1
                }
            }

            if isConfigured, let status = viewModel.activityDetection.statuses[provider.id] {
                ActivityDetectionRow(
                    viewModel: viewModel,
                    provider: provider,
                    presentation: ActivityDetectionPresentation(status: status, providerName: provider.displayName)
                )
                .id(ProviderSettingsPage.activityDetectionRowId)
                .accessibilityFocused(isActivityDetectionFocused)
            }

            if showsFastChecks {
                fastCheckStatus
                keepCheckingRow
            }
        } header: {
            Text(String(displayLocalized: "Usage checks", bundle: .module))
        } footer: {
            footer
        }
    }

    private var isAutoRefreshEnabled: Bool {
        viewModel.isAutoRefreshEnabled(for: provider.id)
    }

    private var isConfigured: Bool {
        QuotaViewModel.isConfiguredState(viewModel.providerStates[provider.id])
    }

    private var showsFastChecks: Bool {
        viewModel.autoRefreshMode == .smart && isAutoRefreshEnabled && isConfigured
    }

    @ViewBuilder
    private var fastCheckStatus: some View {
        if let remaining = viewModel.smartExtensionRemaining(for: provider.id) {
            HStack(spacing: 10) {
                Label(
                    String.localizedStringWithFormat(
                        String(displayLocalized: "Fast checks for %@ more.", bundle: .module),
                        refreshDurationText(remaining)
                    ),
                    systemImage: "bolt.fill"
                )
                .foregroundStyle(.secondary)
                Spacer()
                Button(String(displayLocalized: "Stop fast checks", bundle: .module)) {
                    viewModel.stopSmartExtension(for: provider.id)
                }
                .help(stopExplanation)
                .accessibilityHint(stopExplanation)
            }
        } else if viewModel.isFastAutomaticRefreshActive(for: provider.id) {
            Label(
                String(displayLocalized: "Fast checks are on due to recent activity.", bundle: .module),
                systemImage: "bolt.fill"
            )
            .foregroundStyle(.secondary)
        }
    }

    private var keepCheckingRow: some View {
        LabeledContent(String(displayLocalized: "Keep checking fast", bundle: .module)) {
            Menu(String(displayLocalized: "Choose…", bundle: .module)) {
                ForEach(AutoRefreshPreferences.smartExtensionOptions, id: \.self) { duration in
                    Button(refreshDurationText(duration)) {
                        viewModel.startSmartExtension(for: provider.id, duration: duration)
                    }
                }
            }
            .fixedSize()
            .accessibilityLabel(String.localizedStringWithFormat(
                String(displayLocalized: "Keep checking %@", bundle: .module),
                provider.displayName
            ))
            .accessibilityHint(keepCheckingExplanation)
        }
        .help(keepCheckingExplanation)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !isConfigured {
                SettingsCaption(String(displayLocalized: "Automatic checks start after setup.", bundle: .module))
            }
            if showsFastChecks, let limit = providerLimitText {
                SettingsCaption(limit)
            }
            if showsFastChecks, viewModel.fastRefreshMatchesSlowInterval(for: provider.id) {
                SettingsCaption(String(
                    displayLocalized: """
                    Fast and slow checks use the same interval, so fast checks are not more frequent.
                    """,
                    bundle: .module
                ))
            }
            if let costText {
                Label(costText, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var providerLimitText: String? {
        guard viewModel.providerMinimumIntervalOverridesFastRefresh(for: provider.id) else {
            return nil
        }
        return String.localizedStringWithFormat(
            String(displayLocalized: "Provider limit: checks no more often than %@.", bundle: .module),
            refreshIntervalText(viewModel.effectiveFastInterval(for: provider.id))
        )
    }

    private var costText: String? {
        if let command = provider.automaticRefreshDisclosure {
            return String.localizedStringWithFormat(
                String(displayLocalized: "Each check runs %1$@ and may use some of your %2$@ quota.", bundle: .module),
                command.command,
                command.quotaName
            )
        }
        return switch provider.refreshCharacteristics.costEvidence {
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
            displayLocalized: "Stopping ends the fast checks early. Automatic checks stay on.",
            bundle: .module
        )
    }
}

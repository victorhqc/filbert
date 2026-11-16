import Core
import SwiftUI

@MainActor
struct ActivityDetectionRow: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo
    let presentation: ActivityDetectionPresentation

    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?

    private var model: ActivityDetectionModel {
        viewModel.activityDetection
    }

    private var isBusy: Bool {
        model.busyProviderIds.contains(provider.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 4) {
                    Text(String(displayLocalized: "Activity detection", bundle: .module))
                    SettingsInfoButton(
                        label: String(displayLocalized: "About activity detection", bundle: .module),
                        explanation: explanation
                    )
                }
                Spacer(minLength: 8)
                Label(presentation.summary, systemImage: presentation.symbol)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                actionButton
            }
            if let detail = presentation.detail {
                SettingsCaption(detail)
            }
            if isBusy {
                SettingsWorkingIndicator()
            }
            if let error = model.errors[provider.id] {
                SettingsErrorMessage(message: error.resolved, errorLog: viewModel.errorLog)
            }
            if !viewModel.activityDetectionTakesEffect(for: provider.id) {
                noEffectHint
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localizedStringWithFormat(
            String(displayLocalized: "Activity detection for %@", bundle: .module),
            provider.displayName
        ))
    }

    private var explanation: String {
        String.localizedStringWithFormat(
            String(
                displayLocalized: """
                Optional. Filbert can add a small helper to %@ that tells it when you start and finish a task. \
                With it, Filbert checks faster while you work, so the numbers stay up to date. \
                Without it, Filbert checks on its normal schedule.
                """,
                bundle: .module
            ),
            provider.displayName
        )
    }

    @ViewBuilder
    private var actionButton: some View {
        switch presentation.action {
        case .install:
            Button(String(displayLocalized: "Install", bundle: .module)) {
                Task { await model.install(for: provider.id) }
            }
            .disabled(isBusy)
        case .remove:
            Button(String(displayLocalized: "Remove", bundle: .module), role: .destructive) {
                Task { await model.remove(for: provider.id) }
            }
            .disabled(isBusy)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private var noEffectHint: some View {
        if viewModel.autoRefreshMode != .smart {
            Button {
                navigation?.open(SettingsDestination(tab: .general))
            } label: {
                Label(
                    String(
                        displayLocalized: "Works when “Check faster while you work” is on in General.",
                        bundle: .module
                    ),
                    systemImage: "arrow.right.circle"
                )
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.link)
            .font(.caption)
            .accessibilityHint(String(displayLocalized: "Opens the General settings.", bundle: .module))
        } else {
            SettingsCaption(String(displayLocalized: "Works when Check automatically is on.", bundle: .module))
        }
    }
}

import Core
import SwiftUI

@MainActor
struct ActivityDetectionSection: View {
    let viewModel: QuotaViewModel
    let provider: ProviderInfo
    let focus: AccessibilityFocusState<String?>.Binding

    @Environment(SettingsNavigation.self) private var navigation: SettingsNavigation?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isShowingExplanation = false

    private var model: ActivityDetectionModel {
        viewModel.activityDetection
    }

    var body: some View {
        if isVisible, let status = model.statuses[provider.id] {
            content(ActivityDetectionPresentation(status: status, providerName: provider.displayName))
        }
    }

    private var isVisible: Bool {
        viewModel.isEnabled(provider.id)
            && QuotaViewModel.isConfiguredState(viewModel.providerStates[provider.id])
    }

    private func content(_ presentation: ActivityDetectionPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(spacing: 4) {
                Text(String(displayLocalized: "Activity detection", bundle: .module))
                    .font(.subheadline.weight(.semibold))
                explanationButton
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(presentation.summary, systemImage: presentation.symbol)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                actionButton(presentation.action)
            }
            if let detail = presentation.detail {
                caption(detail)
            }
            if model.busyProviderIds.contains(provider.id) {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    caption(String(displayLocalized: "Working…", bundle: .module))
                }
            }
            if let error = model.errors[provider.id] {
                Label(error.resolved, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ProviderVisualStyle.tierColor(.critical, scheme: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                ErrorLogLink(errorLog: viewModel.errorLog)
            }
            if !viewModel.activityDetectionTakesEffect(for: provider.id) {
                smartScheduleLink
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String.localizedStringWithFormat(
            String(displayLocalized: "Activity detection for %@", bundle: .module),
            provider.displayName
        ))
        .accessibilityFocused(focus, equals: provider.id)
    }

    private var explanationButton: some View {
        Button {
            isShowingExplanation.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help(String(displayLocalized: "About activity detection", bundle: .module))
        .accessibilityLabel(String(displayLocalized: "About activity detection", bundle: .module))
        .popover(isPresented: $isShowingExplanation, arrowEdge: .bottom) {
            Text(explanation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 320, alignment: .leading)
                .padding(14)
        }
    }

    private var explanation: String {
        String.localizedStringWithFormat(
            String(
                displayLocalized: """
                Optional. Filbert can add a small helper to %@ that tells it when you start and finish a task. \
                With it, the Smart schedule checks your usage while you work, so the numbers stay up to date. \
                Without it, Filbert checks on its normal schedule.
                """,
                bundle: .module
            ),
            provider.displayName
        )
    }

    @ViewBuilder
    private func actionButton(_ action: ActivityDetectionPresentation.Action?) -> some View {
        switch action {
        case .install:
            Button(String(displayLocalized: "Install", bundle: .module)) {
                Task { await model.install(for: provider.id) }
            }
            .controlSize(.small)
            .disabled(model.busyProviderIds.contains(provider.id))
        case .remove:
            Button(String(displayLocalized: "Remove", bundle: .module), role: .destructive) {
                Task { await model.remove(for: provider.id) }
            }
            .controlSize(.small)
            .disabled(model.busyProviderIds.contains(provider.id))
        case .none:
            EmptyView()
        }
    }

    private var smartScheduleLink: some View {
        Button {
            navigation?.open(SettingsDestination(tab: .refresh))
        } label: {
            Label(
                String(
                    displayLocalized: "Activity detection works only with automatic checks on the Smart schedule.",
                    bundle: .module
                ),
                systemImage: "arrow.right.circle"
            )
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(.link)
        .font(.caption)
        .accessibilityHint(String(displayLocalized: "Opens the Usage Checks settings.", bundle: .module))
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

import AppKit
import Core
import SwiftUI

// MARK: - Multi-provider quota popover

@MainActor
struct QuotaView: View {
    let viewModel: QuotaViewModel
    let sleepPrevention: SleepPreventionController
    let updateCoordinator: UpdateCoordinator

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.hasAnyConfiguredProvider {
                emptyState
            } else {
                // No ScrollView: MenuBarExtra's window-style popover collapses it to zero height.
                ForEach(viewModel.configuredProviderIds, id: \.self) { providerId in
                    if let state = viewModel.providerStates[providerId] {
                        providerSection(providerId: providerId, state: state)
                    }
                }
            }

            if sleepPrevention.isFeatureVisible {
                Divider()

                SleepPreventionRow(controller: sleepPrevention)
            }

            Divider()

            footer
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(String(displayLocalized: "No providers configured", bundle: .module))
                .font(.headline)

            Text(String(displayLocalized: "Open Settings to add your first AI provider.", bundle: .module))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(String(displayLocalized: "Open Settings", bundle: .module))
                .openAndRaiseSettings()
        }
        .padding(.vertical, 16)
    }

    // MARK: - Setup

    private func setupContent(_ reason: String, providerId _: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Loading

    private var loadingContent: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
                .padding(.trailing, 4)
            Text(String(displayLocalized: "Loading…", bundle: .module))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Quota content

    private func quotaContent(_ quota: ProviderQuota, providerId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            QuotaHeadlineAndRows(
                viewModel: viewModel,
                providerId: providerId,
                quota: quota,
                lines: rowLines(for: quota),
                headlineColor: headlineBalanceColor(for: quota)
            )

            if let peakConfig = quota.peakHoursConfig {
                PeakHoursBlock(config: peakConfig)
                    .padding(.top, 2)
            }

            if quota.isStale {
                staleCacheHint(quota)
            }

            if let guidance = quota.error {
                Text(guidance.resolved)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                lastUpdatedLabel(quota)
            }
        }
        .padding(.bottom, 4)
    }

    private func refreshButton(for providerId: String, state: ProviderState) -> some View {
        Button {
            viewModel.manualRefresh(for: providerId)
        } label: {
            RefreshIcon(isRefreshing: viewModel.isRefreshing[providerId] ?? false)
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .help(refreshHelp(for: providerId, defaultHelp: String(displayLocalized: "Check usage now", bundle: .module)))
        .disabled(isRefreshDisabled(providerId: providerId, state: state))
    }

    private func isRefreshDisabled(providerId: String, state: ProviderState) -> Bool {
        if viewModel.isRefreshing[providerId] == true {
            return true
        }
        if case .loading = state {
            return true
        }
        return viewModel.manualRefreshWaitRemaining(for: providerId) != nil
    }

    private func refreshHelp(for providerId: String, defaultHelp: String) -> String {
        guard let remaining = viewModel.manualRefreshWaitRemaining(for: providerId) else {
            return defaultHelp
        }
        let wholeMinutes = max((remaining / 60).rounded(.up), 1) * 60
        let duration = CoarseDurationFormatting.string(from: wholeMinutes, unitsStyle: .full)
        return String(
            displayLocalized: "The provider asked Filbert to wait. Try again in \(duration).",
            bundle: .module
        )
    }

    private func headerErrorMessage(providerId: String, state: ProviderState) -> String? {
        if let refreshError = viewModel.refreshErrors[providerId] {
            return refreshError.resolved
        }
        if case let .error(message) = state {
            return message.resolved
        }
        return nil
    }

    private func errorContent(_ message: String, providerId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if viewModel.canInstallHelper(for: providerId) {
                Button(String(displayLocalized: "Install Helper", bundle: .module)) {
                    Task { await viewModel.installHelper(for: providerId) }
                }
            } else if viewModel.isReadyToFetch(providerId) {
                Button(String(displayLocalized: "Retry", bundle: .module)) {
                    viewModel.manualRefresh(for: providerId)
                }
                .help(refreshHelp(for: providerId, defaultHelp: String(displayLocalized: "Retry", bundle: .module)))
                .disabled(
                    viewModel.isRefreshing[providerId] == true
                        || viewModel.manualRefreshWaitRemaining(for: providerId) != nil
                )
            } else {
                Text(String(displayLocalized: "Open Settings", bundle: .module))
                    .openAndRaiseSettings()
            }
            ErrorLogLink(errorLog: viewModel.errorLog)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func lastUpdatedLabel(_ quota: ProviderQuota) -> some View {
        let relative = quota.lastUpdated.formatted(.relative(presentation: .named).locale(DisplayLanguage.locale))
        Text(String(displayLocalized: "Last updated: \(relative)", bundle: .module))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Stale-cache hint

    @ViewBuilder
    private func staleCacheHint(_ quota: ProviderQuota) -> some View {
        let relative = quota.lastUpdated.formatted(.relative(presentation: .named).locale(DisplayLanguage.locale))
        VStack(alignment: .leading, spacing: 2) {
            Text(String(displayLocalized: "Last updated by \(quota.providerName): \(relative)", bundle: .module))
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(displayLocalized: "Open \(quota.providerName) to get newer usage", bundle: .module))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func rowLines(for quota: ProviderQuota) -> [UsageLine] {
        guard let layout = FallbackPoolLayout(lines: quota.lines) else {
            return visibleUsageLines(quota.lines)
        }
        return [layout.poolLine()] + visibleUsageLines(layout.otherLines)
    }

    private func headlineBalanceColor(for quota: ProviderQuota) -> Color? {
        QuotaStatusResolver.firstCurrencyBalance(in: quota.lines).map {
            ProviderVisualStyle.balanceTierColor($0, scheme: colorScheme)
        }
    }
}

// MARK: - Per-provider card

private extension QuotaView {
    @ViewBuilder
    func providerSection(providerId: String, state: ProviderState) -> some View {
        if let info = viewModel.providerInfo(for: providerId) {
            let collapsed = viewModel.isCollapsed(providerId)
            let fastRefreshStatus = viewModel.isFastAutomaticRefreshActive(for: providerId)
                ? String(displayLocalized: "Fast checks on", bundle: .module)
                : nil
            VStack(alignment: .leading, spacing: 8) {
                providerHeader(
                    info: info,
                    state: state,
                    collapsed: collapsed,
                    fastRefreshStatus: fastRefreshStatus
                )

                if !collapsed {
                    providerBody(providerId: providerId, state: state)
                } else if case let .error(message) = state {
                    errorContent(message.resolved, providerId: providerId)
                }

                if let message = viewModel.refreshErrors[providerId] {
                    Label(message.resolved, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ErrorLogLink(errorLog: viewModel.errorLog)
                }
            }
            .padding(8)
            .background(
                ProviderVisualStyle.neutralContainerFill,
                in: RoundedRectangle(cornerRadius: ProviderVisualStyle.cardCornerRadius)
            )
        }
    }

    func providerHeader(
        info: ProviderInfo,
        state: ProviderState,
        collapsed: Bool,
        fastRefreshStatus: String?
    ) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    viewModel.toggleCollapsed(info.id)
                }
            } label: {
                providerHeaderLabel(
                    info: info,
                    state: state,
                    collapsed: collapsed,
                    fastRefreshStatus: fastRefreshStatus
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                headerAccessibilityLabel(
                    info: info,
                    state: state,
                    collapsed: collapsed,
                    fastRefreshStatus: fastRefreshStatus
                )
            )
            .accessibilityValue(
                collapsed
                    ? String(displayLocalized: "Collapsed", bundle: .module)
                    : String(displayLocalized: "Expanded", bundle: .module)
            )
            .accessibilityAction(
                named: collapsed
                    ? String(displayLocalized: "Expand", bundle: .module)
                    : String(displayLocalized: "Collapse", bundle: .module)
            ) {
                viewModel.toggleCollapsed(info.id)
            }

            if let message = headerErrorMessage(providerId: info.id, state: state) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .font(.caption2)
                    .help(message)
            }

            refreshButton(for: info.id, state: state)
        }
    }

    private func providerHeaderLabel(
        info: ProviderInfo,
        state: ProviderState,
        collapsed: Bool,
        fastRefreshStatus: String?
    ) -> some View {
        HStack(spacing: 7) {
            ProviderLogoBadge(glyph: info.glyph)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if let fastRefreshStatus {
                    Label(fastRefreshStatus, systemImage: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if collapsed, case let .loaded(quota) = state {
                CompactProviderStatus(quota: quota)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .rotationEffect(.degrees(collapsed ? 0 : 90))
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func providerBody(providerId: String, state: ProviderState) -> some View {
        switch state {
        case .unconfigured:
            EmptyView()
        case let .setup(reason):
            setupContent(reason.resolved, providerId: providerId)
        case .loading:
            loadingContent
        case let .loaded(quota):
            quotaContent(quota, providerId: providerId)
        case let .error(message):
            errorContent(message.resolved, providerId: providerId)
        }
    }
}

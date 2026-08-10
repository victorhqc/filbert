import AppKit
import Core
import SwiftUI

// MARK: - Multi-provider quota popover

@MainActor
struct QuotaView: View {
    let viewModel: QuotaViewModel

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

            Divider()

            HStack {
                Text(String(localized: "Settings…"))
                    .font(.caption)
                    .openAndRaiseSettings()

                Spacer()

                Button(String(localized: "Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
                .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(String(localized: "No providers configured"))
                .font(.headline)

            Text(String(localized: "Open Settings to add your first AI provider."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(String(localized: "Open Settings"))
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
            Text(String(localized: "Loading…"))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Quota content

    private func quotaContent(_ quota: ProviderQuota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(quota.headline)
                    .font(.headline)
                if let color = headlineBalanceColor(for: quota) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 2)

            // balance-only lines with non-positive or duplicate totals are filtered out before ForEach.
            ForEach(renderedLines(quota.lines), id: \.label) { line in
                usageLineRow(line)
            }

            // `lastUpdated` forces SwiftUI to re-evaluate the block on every
            // refresh so the in-peak / off-peak status always uses the current time.
            if let peakConfig = quota.peakHoursConfig {
                PeakHoursBlock(config: peakConfig, lastUpdated: quota.lastUpdated)
                    .padding(.top, 2)
            }

            if quota.isStale {
                staleCacheHint(quota)
            }

            lastUpdatedLabel(quota)
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
        .help(String(localized: "Refresh"))
        .disabled(isRefreshDisabled(providerId: providerId, state: state))
    }

    private func isRefreshDisabled(providerId: String, state: ProviderState) -> Bool {
        if viewModel.isRefreshing[providerId] == true {
            return true
        }
        if case .loading = state {
            return true
        }
        return false
    }

    private func headerErrorMessage(providerId: String, state: ProviderState) -> String? {
        if let refreshError = viewModel.refreshErrors[providerId] {
            return refreshError
        }
        if case let .error(message) = state {
            return message
        }
        return nil
    }

    private func headerAccessibilityLabel(
        info: ProviderInfo,
        state: ProviderState,
        collapsed: Bool,
        fastRefreshStatus: String?
    ) -> String {
        let headerLabel: String
        guard collapsed, case let .loaded(quota) = state else {
            headerLabel = info.displayName
            return headerAccessibilityLabel(headerLabel, fastRefreshStatus: fastRefreshStatus)
        }

        switch QuotaStatusResolver.resolve(for: quota) {
        case let .window(percentage):
            headerLabel = String(localized: "\(info.displayName): \(Int(percentage.rounded()))% used")
        case let .balance(_, _, formattedAmount):
            headerLabel = String(localized: "\(info.displayName): \(formattedAmount) remaining")
        case .fallback:
            headerLabel = info.displayName
        }
        return headerAccessibilityLabel(headerLabel, fastRefreshStatus: fastRefreshStatus)
    }

    private func headerAccessibilityLabel(_ headerLabel: String, fastRefreshStatus: String?) -> String {
        guard let fastRefreshStatus else { return headerLabel }
        return String.localizedStringWithFormat(
            String(localized: "%1$@. %2$@"),
            headerLabel,
            fastRefreshStatus
        )
    }

    private func usageLineRow(_ line: UsageLine) -> some View {
        UsageLineRow(line: line)
    }

    // MARK: - Error

    private func errorContent(_ message: String, providerId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(String(localized: "Retry")) {
                viewModel.manualRefresh(for: providerId)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Last updated

    @ViewBuilder
    private func lastUpdatedLabel(_ quota: ProviderQuota) -> some View {
        let relative = quota.lastUpdated.formatted(.relative(presentation: .named))
        Text(String(localized: "Last updated: \(relative)"))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Stale-cache hint

    @ViewBuilder
    private func staleCacheHint(_ quota: ProviderQuota) -> some View {
        let relative = quota.lastUpdated.formatted(.relative(presentation: .named))
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Last updated by \(quota.providerName): \(relative)"))
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(String(localized: "Open \(quota.providerName) to refresh"))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func percentage(for line: UsageLine) -> Double? {
        QuotaStatusResolver.percentage(for: line)
    }

    private func renderedLines(_ lines: [UsageLine]) -> [UsageLine] {
        filteredBalanceLines(lines, isPercentageLine: { percentage(for: $0) != nil })
    }

    private func headlineBalanceColor(for quota: ProviderQuota) -> Color? {
        guard let line = quota.lines.first(where: { percentage(for: $0) == nil }),
              let total = line.total
        else {
            return nil
        }
        return ProviderVisualStyle.balanceTierColor(total, scheme: colorScheme)
    }
}

// MARK: - Per-provider card

private extension QuotaView {
    @ViewBuilder
    func providerSection(providerId: String, state: ProviderState) -> some View {
        if let info = viewModel.providerInfo(for: providerId) {
            let collapsed = viewModel.isCollapsed(providerId)
            let fastRefreshStatus = viewModel.isFastAutomaticRefreshActive(for: providerId)
                ? String(localized: "Fast refresh active")
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
            .buttonStyle(.plain)
            .accessibilityLabel(
                headerAccessibilityLabel(
                    info: info,
                    state: state,
                    collapsed: collapsed,
                    fastRefreshStatus: fastRefreshStatus
                )
            )
            .accessibilityValue(collapsed ? String(localized: "Collapsed") : String(localized: "Expanded"))
            .accessibilityAction(
                named: collapsed ? String(localized: "Expand") : String(localized: "Collapse")
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

    @ViewBuilder
    func providerBody(providerId: String, state: ProviderState) -> some View {
        switch state {
        case .unconfigured:
            EmptyView()
        case let .setup(reason):
            setupContent(reason, providerId: providerId)
        case .loading:
            loadingContent
        case let .loaded(quota):
            quotaContent(quota)
        case let .error(message):
            errorContent(message, providerId: providerId)
        }
    }
}

private struct CompactProviderStatus: View {
    let quota: ProviderQuota

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            compactStatus(at: context.date)
        }
    }

    @ViewBuilder
    private func compactStatus(at now: Date) -> some View {
        let status = QuotaStatusResolver.resolve(for: quota)
        let tier = QuotaStatusResolver.compactTier(for: quota, at: now)
        switch status {
        case let .window(percentage):
            if let tier {
                HStack(spacing: 4) {
                    compactRing(
                        percentage: percentage,
                        color: ProviderVisualStyle.tierColor(tier, scheme: colorScheme)
                    )
                    Text(String(format: "%.0f%%", percentage))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ProviderVisualStyle.tierColor(tier, scheme: colorScheme))
                }
                .accessibilityHidden(true)
            }
        case let .balance(_, _, formattedAmount):
            if let tier {
                HStack(spacing: 4) {
                    Circle()
                        .fill(ProviderVisualStyle.tierColor(tier, scheme: colorScheme))
                        .frame(width: 7, height: 7)
                    Text(formattedAmount)
                        .font(.caption.monospacedDigit())
                }
                .accessibilityHidden(true)
            }
        case .fallback:
            EmptyView()
        }
    }

    private func compactRing(percentage: Double, color: Color) -> some View {
        let fraction = QuotaStatusResolver.clampedFraction(percentage / 100)
        return ZStack {
            Circle()
                .stroke(.secondary.opacity(0.2), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 14, height: 14)
    }
}

/// Dedupes balance rows with the same positive amount — duplicate amounts
/// are visually confusing. Percentage rows always pass.
private func filteredBalanceLines(
    _ lines: [UsageLine],
    isPercentageLine: (UsageLine) -> Bool
) -> [UsageLine] {
    let positiveBalanceTotals = lines.compactMap { line -> Double? in
        guard !isPercentageLine(line) else { return nil }
        guard let total = line.total, total > 0 else { return nil }
        return total
    }
    let cents = positiveBalanceTotals.map { Int(($0 * 100).rounded()) }
    let hasDuplicates = Set(cents).count < cents.count

    var firstBalanceKept = false
    return lines.filter { line in
        guard !isPercentageLine(line) else { return true }
        guard let total = line.total, total > 0 else { return false }
        if hasDuplicates {
            if firstBalanceKept {
                return false
            }
            firstBalanceKept = true
            return true
        }
        return true
    }
}

// MARK: - Peak-hours block

/// Provider-agnostic: all pricing rules come from `config`, so the view has
/// zero knowledge of any specific provider. Computed from `Date()` on each
/// render so the popover stays correct while open.
private struct PeakHoursBlock: View {
    let config: PeakHoursConfig

    /// SwiftUI uses this to decide whether to re-evaluate the block's body —
    /// a new value on each refresh guarantees `Date()` inside `body` is fresh.
    let lastUpdated: Date

    var body: some View {
        let now = Date()
        let inPeak = config.isInPeak(at: now)
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Peak hours"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(localWindowLabel)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Circle()
                    .fill(inPeak ? Color.orange : Color.green)
                    .frame(width: 6, height: 6)
                Text(inPeak
                    ? String(localized: "In peak")
                    : String(localized: "Off peak"))
                    .font(.caption2)
                    .fontWeight(.medium)
                Spacer()
                Text(String(localized: "\(config.multiplier(at: now))× multiplier"))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Derived values

    private var localWindowLabel: String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let localStart = peakWindowBoundary(hour: config.peakStartHour)
        let localEnd = peakWindowBoundary(hour: config.peakEndHour)
        let start = formatter.string(from: localStart)
        let end = formatter.string(from: localEnd)
        return String(localized: "\(start)–\(end) (your time)")
    }

    private func peakWindowBoundary(hour: Int) -> Date {
        guard let tz = config.timeZone else { return Date() }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let today = cal.dateComponents([.year, .month, .day], from: Date())
        var components = DateComponents()
        components.year = today.year
        components.month = today.month
        components.day = today.day
        components.hour = hour
        components.minute = 0
        components.timeZone = tz
        return cal.date(from: components) ?? Date()
    }
}

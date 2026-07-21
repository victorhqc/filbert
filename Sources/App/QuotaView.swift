import Core
import SwiftUI

// MARK: - Multi-provider quota popover (AC4: per-provider sections (ui 02))

@MainActor
struct QuotaView: View {
    let viewModel: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !viewModel.hasAnyConfiguredProvider {
                emptyState
            } else {
                // ScrollView is omitted intentionally — MenuBarExtra's
                // window-style popover collapses ScrollView to zero height.
                // When multiple providers are configured the content is
                // still bounded by the popover's intrinsic sizing.
                ForEach(viewModel.configuredProviderIds, id: \.self) { providerId in
                    if let state = viewModel.providerStates[providerId] {
                        providerSection(providerId: providerId, state: state)
                    }
                }
            }

            Divider()

            HStack {
                SettingsLink {
                    Text(String(localized: "Settings…"))
                        .font(.caption)
                }

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

    // MARK: - Empty state (AC3: no configured providers prompt (ui 02))

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(String(localized: "No providers configured"))
                .font(.headline)

            Text(String(localized: "Open Settings to add your first AI provider."))
                .font(.subheadline)
                .foregroundColor(.secondary)

            SettingsLink {
                Text(String(localized: "Open Settings"))
            }
        }
        .padding(.vertical, 16)
    }

    // MARK: - Per-provider section (AC4/AC6: one section per configured provider (ui 02))

    @ViewBuilder
    private func providerSection(providerId: String, state: ProviderState) -> some View {
        switch state {
        case .unconfigured:
            EmptyView()
        case let .setup(reason):
            setupContent(reason, providerId: providerId)
        case .loading:
            loadingContent
        case let .loaded(quota):
            quotaContent(quota, providerId: providerId)
        case let .error(message):
            errorContent(message, providerId: providerId)
        }
    }

    // MARK: - Setup (core 03 AC6: setup reason for .apiKeyFree providers)

    private func setupContent(_ reason: String, providerId _: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reason)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Loading (AC6: loading indicator (ui 01))

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

    // MARK: - Quota content (AC4: render live quota (ui 01); bars + peak (ui 04))

    private func quotaContent(_ quota: ProviderQuota, providerId: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(quota.providerName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            // AC3: headline gains a tier-indicator Circle for balance-only
            // providers; the dot reflects the first balance line's amount
            // (ui 08). Percentage-based providers have no balance line, so no
            // Circle is drawn.
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

            // AC1: balance-only lines with non-positive or duplicate totals are
            // filtered out before ForEach so SwiftUI sees a stable list (ui 08).
            // The headline still surfaces the total, so a true zero balance is
            // never hidden from the user.
            ForEach(renderedLines(quota.lines), id: \.label) { line in
                usageLineRow(line)
            }

            // AC3: peak-hours block for providers that supply a config (ui 04).
            // Passing lastUpdated ensures SwiftUI re-evaluates the block's
            // body on every refresh so the in-peak / off-peak status always
            // uses the current time.
            if let peakConfig = quota.peakHoursConfig {
                PeakHoursBlock(config: peakConfig, lastUpdated: quota.lastUpdated)
                    .padding(.top, 2)
            }

            // AC9: stale-cache hint for providers that set isStale (ui 05).
            if quota.isStale {
                staleCacheHint(quota)
            }

            Divider()
            HStack {
                lastUpdatedLabel(quota)
                // AC6: non-blocking indicator surfacing the most recent
                // refresh failure while last-known data is still shown (ui 07).
                if let message = viewModel.refreshErrors[providerId] {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                        .font(.caption2)
                        .help(message)
                }

                Spacer()

                Button {
                    viewModel.manualRefresh(for: providerId)
                } label: {
                    // AC5: icon-only Refresh control; tooltip carries the label (ui 04).
                    // AC3/AC4: glyph rotates while the refresh is in flight and the
                    // control is disabled — debounce follows the new flag (ui 07).
                    RefreshIcon(isRefreshing: viewModel.isRefreshing[providerId] ?? false)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(String(localized: "Refresh"))
                .disabled(viewModel.isRefreshing[providerId] ?? false)
            }
        }
        .padding(.bottom, 4)
    }

    private func usageLineRow(_ line: UsageLine) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(line.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let pct = percentage(for: line) {
                    Text(String(format: "%.0f%%", pct))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(percentageColor(pct))
                } else if let amount = amountText(for: line) {
                    // AC3: balance-only row renders only the amount text; the
                    // tier Circle lives on the headline, not on rows (ui 08).
                    Text(amount)
                        .font(.subheadline.monospacedDigit())
                }
            }

            // AC1: horizontal usage bar beneath the label row (ui 04).
            // Balance-only rows get no bar (ui 08 AC3).
            if let pct = percentage(for: line) {
                UsageBar(percentage: pct, color: percentageColor(pct))
            }

            if let resetDate = line.resetDate {
                Text(QuotaFormatting.countdown(to: resetDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let details = line.details, !details.isEmpty {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(details, id: \.label) { detail in
                        HStack {
                            Text(detail.label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(detail.value)
                                .font(.caption2.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 12)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Error (AC6: error with Retry (ui 01))

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

    // MARK: - Last updated (AC5: last updated indicator (ui 01))

    @ViewBuilder
    private func lastUpdatedLabel(_ quota: ProviderQuota) -> some View {
        let relative = quota.lastUpdated.formatted(.relative(presentation: .named))
        Text(String(localized: "Last updated: \(relative)"))
            .font(.caption)
            .foregroundColor(.secondary)
    }

    // MARK: - Stale-cache hint (ui 05 AC9)

    /// Renders two muted lines when the provider flagged its data as stale.
    /// The UI never computes freshness — it reads the flag the provider set
    /// (ui 05 AC9).
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

    /// Green / orange / red tier shared by the percentage number and the bar,
    /// so they can never disagree (ui 04 AC2).
    private func percentageColor(_ pct: Double) -> Color {
        switch pct {
        case ..<50: .green
        case 50 ..< 80: .orange
        default: .red
        }
    }

    /// Forwards to the shared resolver so the popover rows and the menu-bar
    /// icon share one percentage derivation (ui 10 AC3, ui 04 AC1).
    private func percentage(for line: UsageLine) -> Double? {
        QuotaStatusResolver.percentage(for: line)
    }

    /// Filters the provider's lines for display (ui 08 AC1), delegating to
    /// the file-level helper that implements the dedup + non-positive rules.
    private func renderedLines(_ lines: [UsageLine]) -> [UsageLine] {
        filteredBalanceLines(lines, isPercentageLine: { percentage(for: $0) != nil })
    }

    /// Tier color for the headline (ui 08 AC3). Derived from the first
    /// balance-only line's total — the amount the headline summarizes.
    /// Returns nil when the provider has no balance data (percentage-based
    /// providers), so no Circle is drawn.
    private func headlineBalanceColor(for quota: ProviderQuota) -> Color? {
        guard let line = quota.lines.first(where: { percentage(for: $0) == nil }),
              let total = line.total
        else {
            return nil
        }
        return balanceTierColor(total)
    }

    /// Forwards to the shared resolver so the popover rows and the menu-bar
    /// icon share one currency formatter (ui 10 AC4, ui 08 AC3).
    private func amountText(for line: UsageLine) -> String? {
        QuotaStatusResolver.amountText(for: line)
    }
}

// MARK: - Balance tier color (ui 08 AC3)

/// Red / orange / green tier for a balance amount, using the user-configured
/// low/ok thresholds. Red below `low` (almost gone or gone), orange in
/// `[low, ok)` (decreasing), green at or above `ok` (healthy).
private func balanceTierColor(_ total: Double) -> Color {
    switch total {
    case ..<BalanceThresholds.low: .red
    case BalanceThresholds.low ..< BalanceThresholds.ok: .orange
    default: .green
    }
}

/// Filters lines for display (ui 08 AC1). Drops balance-only lines (those for
/// which `isPercentageLine` returns false) with nil or non-positive `total`.
/// When two balance rows share the same positive amount, only the first (the
/// Total balance in DeepSeek's ordering) survives — duplicate amounts are
/// visually confusing and carry no extra information. Percentage rows always
/// pass.
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
            // Keep only the first positive balance line (Total balance).
            if firstBalanceKept {
                return false
            }
            firstBalanceKept = true
            return true
        }
        return true
    }
}

// MARK: - Usage bar (ui 04 AC1/AC2)

/// Thin horizontal progress bar colored by usage tier. Takes the full width
/// its parent gives it, so it auto-fits the popover (ui 04 AC6).
///
/// Avoids `GeometryReader` — inside the `MenuBarExtra` popover it collapses to
/// zero width because the parent `VStack` doesn't propagate a concrete width
/// before sizing the bar. The fill is a full-width `Capsule` scaled to the
/// used fraction with `scaleEffect`, so it tracks whatever width the popover
/// gives the row without measuring it explicitly.
private struct UsageBar: View {
    let percentage: Double
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.secondary.opacity(0.15))
            Capsule()
                .fill(color)
                .scaleEffect(x: clampedFraction, anchor: .leading)
                .opacity(clampedFraction <= 0 ? 0 : 1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel(
            String(localized: "Usage: \(Int(clampedFraction * 100))%")
        )
    }

    private var clampedFraction: Double {
        min(max(percentage / 100, 0), 1)
    }
}

// MARK: - Peak-hours block (ui 04 AC3/AC4)

/// Renders a provider-agnostic peak-hours status block — the peak window
/// converted to local time, a live in-peak / off-peak indicator, and the
/// current multiplier.
///
/// All pricing rules come from the `config` parameter; the view has zero
/// knowledge of any specific provider. Computed from `Date()` on each
/// render so the popover stays correct while open (ui 04 AC4).
private struct PeakHoursBlock: View {
    let config: PeakHoursConfig

    /// The last time the provider quota was refreshed. SwiftUI uses this to
    /// decide whether to re-evaluate the block's body — a new value on each
    /// refresh guarantees `Date()` inside `body` is fresh.
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

    /// Builds a "start–end (your time)" label by computing today's peak window
    /// boundaries in the config's time zone and formatting them locally.
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

    /// Today at `hour:00` in the config's time zone — an absolute instant
    /// that, when formatted with the user's local time zone, shows the
    /// converted time.
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

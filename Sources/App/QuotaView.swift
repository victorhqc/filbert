import Core
import SwiftUI
import ZAIProvider

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
        case .loading:
            loadingContent
        case let .loaded(quota):
            quotaContent(quota, providerId: providerId)
        case let .error(message):
            errorContent(message, providerId: providerId)
        }
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

            Text(quota.headline)
                .font(.headline)
                .padding(.bottom, 2)

            ForEach(quota.lines, id: \.label) { line in
                usageLineRow(line)
            }

            // AC3: peak-hours block only for the z.ai provider (ui 04).
            if showsPeakHoursBlock(for: quota) {
                PeakHoursBlock()
                    .padding(.top, 2)
            }

            Divider()
            HStack {
                lastUpdatedLabel(quota)

                Spacer()

                Button {
                    viewModel.fetchQuota(for: providerId)
                } label: {
                    // AC5: icon-only Refresh control; tooltip carries the label (ui 04).
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help(String(localized: "Refresh"))
                .disabled(ifLoadingState(providerId))

                Button(String(localized: "Clear Key")) {
                    try? viewModel.deleteKey(for: providerId)
                }
                .font(.caption)
            }
        }
        .padding(.bottom, 4)
    }

    private func ifLoadingState(_ providerId: String) -> Bool {
        if case .loading = viewModel.providerStates[providerId] {
            return true
        }
        return false
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
                }
            }

            // AC1: horizontal usage bar beneath the label row (ui 04).
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
                viewModel.fetchQuota(for: providerId)
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

    /// Returns the line's percentage, deriving it from `used / total` when
    /// `percentage` is missing (e.g. monthly web-tool calls). Nil when there
    /// is no usable percentage data — the row then renders text-only (ui 04 AC1).
    private func percentage(for line: UsageLine) -> Double? {
        if let pct = line.percentage {
            return pct
        }
        guard let used = line.used, let total = line.total, total > 0 else {
            return nil
        }
        return min(max(used / total * 100, 0), 100)
    }

    /// The peak-hours block is z.ai-specific; gated by `providerId` so any
    /// future provider is unaffected (ui 04 AC3/AC7).
    private func showsPeakHoursBlock(for quota: ProviderQuota) -> Bool {
        quota.providerId == ZAIProvider.providerId
    }
}

// MARK: - Usage bar (ui 04 AC1/AC2)

/// Thin horizontal progress bar colored by usage tier. Takes the full width
/// its parent gives it, so it auto-fits the popover (ui 04 AC6).
private struct UsageBar: View {
    let percentage: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let fillWidth = max(proxy.size.width * clampedFraction, 2)
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                // Fill
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: fillWidth)
            }
        }
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

// MARK: - Peak-hours block (ui 04 AC3/AC4) — z.ai only

/// Surfaces the GLM Coding Plan's daily peak window (14:00–18:00 UTC+8) in
/// the user's local time, whether they're currently in peak, and the current
/// advanced-model (GLM-5.2 / GLM-5-Turbo) multiplier.
///
/// Rules per zai-bar's published README:
///   - Peak: 14:00–18:00 in Asia/Shanghai (CST, no DST) → 3× multiplier.
///   - Off-peak: 1× until 2026-10-01 (limited-time promo), 2× after.
///
/// Computed from `Date()` on each render so the popover stays correct while
/// open (ui 04 AC4).
private struct PeakHoursBlock: View {
    // Asia/Shanghai is IANA's name for China Standard Time (UTC+8, no DST).
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")
    private let peakStartHour = 14
    private let peakEndHour = 18
    private let promoEndDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantFuture
    }()

    var body: some View {
        let now = Date()
        let inPeak = isInPeak(at: now)
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
                Text(String(localized: "\(multiplier(at: now, inPeak: inPeak))× multiplier"))
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Derived values

    /// "14:00–18:00 (local times)" — converts the UTC+8 boundaries to the
    /// user's local zone and formats with `.hourMinute` so it follows the
    /// system locale.
    private var localWindowLabel: String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short

        let localStart = localBoundary(hour: peakStartHour)
        let localEnd = localBoundary(hour: peakEndHour)
        let start = formatter.string(from: localStart)
        let end = formatter.string(from: localEnd)
        return String(localized: "\(start)–\(end) (your time)")
    }

    /// True iff `date`, interpreted in Asia/Shanghai, falls in `[14:00, 18:00)`.
    private func isInPeak(at date: Date) -> Bool {
        guard let shanghai else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = shanghai
        let hour = cal.component(.hour, from: date)
        return hour >= peakStartHour && hour < peakEndHour
    }

    /// 3× in peak; else 1× while the promo is active, 2× afterwards.
    private func multiplier(at date: Date, inPeak: Bool) -> Int {
        if inPeak {
            return 3
        }
        return date < promoEndDate ? 1 : 2
    }

    /// Today's local-date instant at `hour:00` (e.g. today at 14:00 in the
    /// user's zone). Used purely to format the local-time window label.
    private func localBoundary(hour: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var components = cal.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        return cal.date(from: components) ?? Date()
    }
}

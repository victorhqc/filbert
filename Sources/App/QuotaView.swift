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

    // MARK: - Quota content (AC4: render live quota (ui 01))

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

            Divider()
            HStack {
                lastUpdatedLabel(quota)

                Spacer()

                Button(String(localized: "Refresh")) {
                    viewModel.fetchQuota(for: providerId)
                }
                .font(.caption)
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
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(line.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let pct = line.percentage {
                    Text(String(format: "%.0f%%", pct))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(percentageColor(pct))
                }
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

    private func percentageColor(_ pct: Double) -> Color {
        switch pct {
        case ..<50: .green
        case 50 ..< 80: .orange
        default: .red
        }
    }
}

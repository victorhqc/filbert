import Core
import SwiftUI

@MainActor
struct QuotaView: View {
    let viewModel: QuotaViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let quota = viewModel.quota {
                quotaContent(quota)
            } else if viewModel.isLoading {
                loadingContent
            } else if let error = viewModel.errorMessage {
                errorContent(error)
            }

            // Footer: controls (AC5: manual refresh (ui 01))
            Divider()
            HStack {
                lastUpdatedLabel

                Spacer()

                Button(String(localized: "Refresh")) {
                    viewModel.fetchQuota()
                }
                .disabled(viewModel.isLoading)

                Button(String(localized: "Clear Key")) {
                    try? viewModel.deleteKey()
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Quota content (AC4: render live quota (ui 01))

    private func quotaContent(_ quota: ProviderQuota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(quota.headline)
                .font(.headline)
                .padding(.bottom, 2)

            ForEach(quota.lines, id: \.label) { line in
                usageLineRow(line)
            }
        }
    }

    private func usageLineRow(_ line: UsageLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // Label + percentage
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

            // Reset countdown (same format as headline via QuotaFormatting)
            if let resetDate = line.resetDate {
                Text(QuotaFormatting.countdown(to: resetDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Details (nil omitted, not shown blank — AC4)
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

    // MARK: - Error (AC6: error with Retry (ui 01))

    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Button(String(localized: "Retry")) {
                viewModel.fetchQuota()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Last updated (AC5: last updated indicator (ui 01))

    @ViewBuilder
    private var lastUpdatedLabel: some View {
        if let quota = viewModel.quota {
            let relative = quota.lastUpdated.formatted(.relative(presentation: .named))
            Text(String(localized: "Last updated: \(relative)"))
                .foregroundColor(.secondary)
        }
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

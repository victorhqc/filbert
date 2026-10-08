import Core
import SwiftUI

/// Forecasts age through the timeline. A render never triggers provider work.
struct QuotaHeadlineAndRows: View {
    let viewModel: QuotaViewModel
    let providerId: String
    let quota: ProviderQuota
    let lines: [UsageLine]
    let headlineColor: Color?

    var body: some View {
        if viewModel.hasAllowanceForecasts(for: providerId) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(viewModel.allowanceForecastPresentation(for: quota, providerId: providerId, at: context.date))
            }
        } else {
            content(.empty)
        }
    }

    private func content(_ forecast: AllowanceForecastPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let title = forecast.title {
                    ForecastTitle(title: title)
                } else {
                    Text(quota.headline)
                        .font(.headline)
                }
                if let headlineColor {
                    Circle()
                        .fill(headlineColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 2)

            ForEach(lines, id: \.label) { line in
                UsageLineRow(line: line, forecast: line.id.flatMap { forecast.rowLines[$0] })
            }
        }
    }
}

private struct ForecastTitle: View {
    let title: AllowanceForecastPresentation.Title

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.text)
                .font(.headline)
            Text(title.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.accessibilityLabel)
        .help(title.accessibilityLabel)
    }
}

struct ForecastRowLine: View {
    let line: AllowanceForecastPresentation.Line

    var body: some View {
        Text(line.text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(line.accessibilityLabel)
            .help(line.accessibilityLabel)
    }
}

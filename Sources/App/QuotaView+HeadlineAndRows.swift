import Core
import SwiftUI

struct QuotaHeadlineAndRows: View {
    let viewModel: QuotaViewModel
    let providerId: String
    let quota: ProviderQuota
    let lines: [UsageLine]
    let headlineColor: Color?

    var body: some View {
        let hasForecasts = viewModel.hasAllowanceForecasts(for: providerId)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if hasForecasts {
                    AllowanceForecastTimeline { date in
                        headline(presentation(at: date).headline)
                    }
                } else {
                    headline(nil)
                }
                if let headlineColor {
                    Circle()
                        .fill(headlineColor)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 2)

            ForEach(lines, id: \.label) { line in
                UsageLineRow(line: line, forecast: hasForecasts ? forecastLineSource(for: line) : nil)
            }
        }
    }

    @ViewBuilder
    private func headline(_ forecast: AllowanceForecastPresentation.Headline?) -> some View {
        if let forecast {
            ForecastHeadline(headline: forecast)
        } else {
            Text(quota.headline)
                .font(.headline)
        }
    }

    private func forecastLineSource(for line: UsageLine) -> AllowanceForecastLineSource? {
        guard let id = line.id else { return nil }
        return { date in presentation(at: date).rowLines[id] }
    }

    private func presentation(at date: Date) -> AllowanceForecastPresentation {
        viewModel.allowanceForecastPresentation(for: quota, providerId: providerId, at: date)
    }
}

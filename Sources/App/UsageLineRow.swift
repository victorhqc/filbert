import Core
import Foundation
import SwiftUI

struct UsageLineRow: View {
    let line: UsageLine
    var forecast: AllowanceForecastLineSource?

    var body: some View {
        if shouldUseBudgetPacing {
            PacedUsageLineRow(line: line, forecast: forecast)
        } else {
            StandardUsageLineRow(line: line, forecast: forecast)
        }
    }

    private var shouldUseBudgetPacing: Bool {
        BudgetPace(line: line, now: Date()) != nil
    }
}

private struct StandardUsageLineRow: View {
    let line: UsageLine
    let forecast: AllowanceForecastLineSource?

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(line.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                if let percentage = QuotaStatusResolver.percentage(for: line) {
                    Text(String(format: "%.0f%%", percentage))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(percentageColor(percentage))
                } else if let amount = QuotaStatusResolver.amountText(for: line) {
                    Text(amount)
                        .font(.subheadline.monospacedDigit())
                }
            }

            if let percentage = QuotaStatusResolver.percentage(for: line) {
                UsageBar(percentage: percentage, color: percentageColor(percentage))
            }

            if let forecast {
                AllowanceForecastTimeline { date in
                    if let line = forecast(date) {
                        ForecastRowLine(line: line)
                    }
                }
            }

            if let resetDate = line.resetDate {
                Text(QuotaFormatting.countdown(to: resetDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            UsageDetailsRows(details: line.details)
        }
        .padding(.vertical, 2)
    }

    private func percentageColor(_ percentage: Double) -> Color {
        let tier = QuotaStatusResolver.tier(for: .window(percentage: percentage))
        return ProviderVisualStyle.tierColor(tier ?? .good, scheme: colorScheme)
    }
}

private struct PacedUsageLineRow: View {
    let line: UsageLine
    let forecast: AllowanceForecastLineSource?

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let pace = BudgetPace(line: line, now: context.date) {
                paceContent(pace, forecast: forecast?(context.date))
            } else {
                StandardUsageLineRow(line: line, forecast: forecast)
            }
        }
    }

    private func paceContent(
        _ pace: BudgetPace,
        forecast: AllowanceForecastPresentation.Line?
    ) -> some View {
        let color = ProviderVisualStyle.tierColor(pace.tier, scheme: colorScheme)
        let text = PacedUsageLineText(pace: pace, forecast: forecast)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(line.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(text.used)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(color)
            }

            BudgetPaceBar(pace: pace, color: color)

            if let forecast {
                ForecastRowLine(line: forecast)
            }

            HStack(spacing: 8) {
                Text(text.remainingTime)
                Spacer(minLength: 4)
                Text(text.allowance)
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)

            UsageDetailsRows(details: line.details)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.label)
        .accessibilityValue(text.accessibilityValue)
    }
}

private struct UsageDetailsRows: View {
    let details: [UsageDetail]?

    var body: some View {
        if let details, !details.isEmpty {
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
}

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

private struct BudgetPaceBar: View {
    let pace: BudgetPace
    let color: Color

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let cornerRadius = size.height / 2
            context.fill(
                Path(roundedRect: rect, cornerRadius: cornerRadius),
                with: .color(.secondary.opacity(0.15))
            )

            let filledWidth = size.width * pace.usedFraction
            if filledWidth > 0 {
                let fillRect = CGRect(x: 0, y: 0, width: filledWidth, height: size.height)
                context.fill(
                    Path(roundedRect: fillRect, cornerRadius: min(cornerRadius, filledWidth / 2)),
                    with: .color(color)
                )
            }

            for dividerFraction in pace.configuration.dividerFractions {
                let dividerPosition = size.width * dividerFraction
                var divider = Path()
                divider.move(to: CGPoint(x: dividerPosition, y: 1))
                divider.addLine(to: CGPoint(x: dividerPosition, y: size.height - 1))
                context.stroke(divider, with: .color(.primary.opacity(0.24)), lineWidth: 1)
            }

            let markerX = size.width * pace.elapsedFraction
            var marker = Path()
            marker.move(to: CGPoint(x: markerX, y: 0))
            marker.addLine(to: CGPoint(x: markerX, y: size.height))
            context.stroke(marker, with: .color(.primary.opacity(0.85)), lineWidth: 1.5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

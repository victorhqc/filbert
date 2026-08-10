import Core
import Foundation
import SwiftUI

struct UsageLineRow: View {
    let line: UsageLine

    var body: some View {
        if shouldUseWeeklyPacing {
            WeeklyUsageLineRow(line: line)
        } else {
            StandardUsageLineRow(line: line)
        }
    }

    private var shouldUseWeeklyPacing: Bool {
        line.windowDuration == UsageWindowDuration.week
            && WeeklyBudgetPace(line: line, now: Date()) != nil
    }
}

private struct StandardUsageLineRow: View {
    let line: UsageLine

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

private struct WeeklyUsageLineRow: View {
    let line: UsageLine

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if let pace = WeeklyBudgetPace(line: line, now: context.date) {
                paceContent(pace)
            } else {
                StandardUsageLineRow(line: line)
            }
        }
    }

    private func paceContent(_ pace: WeeklyBudgetPace) -> some View {
        let color = ProviderVisualStyle.tierColor(pace.tier, scheme: colorScheme)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(line.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(usedPercentageText(pace.usedPercentage))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(color)
            }

            WeeklyPaceBar(pace: pace, color: color)

            HStack(spacing: 8) {
                Text(remainingTimeText(pace.remainingTime))
                Spacer(minLength: 4)
                Text(remainingAllowanceText(pace))
                    .multilineTextAlignment(.trailing)
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.secondary)

            UsageDetailsRows(details: line.details)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.label)
        .accessibilityValue(weeklyAccessibilityValue(pace))
    }

    private func usedPercentageText(_ percentage: Double) -> String {
        let formatted = percentage.formatted(.number.precision(.fractionLength(0)))
        return String.localizedStringWithFormat(String(localized: "%@%% used"), formatted)
    }

    private func remainingTimeText(_ remainingTime: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = remainingTime >= 24 * 60 * 60 ? [.day, .hour] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        let formatted = formatter.string(from: remainingTime) ?? ""
        return String.localizedStringWithFormat(String(localized: "%@ left"), formatted)
    }

    private func remainingAllowanceText(_ pace: WeeklyBudgetPace) -> String {
        if let availablePercentagePerDay = pace.availablePercentagePerDay {
            let formatted = availablePercentagePerDay.formatted(
                .number.precision(.fractionLength(1))
            )
            return String.localizedStringWithFormat(
                String(localized: "About %@%%/day available"),
                formatted
            )
        }

        let formatted = pace.remainingPercentage.formatted(.number.precision(.fractionLength(0)))
        return String.localizedStringWithFormat(
            String(localized: "%@%% available until reset"),
            formatted
        )
    }

    private func weeklyAccessibilityValue(_ pace: WeeklyBudgetPace) -> String {
        let paceStatus = switch pace.tier {
        case .good:
            String(localized: "On pace")
        case .warn, .critical:
            String(localized: "Over pace")
        }
        let value = String.localizedStringWithFormat(
            String(localized: "%1$@. %2$@"),
            usedPercentageText(pace.usedPercentage),
            remainingTimeText(pace.remainingTime)
        )
        let allowance = String.localizedStringWithFormat(
            String(localized: "%1$@. %2$@"),
            paceStatus,
            remainingAllowanceText(pace)
        )
        return String.localizedStringWithFormat(String(localized: "%1$@. %2$@"), value, allowance)
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

private struct WeeklyPaceBar: View {
    let pace: WeeklyBudgetPace
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

            for day in 1 ..< 7 {
                let dividerPosition = size.width * CGFloat(day) / 7
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

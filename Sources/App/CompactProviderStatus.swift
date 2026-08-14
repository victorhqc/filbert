import Core
import SwiftUI

struct CompactProviderStatus: View {
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

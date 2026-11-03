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
                    UsageRing(
                        fraction: QuotaStatusResolver.clampedFraction(percentage / 100),
                        color: ProviderVisualStyle.tierColor(tier, scheme: colorScheme)
                    )
                    Text(QuotaFormatting.percentage(percentage))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ProviderVisualStyle.tierColor(tier, scheme: colorScheme))
                }
                .accessibilityHidden(true)
            }
        case let .balance(_, formattedAmount):
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
        case let .credits(formattedAmount):
            Text(formattedAmount)
                .font(.caption.monospacedDigit())
                .accessibilityHidden(true)
        case .fallback:
            EmptyView()
        }
    }
}

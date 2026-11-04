import Core
import SwiftUI

struct ProviderTab: View {
    let info: ProviderInfo
    let state: ProviderState
    let errorMessage: String?
    let isSelected: Bool
    let accessibilityLabel: String
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    private static let ringDiameter: CGFloat = 28
    private static let ringColorOpacity = 0.7
    private static let valueLineHeight: CGFloat = 13

    var body: some View {
        Button(action: onSelect) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                tabContent(ProviderTabStatus.make(state: state, errorMessage: errorMessage, at: context.date))
            }
        }
        .buttonStyle(.plain)
        .help(info.displayName)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tabContent(_ status: ProviderTabStatus) -> some View {
        VStack(spacing: 3) {
            ringedBadge(status)
            valueLine(status)
                .frame(height: Self.valueLineHeight)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(minWidth: Self.ringDiameter + 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: ProviderVisualStyle.cardCornerRadius)
        )
        .contentShape(RoundedRectangle(cornerRadius: ProviderVisualStyle.cardCornerRadius))
    }

    private func ringedBadge(_ status: ProviderTabStatus) -> some View {
        ZStack {
            UsageRing(
                fraction: status.ringFraction,
                color: status.tier.map { ProviderVisualStyle.tierColor($0, scheme: colorScheme) },
                lineWidth: 2.5,
                diameter: Self.ringDiameter,
                colorOpacity: Self.ringColorOpacity
            )
            ProviderLogoBadge(glyph: info.glyph, showsContainer: false)
        }
        .overlay(alignment: .bottomTrailing) {
            if let tabLabel = info.tabLabel {
                cornerLabel(tabLabel)
            }
        }
    }

    private func cornerLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2.5)
            .padding(.vertical, 0.5)
            .background(Capsule().fill(.background))
            .overlay(Capsule().stroke(.secondary.opacity(0.4), lineWidth: 0.5))
            .fixedSize()
            .offset(x: 6, y: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func valueLine(_ status: ProviderTabStatus) -> some View {
        switch status.value {
        case let .text(text):
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(valueColor(status))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        case .progress:
            ProgressView()
                .controlSize(.mini)
        case let .warning(message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundColor(.yellow)
                .help(message)
        case .empty:
            Color.clear
                .frame(width: 1)
        }
    }

    private func valueColor(_ status: ProviderTabStatus) -> Color {
        guard status.colorsValue, let tier = status.tier else { return .primary }
        return ProviderVisualStyle.tierColor(tier, scheme: colorScheme)
    }
}

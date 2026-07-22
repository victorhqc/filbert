import AppKit
import Core
import SwiftUI

enum ProviderVisualStyle {
    static let badgeContentSize: CGFloat = 15
    static let badgeInset: CGFloat = 4
    static let badgeCornerRadius: CGFloat = 6
    static let cardCornerRadius: CGFloat = 10
    static let neutralContainerFill = Color.secondary.opacity(0.08)

    /// Light values retain the contrast-tuned palette from (ui 11); dark mode
    /// uses the semantic system colors so it follows the active appearance.
    static func tierColor(
        _ tier: QuotaStatusResolver.Tier,
        scheme: ColorScheme
    ) -> Color {
        switch (tier, scheme) {
        case (.good, .light): Color(red: 0.027, green: 0.502, blue: 0.141)
        case (.warn, .light): Color(red: 0.690, green: 0.333, blue: 0.051)
        case (.critical, .light): Color(red: 0.729, green: 0.169, blue: 0.161)
        case (.good, _): .green
        case (.warn, _): .orange
        case (.critical, _): .red
        }
    }

    static func balanceTierColor(_ total: Double, scheme: ColorScheme) -> Color {
        let status = QuotaStatusResolver.Status.balance(
            used: nil,
            total: total,
            formattedAmount: ""
        )
        guard let tier = QuotaStatusResolver.tier(for: status) else { return .secondary }
        return tierColor(tier, scheme: scheme)
    }
}

struct ProviderLogoBadge: View {
    let glyph: ProviderGlyph

    var body: some View {
        Group {
            switch glyph {
            case let .sfSymbol(name):
                Image(systemName: name)
            case let .asset(name, bundle):
                if let image = bundle.image(forResource: NSImage.Name(name)) {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "cpu")
                }
            }
        }
        .foregroundStyle(.primary)
        .frame(
            width: ProviderVisualStyle.badgeContentSize,
            height: ProviderVisualStyle.badgeContentSize
        )
        .padding(ProviderVisualStyle.badgeInset)
        .background(
            .secondary.opacity(0.14),
            in: RoundedRectangle(cornerRadius: ProviderVisualStyle.badgeCornerRadius)
        )
        .accessibilityHidden(true)
    }
}

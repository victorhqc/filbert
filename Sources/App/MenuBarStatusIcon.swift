import AppKit
import Core
import SwiftUI

@MainActor
struct MenuBarStatusIcon: View {
    let viewModel: QuotaViewModel
    let sleepPrevention: SleepPreventionController
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if let resolved = resolvedStatus {
            switch resolved.status {
            case let .window(percentage):
                statusRow(percentageText(percentage), resolved: resolved)
            case let .balance(_, _, formattedAmount):
                statusRow(formattedAmount, resolved: resolved)
            case .fallback:
                fallbackIcon
            }
        } else {
            fallbackIcon
        }
    }

    @ViewBuilder
    private var fallbackIcon: some View {
        if sleepPrevention.isAwakeIndicatorVisible, !viewModel.isVintageMacIconEnabled {
            let image = MenuBarStatusVisual.fallbackImage(
                foregroundColor: menuBarForegroundColor
            )
            Image(nsImage: image)
                .resizable()
                .renderingMode(.original)
                .frame(width: image.size.width, height: image.size.height)
                .accessibilityLabel(
                    [
                        String(localized: "Filbert"),
                        String(localized: "Mac sleep prevention active"),
                    ].joined(separator: ", ")
                )
        } else {
            Image(systemName: "brain.head.profile")
                .accessibilityLabel(String(localized: "Filbert"))
        }
    }

    private var resolvedStatus: MenuBarProviderPresentation.Resolved? {
        guard let providerId = viewModel.menuBarProviderId else { return nil }
        return MenuBarProviderPresentation.resolve(
            providerInfo: viewModel.providerInfo(for: providerId),
            providerState: viewModel.providerStates[providerId],
            isFastRefreshActive: viewModel.isFastAutomaticRefreshActive(for: providerId)
        )
    }

    private func percentageText(_ percentage: Double) -> String {
        let rounded = Int(percentage.rounded())
        return String(localized: "\(rounded)%")
    }

    private func statusRow(
        _ text: String,
        resolved: MenuBarProviderPresentation.Resolved
    ) -> some View {
        HStack(spacing: 3) {
            compositeImage(for: resolved)
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .accessibilityLabel(
            MenuBarProviderPresentation.accessibilityLabel(
                for: resolved,
                isSleepPreventionActive: sleepPrevention.isAwakeIndicatorVisible
                    && !viewModel.isVintageMacIconEnabled
            )
        )
    }

    private func compositeImage(
        for resolved: MenuBarProviderPresentation.Resolved
    ) -> some View {
        let image = MenuBarStatusVisual.compositeImage(
            statusImage: MenuBarStatusVisual.statusImage(
                for: resolved.status,
                isVintageMacEnabled: viewModel.isVintageMacIconEnabled
            ),
            glyph: resolved.glyph,
            isFastRefreshActive: resolved.isFastRefreshActive,
            isSleepPreventionActive: sleepPrevention.isAwakeIndicatorVisible
                && !viewModel.isVintageMacIconEnabled,
            foregroundColor: menuBarForegroundColor
        )
        return Image(nsImage: image)
            .resizable()
            .renderingMode(.original)
            .frame(width: image.size.width, height: image.size.height)
            .accessibilityHidden(true)
    }

    private var menuBarForegroundColor: NSColor {
        colorScheme == .dark ? .white : .black
    }
}

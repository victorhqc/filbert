import AppKit
import Core

enum MenuBarStatusVisual {
    enum StatusImage: Equatable {
        case ring(bucket: Double)
        case macFace(tier: QuotaStatusResolver.Tier)
    }

    private static let compositeSpacing: CGFloat = 2
    private static let awakeIndicatorSize: CGFloat = 6

    static func statusImage(
        for status: QuotaStatusResolver.Status,
        isVintageMacEnabled: Bool
    ) -> StatusImage? {
        switch status {
        case let .window(percentage):
            if isVintageMacEnabled, let tier = QuotaStatusResolver.tier(for: status) {
                return .macFace(tier: tier)
            }
            let clamped = QuotaStatusResolver.clampedFraction(percentage / 100)
            return .ring(bucket: (clamped * 10).rounded() / 10)
        case .balance:
            guard isVintageMacEnabled, let tier = QuotaStatusResolver.tier(for: status) else {
                return nil
            }
            return .macFace(tier: tier)
        case .fallback:
            return nil
        }
    }

    static func compositeSize(
        statusImage: StatusImage?,
        isFastRefreshActive: Bool,
        isSleepPreventionActive: Bool = false
    ) -> CGSize {
        let identity = MenuBarProviderGlyphResolver.menuBarImageSize(
            isFastRefreshActive: isFastRefreshActive
        )
        guard let statusImage else {
            guard isSleepPreventionActive else { return identity }
            return CGSize(
                width: identity.width + compositeSpacing + awakeIndicatorSize,
                height: max(identity.height, awakeIndicatorSize)
            )
        }
        let visual = MenuBarStatusVisualRenderer.size(for: statusImage)
        return CGSize(
            width: identity.width + compositeSpacing + visual.width,
            height: max(identity.height, visual.height)
        )
    }

    static func compositeImage(
        statusImage: StatusImage?,
        glyph: ProviderGlyph,
        isFastRefreshActive: Bool,
        isSleepPreventionActive: Bool = false,
        foregroundColor: NSColor = .black
    ) -> NSImage {
        let size = compositeSize(
            statusImage: statusImage,
            isFastRefreshActive: isFastRefreshActive,
            isSleepPreventionActive: isSleepPreventionActive
        )
        return MenuBarBitmapRenderer.image(size: size) {
            let identity = MenuBarProviderGlyphResolver.menuBarImage(
                for: glyph,
                isFastRefreshActive: isFastRefreshActive,
                foregroundColor: foregroundColor
            )
            drawIdentity(identity, in: size)
            drawStatusImage(
                statusImage,
                after: identity,
                in: size,
                isSleepPreventionActive: isSleepPreventionActive,
                foregroundColor: foregroundColor
            )
        }
    }

    static func fallbackImage(foregroundColor: NSColor = .black) -> NSImage {
        let fallbackSize = MenuBarProviderGlyphResolver.identityCanvasRect.size
        let size = CGSize(
            width: fallbackSize.width + compositeSpacing + awakeIndicatorSize,
            height: max(fallbackSize.height, awakeIndicatorSize)
        )
        return MenuBarBitmapRenderer.image(size: size) {
            let fallback = NSImage(
                systemSymbolName: "brain.head.profile",
                accessibilityDescription: nil
            ) ?? NSImage(size: .zero)
            MenuBarBitmapRenderer.draw(
                fallback,
                in: CGRect(origin: .zero, size: fallbackSize),
                color: foregroundColor
            )
            drawAwakeIndicator(after: fallbackSize.width, in: size, color: foregroundColor)
        }
    }

    private static func drawIdentity(_ image: NSImage, in size: CGSize) {
        image.draw(
            in: CGRect(
                x: 0,
                y: (size.height - image.size.height) / 2,
                width: image.size.width,
                height: image.size.height
            )
        )
    }

    private static func drawStatusImage(
        _ statusImage: StatusImage?,
        after identity: NSImage,
        in size: CGSize,
        isSleepPreventionActive: Bool,
        foregroundColor: NSColor
    ) {
        guard let statusImage else {
            if isSleepPreventionActive {
                drawAwakeIndicator(after: identity.size.width, in: size, color: foregroundColor)
            }
            return
        }

        let visual = MenuBarStatusVisualRenderer.render(
            statusImage: statusImage,
            foregroundColor: foregroundColor
        )
        let origin = identity.size.width + compositeSpacing
        visual.draw(
            in: CGRect(
                x: origin,
                y: (size.height - visual.size.height) / 2,
                width: visual.size.width,
                height: visual.size.height
            )
        )
        if isSleepPreventionActive, case .ring = statusImage {
            MenuBarBitmapRenderer.draw(
                awakeIndicatorImage(),
                in: CGRect(
                    x: origin + (visual.size.width - awakeIndicatorSize) / 2,
                    y: (size.height - awakeIndicatorSize) / 2,
                    width: awakeIndicatorSize,
                    height: awakeIndicatorSize
                ),
                color: foregroundColor
            )
        }
    }

    private static func drawAwakeIndicator(after identityWidth: CGFloat, in size: CGSize, color: NSColor) {
        MenuBarBitmapRenderer.draw(
            awakeIndicatorImage(),
            in: CGRect(
                x: identityWidth + compositeSpacing,
                y: (size.height - awakeIndicatorSize) / 2,
                width: awakeIndicatorSize,
                height: awakeIndicatorSize
            ),
            color: color
        )
    }

    private static func awakeIndicatorImage() -> NSImage {
        NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
            ?? NSImage(size: .zero)
    }
}

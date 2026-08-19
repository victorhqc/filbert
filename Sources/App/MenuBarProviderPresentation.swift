import AppKit
import Core

enum MenuBarProviderPresentation {
    struct Resolved {
        let providerName: String
        let glyph: ProviderGlyph
        let status: QuotaStatusResolver.Status
        let isFastRefreshActive: Bool
    }

    static func resolve(
        providerInfo: ProviderInfo?,
        providerState: ProviderState?,
        isFastRefreshActive: Bool
    ) -> Resolved? {
        guard let providerInfo,
              case let .loaded(quota) = providerState
        else {
            return nil
        }

        let status = QuotaStatusResolver.resolve(for: quota)
        guard status != .fallback else { return nil }

        return Resolved(
            providerName: providerInfo.displayName,
            glyph: providerInfo.glyph,
            status: status,
            isFastRefreshActive: isFastRefreshActive
        )
    }

    static func accessibilityLabel(for resolved: Resolved) -> String {
        let status: String
        switch resolved.status {
        case let .window(percentage):
            status = String(
                localized: "\(resolved.providerName): \(Int(percentage.rounded()))% used"
            )
        case let .balance(_, total, _):
            let amount = QuotaStatusResolver.amountText(
                for: UsageLine(label: "", total: total, unit: nil)
            ) ?? String(format: "%.2f", total)
            status = String(localized: "\(resolved.providerName): \(amount) remaining")
        case .fallback:
            return String(localized: "Filbert")
        }

        guard resolved.isFastRefreshActive else { return status }
        return [status, String(localized: "Fast refresh active")].joined(separator: ", ")
    }
}

enum MenuBarProviderGlyphResolver {
    static let glyphSide: CGFloat = 9
    static let fastIndicatorSide: CGFloat = 7

    static func menuBarImageSize(isFastRefreshActive: Bool) -> CGSize {
        CGSize(
            width: glyphSide,
            height: isFastRefreshActive ? fastIndicatorSide + glyphSide : glyphSide
        )
    }

    /// Drawn into one bitmap template `NSImage` — bolt above glyph while
    /// fast — because `MenuBarExtra`'s label layer silently drops
    /// symbol-backed images.
    static func menuBarImage(
        for glyph: ProviderGlyph,
        isFastRefreshActive: Bool
    ) -> NSImage {
        let size = menuBarImageSize(isFastRefreshActive: isFastRefreshActive)
        let renderedImage = NSImage(size: size)
        renderedImage.lockFocus()

        if isFastRefreshActive {
            drawAspectFit(
                fastIndicatorImage(),
                in: CGRect(
                    x: (size.width - fastIndicatorSide) / 2,
                    y: glyphSide,
                    width: fastIndicatorSide,
                    height: fastIndicatorSide
                )
            )
        }
        drawAspectFit(
            image(for: glyph),
            in: CGRect(x: 0, y: 0, width: glyphSide, height: glyphSide)
        )

        renderedImage.unlockFocus()
        renderedImage.isTemplate = true
        return renderedImage
    }

    static func fallbackSymbolName(for glyph: ProviderGlyph) -> String? {
        guard case let .asset(name, bundle) = glyph,
              bundle.image(forResource: NSImage.Name(name)) == nil
        else {
            return nil
        }
        return "cpu"
    }

    static func image(for glyph: ProviderGlyph) -> NSImage {
        switch glyph {
        case let .sfSymbol(name):
            systemImage(named: name)
        case let .asset(name, bundle):
            if let image = bundle.image(forResource: NSImage.Name(name)) {
                image
            } else {
                systemImage(named: fallbackSymbolName(for: glyph) ?? "cpu")
            }
        }
    }

    private static func systemImage(named name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
            ?? NSImage(size: .zero)
    }

    private static func fastIndicatorImage() -> NSImage {
        NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)
            ?? NSImage(size: .zero)
    }

    private static func drawAspectFit(_ source: NSImage, in rect: CGRect) {
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }
        let scale = min(
            rect.width / sourceSize.width,
            rect.height / sourceSize.height
        )
        let fittedWidth = sourceSize.width * scale
        let fittedHeight = sourceSize.height * scale
        source.draw(
            in: CGRect(
                x: rect.midX - fittedWidth / 2,
                y: rect.midY - fittedHeight / 2,
                width: fittedWidth,
                height: fittedHeight
            )
        )
    }
}

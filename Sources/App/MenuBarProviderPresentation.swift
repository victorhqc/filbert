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
    static let identityCanvasSide: CGFloat = 14
    static let glyphSide: CGFloat = 12
    static let fastIndicatorSide: CGFloat = 7
    static let fastIndicatorClearance: CGFloat = 1

    static let identityCanvasRect = CGRect(
        x: 0,
        y: 0,
        width: identityCanvasSide,
        height: identityCanvasSide
    )

    static let glyphRect = CGRect(
        x: (identityCanvasSide - glyphSide) / 2,
        y: (identityCanvasSide - glyphSide) / 2,
        width: glyphSide,
        height: glyphSide
    )

    static let fastIndicatorRect = CGRect(
        x: identityCanvasSide - fastIndicatorSide,
        y: identityCanvasSide - fastIndicatorSide,
        width: fastIndicatorSide,
        height: fastIndicatorSide
    )

    static let fastIndicatorClearanceRect = fastIndicatorRect
        .insetBy(dx: -fastIndicatorClearance, dy: -fastIndicatorClearance)
        .intersection(identityCanvasRect)

    static func menuBarImageSize(isFastRefreshActive _: Bool) -> CGSize {
        identityCanvasRect.size
    }

    static func menuBarImage(
        for glyph: ProviderGlyph,
        isFastRefreshActive: Bool
    ) -> NSImage {
        let size = menuBarImageSize(isFastRefreshActive: isFastRefreshActive)
        let renderedImage = NSImage(size: size)
        renderedImage.lockFocus()

        drawAspectFit(
            image(for: glyph),
            in: glyphRect
        )
        if isFastRefreshActive {
            clear(fastIndicatorClearanceRect)
            drawAspectFit(
                fastIndicatorImage(),
                in: fastIndicatorRect
            )
        }

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

    private static func clear(_ rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.clear)
        context.fill(rect)
        context.restoreGState()
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

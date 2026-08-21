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

enum MenuBarBitmapRenderer {
    private static let bitmapScale: CGFloat = 2

    static func image(size: CGSize, drawing: () -> Void) -> NSImage {
        guard size.width > 0, size.height > 0 else {
            return NSImage(size: size)
        }

        let pixelsWide = Int((size.width * bitmapScale).rounded(.up))
        let pixelsHigh = Int((size.height * bitmapScale).rounded(.up))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: representation) else {
            return NSImage(size: size)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.cgContext.scaleBy(x: bitmapScale, y: bitmapScale)
        drawing()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(representation)
        return image
    }

    static func draw(_ source: NSImage, in rect: CGRect, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let sourceImage = cgImage(for: source),
              let fittedRect = fittedRect(for: source, in: rect)
        else {
            return
        }

        context.saveGState()
        context.draw(sourceImage, in: fittedRect)
        context.setBlendMode(.sourceIn)
        context.setFillColor(color.cgColor)
        context.fill(fittedRect)
        context.restoreGState()
    }

    static func clear(using source: NSImage, in rect: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let sourceImage = cgImage(for: source),
              let fittedRect = fittedRect(for: source, in: rect)
        else {
            return
        }

        context.saveGState()
        context.setBlendMode(.destinationOut)
        context.draw(sourceImage, in: fittedRect)
        context.restoreGState()
    }

    private static func cgImage(for source: NSImage) -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: source.size)
        return source.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private static func fittedRect(for source: NSImage, in rect: CGRect) -> CGRect? {
        let sourceSize = source.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        let scale = min(
            rect.width / sourceSize.width,
            rect.height / sourceSize.height
        )
        let fittedWidth = sourceSize.width * scale
        let fittedHeight = sourceSize.height * scale
        return CGRect(
            x: rect.midX - fittedWidth / 2,
            y: rect.midY - fittedHeight / 2,
            width: fittedWidth,
            height: fittedHeight
        )
    }
}

enum MenuBarProviderGlyphResolver {
    static let identityCanvasSide: CGFloat = 14
    static let glyphSide: CGFloat = 12
    static let fastIndicatorSide: CGFloat = 9
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
        isFastRefreshActive: Bool,
        foregroundColor: NSColor = .black
    ) -> NSImage {
        let size = menuBarImageSize(isFastRefreshActive: isFastRefreshActive)
        return MenuBarBitmapRenderer.image(size: size) {
            MenuBarBitmapRenderer.draw(
                image(for: glyph),
                in: glyphRect,
                color: foregroundColor
            )
            if isFastRefreshActive {
                let fastIndicator = fastIndicatorImage()
                MenuBarBitmapRenderer.clear(
                    using: fastIndicator,
                    in: fastIndicatorClearanceRect
                )
                MenuBarBitmapRenderer.draw(
                    fastIndicator,
                    in: fastIndicatorRect,
                    color: foregroundColor
                )
            }
        }
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
}

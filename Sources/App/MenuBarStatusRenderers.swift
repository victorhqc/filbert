import AppKit

enum MenuBarStatusVisualRenderer {
    static func render(
        statusImage: MenuBarStatusVisual.StatusImage,
        foregroundColor: NSColor
    ) -> NSImage {
        let size = size(for: statusImage)
        return MenuBarBitmapRenderer.image(size: size) {
            let statusImageSize = statusImageSize(for: statusImage)
            MenuBarBitmapRenderer.draw(
                renderedStatusImage(for: statusImage),
                in: CGRect(origin: .zero, size: statusImageSize),
                color: foregroundColor
            )
        }
    }

    static func size(for statusImage: MenuBarStatusVisual.StatusImage) -> CGSize {
        statusImageSize(for: statusImage)
    }

    private static func renderedStatusImage(for statusImage: MenuBarStatusVisual.StatusImage) -> NSImage {
        switch statusImage {
        case let .ring(bucket):
            MenuBarRingRenderer.render(fraction: bucket)
        case let .macFace(tier):
            MenuBarMacFaceRenderer.render(tier: tier)
        }
    }

    private static func statusImageSize(for statusImage: MenuBarStatusVisual.StatusImage) -> CGSize {
        switch statusImage {
        case .ring:
            CGSize(width: 14, height: 14)
        case .macFace:
            CGSize(width: 16, height: 16)
        }
    }
}

private enum MenuBarRingRenderer {
    private static let pixels = 28

    private static let drawableRatio: CGFloat = 0.85

    private static let lineWidth: CGFloat = 4

    static func render(fraction: Double) -> NSImage {
        let points = CGFloat(pixels) / 2
        guard let context = makeContext() else {
            return NSImage(size: NSSize(width: points, height: points))
        }
        drawRing(into: context, fraction: fraction)
        return makeImage(from: context, points: points)
    }

    private static func makeContext() -> CGContext? {
        CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        )
    }

    private static func drawRing(into context: CGContext, fraction: Double) {
        let clamped = QuotaStatusResolver.clampedFraction(fraction)
        let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        let center = CGPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels) / 2)
        let radius = (CGFloat(pixels) - lineWidth) / 2
        let spanRatio = clamped >= 1 ? 1.0 : drawableRatio

        context.clear(bounds)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -.pi / 2)
        context.translateBy(x: -center.x, y: -center.y)

        context.addArc(
            center: center,
            radius: radius,
            startAngle: 0,
            endAngle: 2 * .pi * spanRatio,
            clockwise: false
        )
        context.setStrokeColor(CGColor(gray: 0, alpha: 0.2))
        context.strokePath()

        let fillEnd = 2 * .pi * spanRatio * clamped
        guard fillEnd > 0 else { return }
        context.addArc(
            center: center,
            radius: radius,
            startAngle: 0,
            endAngle: fillEnd,
            clockwise: false
        )
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.strokePath()
    }

    private static func makeImage(from context: CGContext, points: CGFloat) -> NSImage {
        guard let cgImage = context.makeImage() else {
            return NSImage(size: NSSize(width: points, height: points))
        }
        let nsImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: points, height: points)
        )
        nsImage.isTemplate = true
        return nsImage
    }
}

private enum MenuBarMacFaceRenderer {
    private static let pixels = 32
    private static let ink = CGColor(gray: 0, alpha: 1)

    static func render(tier: QuotaStatusResolver.Tier) -> NSImage {
        let points = CGFloat(pixels) / 2
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else {
            return NSImage(size: NSSize(width: points, height: points))
        }

        context.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        context.setFillColor(ink)
        drawMacintosh(into: context)
        drawMouth(for: tier, into: context)

        guard let cgImage = context.makeImage() else {
            return NSImage(size: NSSize(width: points, height: points))
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: points, height: points))
        image.isTemplate = true
        return image
    }

    private static func drawMacintosh(into context: CGContext) {
        fill([CGRect(x: 6, y: 30, width: 20, height: 1),
              CGRect(x: 5, y: 29, width: 22, height: 1),
              CGRect(x: 4, y: 28, width: 24, height: 1),
              CGRect(x: 4, y: 6, width: 24, height: 22),
              CGRect(x: 5, y: 4, width: 22, height: 2),
              CGRect(x: 5, y: 1, width: 22, height: 3)], into: context)
        context.clear(CGRect(x: 7, y: 11, width: 18, height: 17))
        context.clear(CGRect(x: 17, y: 7, width: 7, height: 1))
        fill([CGRect(x: 10, y: 22, width: 3, height: 4),
              CGRect(x: 20, y: 22, width: 3, height: 4),
              CGRect(x: 15, y: 17, width: 2, height: 6)], into: context)
    }

    private static func drawMouth(for tier: QuotaStatusResolver.Tier, into context: CGContext) {
        switch tier {
        case .good:
            fill([CGRect(x: 11, y: 16, width: 2, height: 2),
                  CGRect(x: 13, y: 14, width: 6, height: 2),
                  CGRect(x: 19, y: 16, width: 2, height: 2)], into: context)
        case .warn:
            fill([CGRect(x: 11, y: 16, width: 10, height: 2)], into: context)
        case .critical:
            fill([CGRect(x: 11, y: 14, width: 2, height: 2),
                  CGRect(x: 13, y: 16, width: 6, height: 2),
                  CGRect(x: 19, y: 14, width: 2, height: 2)], into: context)
        }
    }

    private static func fill(_ rectangles: [CGRect], into context: CGContext) {
        rectangles.forEach(context.fill)
    }
}

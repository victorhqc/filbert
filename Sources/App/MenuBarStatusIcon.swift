import Core
import SwiftUI

// MARK: - Menu-bar live status icon

/// The ring is rendered into a bitmap `NSImage` instead of a SwiftUI `Shape`
/// because `MenuBarExtra`'s label layer on macOS 14 silently drops arbitrary
/// `Shape` / `Canvas` content — only `Text` and `Image` reliably render.
@MainActor
struct MenuBarStatusIcon: View {
    let viewModel: QuotaViewModel

    var body: some View {
        content
            .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if let resolved = resolvedStatus {
            switch resolved.status {
            case let .window(percentage):
                HStack(spacing: 3) {
                    statusImage(for: resolved.status)
                    statusText(
                        percentageText(percentage),
                        glyph: resolved.glyph,
                        isFastRefreshActive: resolved.isFastRefreshActive
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel(
                    MenuBarProviderPresentation.accessibilityLabel(for: resolved)
                )
            case let .balance(_, _, formattedAmount):
                HStack(spacing: 3) {
                    statusImage(for: resolved.status)
                    statusText(
                        formattedAmount,
                        glyph: resolved.glyph,
                        isFastRefreshActive: resolved.isFastRefreshActive
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.primary)
                }
                .accessibilityLabel(
                    MenuBarProviderPresentation.accessibilityLabel(for: resolved)
                )
            case .fallback:
                fallbackIcon
            }
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: "brain.head.profile")
            .accessibilityLabel(String(localized: "Filbert"))
    }

    // MARK: - Resolution

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

    @ViewBuilder
    private func statusImage(for status: QuotaStatusResolver.Status) -> some View {
        if let statusImage = MenuBarStatusVisual.statusImage(
            for: status,
            isVintageMacEnabled: viewModel.isVintageMacIconEnabled
        ) {
            MenuBarStatusVisualImage(statusImage: statusImage)
        }
    }

    private func statusText(
        _ text: String,
        glyph: ProviderGlyph,
        isFastRefreshActive: Bool
    ) -> Text {
        let providerGlyph = Text(
            Image(nsImage: MenuBarProviderGlyphResolver.menuBarImage(for: glyph))
        )
        let status = Text(text)
        let statusWithRefreshIndicator = if isFastRefreshActive {
            status + Text(" ") + Text(Image(systemName: "bolt.fill"))
        } else {
            status
        }
        return statusWithRefreshIndicator + Text(" ") + providerGlyph
    }
}

enum MenuBarStatusVisual {
    enum StatusImage: Equatable {
        case ring(bucket: Double)
        case macFace(tier: QuotaStatusResolver.Tier)
    }

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
}

private struct MenuBarStatusVisualImage: View {
    let statusImage: MenuBarStatusVisual.StatusImage

    var body: some View {
        Image(nsImage: MenuBarStatusVisualRenderer.render(statusImage: statusImage))
            .resizable()
            .renderingMode(.template)
            .frame(
                width: MenuBarStatusVisualRenderer.size(for: statusImage).width,
                height: MenuBarStatusVisualRenderer.size(for: statusImage).height
            )
            .accessibilityHidden(true)
    }
}

private enum MenuBarStatusVisualRenderer {
    static func render(statusImage: MenuBarStatusVisual.StatusImage) -> NSImage {
        let size = size(for: statusImage)
        let image = NSImage(size: size)
        image.lockFocus()

        let statusImageSize = statusImageSize(for: statusImage)
        renderedStatusImage(for: statusImage).draw(
            in: CGRect(origin: .zero, size: statusImageSize)
        )

        image.unlockFocus()
        image.isTemplate = true
        return image
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

/// Drawn in solid black so `MenuBarExtra` can template-tint it.
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

    /// `CGContext`'s default arc origin is 3 o'clock (0° = positive X), so the
    /// context is rotated -90° to make the arc start at 12 o'clock.
    ///
    /// At 100% the arc spans the full `2π` so a complete budget reads as a
    /// complete circle rather than a 99% ring; buckets 0–90% keep the open-arc
    /// gap.
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

        // Track: the full drawable arc at low opacity.
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

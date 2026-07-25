import Core
import SwiftUI

// MARK: - Menu-bar live status icon

/// The ring is rendered into a bitmap `NSImage` instead of a SwiftUI `Shape`
/// because `MenuBarExtra`'s label layer on macOS 14 silently drops arbitrary
/// `Shape` / `Canvas` content — only `Text` and `Image` reliably render.
@MainActor
struct MenuBarStatusIcon: View {
    let viewModel: QuotaViewModel
    @State private var isVintageMacEnabled = VintageMacIcon.isEnabled

    var body: some View {
        content
            .accessibilityElement(children: .combine)
            .onReceive(NotificationCenter.default.publisher(for: VintageMacIcon.didChangeNotification)) { _ in
                isVintageMacEnabled = VintageMacIcon.isEnabled
            }
    }

    @ViewBuilder
    private var content: some View {
        if let resolved = resolvedStatus {
            switch resolved.status {
            case let .window(percentage):
                HStack(spacing: 3) {
                    if isVintageMacEnabled, let tier = QuotaStatusResolver.tier(for: resolved.status) {
                        MenuBarMacFaceImage(tier: tier)
                    } else {
                        MenuBarRingImage(bucket: bucket(from: percentage / 100))
                    }
                    Text(percentageText(percentage))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .accessibilityLabel(
                    accessibilityPercentage(
                        providerName: resolved.providerName,
                        percentage: percentage
                    )
                )
            case let .balance(_, total, formattedAmount):
                if isVintageMacEnabled, let tier = QuotaStatusResolver.tier(for: resolved.status) {
                    HStack(spacing: 3) {
                        MenuBarMacFaceImage(tier: tier)
                        Text(formattedAmount)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel(
                        accessibilityBalance(
                            providerName: resolved.providerName,
                            total: total
                        )
                    )
                } else {
                    Text(formattedAmount)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.primary)
                        .accessibilityLabel(
                            accessibilityBalance(
                                providerName: resolved.providerName,
                                total: total
                            )
                        )
                }
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

    private var resolvedStatus: Resolved? {
        guard let id = viewModel.configuredProviderIds.first,
              case let .loaded(quota) = viewModel.providerStates[id]
        else {
            return nil
        }
        let status = QuotaStatusResolver.resolve(for: quota)
        guard status != .fallback else { return nil }
        return Resolved(providerName: quota.providerName, status: status)
    }

    private func bucket(from fraction: Double) -> Double {
        let clamped = QuotaStatusResolver.clampedFraction(fraction)
        return (clamped * 10).rounded() / 10
    }

    private func percentageText(_ percentage: Double) -> String {
        let rounded = Int(percentage.rounded())
        return String(localized: "\(rounded)%")
    }

    private func accessibilityPercentage(providerName: String, percentage: Double) -> String {
        let pct = Int(percentage.rounded())
        return String(localized: "\(providerName): \(pct)% used")
    }

    private func accessibilityBalance(providerName: String, total: Double) -> String {
        let amount = QuotaStatusResolver.amountText(
            for: UsageLine(label: "", total: total, unit: nil)
        ) ?? String(format: "%.2f", total)
        return String(localized: "\(providerName): \(amount) remaining")
    }

    private struct Resolved {
        let providerName: String
        let status: QuotaStatusResolver.Status
    }
}

// MARK: - Ring image (bitmap-backed)

/// The image is drawn in solid black because `MenuBarExtra` applies its own
/// template tint, so the menu-bar ring respects the OS chrome.
private struct MenuBarRingImage: View {
    let bucket: Double

    var body: some View {
        MenuBarRingImageCache.image(for: bucket)
            .resizable()
            .renderingMode(.template)
            .frame(width: 14, height: 14)
    }
}

private enum MenuBarRingImageCache {
    /// `nonisolated(unsafe)`: SwiftUI renders on the main actor, so the lazy
    /// populate is single-threaded in practice.
    private nonisolated(unsafe) static var cache: [Int: Image] = [:]

    static func image(for bucket: Double) -> Image {
        let key = bucketKey(bucket)
        if let cached = cache[key] {
            return cached
        }
        let rendered = MenuBarRingRenderer.render(fraction: Double(key) / 10)
        let image = Image(nsImage: rendered)
        cache[key] = image
        return image
    }

    private static func bucketKey(_ bucket: Double) -> Int {
        let clamped = QuotaStatusResolver.clampedFraction(bucket)
        return Int((clamped * 10).rounded())
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

private struct MenuBarMacFaceImage: View {
    let tier: QuotaStatusResolver.Tier

    var body: some View {
        MenuBarMacFaceCache.image(for: tier)
            .resizable()
            .renderingMode(.template)
            .frame(width: 16, height: 16)
    }
}

private enum MenuBarMacFaceCache {
    /// `nonisolated(unsafe)`: SwiftUI renders on the main actor, so the lazy
    /// populate is single-threaded in practice.
    private nonisolated(unsafe) static var cache: [QuotaStatusResolver.Tier: Image] = [:]

    static func image(for tier: QuotaStatusResolver.Tier) -> Image {
        if let cached = cache[tier] {
            return cached
        }
        let image = Image(nsImage: MenuBarMacFaceRenderer.render(tier: tier))
        cache[tier] = image
        return image
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

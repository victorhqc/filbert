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

    static func menuBarImage(for glyph: ProviderGlyph) -> NSImage {
        let sourceImage = image(for: glyph)
        let image = sourceImage.copy() as? NSImage ?? sourceImage
        image.size = NSSize(width: 12, height: 12)
        image.isTemplate = true
        return image
    }

    private static func systemImage(named name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
            ?? NSImage(size: .zero)
    }
}

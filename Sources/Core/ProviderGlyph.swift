import Foundation

/// Providers keep their glyph assets in their own resource bundles. Core only
/// transports the descriptor, so adding a provider does not require an App
/// layer switch over provider IDs.
public enum ProviderGlyph: @unchecked Sendable {
    case sfSymbol(String)
    case asset(name: String, bundle: Bundle)
}

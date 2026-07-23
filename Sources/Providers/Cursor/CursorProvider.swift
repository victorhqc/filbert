import Core
import Foundation

/// Provider-owned metadata and resources for Cursor (providers 07).
public struct CursorProvider {
    public static let providerId = "cursor"
    public static let providerName = "Cursor"
    public static let providerGlyph = ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)
    public static let providerDescription = String(
        localized: "Monitor subscription and on-demand spend"
    )
    public static let setupHelp = ProviderSetupHelp(
        linkLabel: String(localized: "Sign in to Cursor"),
        url: URL(string: "https://docs.cursor.com/en/cli/reference/authentication")!
    )

    public init() {}
}

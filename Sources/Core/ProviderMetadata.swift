import Foundation

/// Documentation for a provider's external setup prerequisite.
public struct ProviderSetupHelp: Sendable, Equatable {
    public let linkLabel: String
    public let url: URL

    public init(linkLabel: String, url: URL) {
        self.linkLabel = linkLabel
        self.url = url
    }
}

/// Metadata about a registered provider, surfaced by the registry (ui 02 Plan 1).
public struct ProviderInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let glyph: ProviderGlyph
    public let description: String
    /// Optional provider-owned notice shown below the Settings controls.
    public let disclaimer: String?
    /// Production host root the provider hits when no override is set (core 02).
    /// Surfaced so the Settings UI can show what the user would be overriding
    /// (ui 03 Plan 3).
    public let defaultBaseURL: URL
    /// Payload-free discriminator so the App layer can dispatch row variants
    /// without inspecting a provider ID string (ui 05 AC1).
    public let authShape: ProviderAuth.Shape
    /// Optional documentation for providers with an external setup prerequisite.
    public let setupHelp: ProviderSetupHelp?

    public init(
        id: String,
        displayName: String,
        glyph: ProviderGlyph = .sfSymbol("cpu"),
        description: String,
        disclaimer: String? = nil,
        defaultBaseURL: URL,
        authShape: ProviderAuth.Shape,
        setupHelp: ProviderSetupHelp? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.glyph = glyph
        self.description = description
        self.disclaimer = disclaimer
        self.defaultBaseURL = defaultBaseURL
        self.authShape = authShape
        self.setupHelp = setupHelp
    }
}

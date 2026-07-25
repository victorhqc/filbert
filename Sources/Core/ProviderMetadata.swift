import Foundation

public struct ProviderSetupHelp: Sendable, Equatable {
    public let linkLabel: String
    public let url: URL

    public init(linkLabel: String, url: URL) {
        self.linkLabel = linkLabel
        self.url = url
    }
}

public struct ProviderInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let glyph: ProviderGlyph
    public let description: String
    public let disclaimer: String?
    public let defaultBaseURL: URL
    /// Payload-free discriminator so the App layer can dispatch row variants
    /// without inspecting a provider ID string.
    public let authShape: ProviderAuth.Shape
    public let setupHelp: ProviderSetupHelp?
    public let credentialImportActionTitle: String?

    public init(
        id: String,
        displayName: String,
        glyph: ProviderGlyph = .sfSymbol("cpu"),
        description: String,
        disclaimer: String? = nil,
        defaultBaseURL: URL,
        authShape: ProviderAuth.Shape,
        setupHelp: ProviderSetupHelp? = nil,
        credentialImportActionTitle: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.glyph = glyph
        self.description = description
        self.disclaimer = disclaimer
        self.defaultBaseURL = defaultBaseURL
        self.authShape = authShape
        self.setupHelp = setupHelp
        self.credentialImportActionTitle = credentialImportActionTitle
    }
}

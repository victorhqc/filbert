import Foundation

public struct ProviderSetupHelp: Sendable, Equatable {
    public let linkLabel: String
    public let url: URL

    public init(linkLabel: String, url: URL) {
        self.linkLabel = linkLabel
        self.url = url
    }
}

public struct ProviderAutomaticRefreshDisclosure: Sendable, Equatable {
    public let command: String
    public let quotaName: String

    public init(command: String, quotaName: String) {
        self.command = command
        self.quotaName = quotaName
    }
}

public struct ProviderAccountLink: Sendable, Equatable {
    public enum Destination: Sendable {
        case dashboard
        case account
    }

    public let url: URL
    public let destination: Destination

    public init(url: URL, destination: Destination = .dashboard) {
        self.url = url
        self.destination = destination
    }
}

public struct ProviderInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let glyph: ProviderGlyph
    public let description: String
    public let disclaimer: String?
    public let automaticRefreshDisclosure: ProviderAutomaticRefreshDisclosure?
    public let refreshCharacteristics: ProviderRefreshCharacteristics
    public let defaultBaseURL: URL
    /// Payload-free discriminator so the App layer can dispatch row variants
    /// without inspecting a provider ID string.
    public let authShape: ProviderAuth.Shape
    public let accountLink: ProviderAccountLink?
    public let setupHelp: ProviderSetupHelp?
    public let credentialImportActionTitle: String?

    public init(
        id: String,
        displayName: String,
        glyph: ProviderGlyph = .sfSymbol("cpu"),
        description: String,
        disclaimer: String? = nil,
        automaticRefreshDisclosure: ProviderAutomaticRefreshDisclosure? = nil,
        refreshCharacteristics: ProviderRefreshCharacteristics = ProviderRefreshCharacteristics(),
        defaultBaseURL: URL,
        authShape: ProviderAuth.Shape,
        setupHelp: ProviderSetupHelp? = nil,
        accountLink: ProviderAccountLink? = nil,
        credentialImportActionTitle: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.glyph = glyph
        self.description = description
        self.disclaimer = disclaimer
        self.automaticRefreshDisclosure = automaticRefreshDisclosure
        self.refreshCharacteristics = refreshCharacteristics
        self.defaultBaseURL = defaultBaseURL
        self.authShape = authShape
        self.accountLink = accountLink
        self.setupHelp = setupHelp
        self.credentialImportActionTitle = credentialImportActionTitle
    }
}

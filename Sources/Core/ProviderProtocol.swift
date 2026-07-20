import Foundation

/// Shared quota model that represents any provider plan type (core 01).
///
/// A single provider can return a mix of line types: some with percentage
/// + resetDate (windowed quota), others with used + unit (continuous
/// consumption), and some with both (capped API plans).
public struct ProviderQuota: Sendable {
    public let providerId: String
    public let providerName: String
    public let headline: String
    public let lines: [UsageLine]
    public let lastUpdated: Date
    public let error: String?

    public init(
        providerId: String,
        providerName: String,
        headline: String,
        lines: [UsageLine],
        lastUpdated: Date,
        error: String? = nil
    ) {
        self.providerId = providerId
        self.providerName = providerName
        self.headline = headline
        self.lines = lines
        self.lastUpdated = lastUpdated
        self.error = error
    }
}

/// One row in the quota display. Label is the only required field (core 01).
///
/// Lines are flexible: some carry percentage + resetDate (windowed quota),
/// others carry used + unit (continuous consumption), and some carry both
/// (capped API plans with a percentage-remaining ceiling).
public struct UsageLine: Sendable {
    public let label: String
    public let used: Double?
    public let total: Double?
    public let percentage: Double?
    public let unit: String?
    public let resetDate: Date?
    public let details: [UsageDetail]?

    public init(
        label: String,
        used: Double? = nil,
        total: Double? = nil,
        percentage: Double? = nil,
        unit: String? = nil,
        resetDate: Date? = nil,
        details: [UsageDetail]? = nil
    ) {
        self.label = label
        self.used = used
        self.total = total
        self.percentage = percentage
        self.unit = unit
        self.resetDate = resetDate
        self.details = details
    }
}

/// A single key-value detail line, e.g. "RPM" : "42 / 500".
public struct UsageDetail: Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

// MARK: - ProviderAuth (core 03)

/// The authentication shape a provider needs to fetch its quota (core 03 AC1).
///
/// Future auth shapes (e.g. OAuth tokens) get their own case under a separate
/// spec — never bolted on as a Stringly-typed field.
public enum ProviderAuth: Sendable {
    /// A plaintext API key stored in the macOS Keychain.
    case apiKey(String)
    /// No API key is needed — the provider derives its auth from the local
    /// environment (installed binary, helper process, cache file, etc.).
    case apiKeyFree

    /// Payload-free discriminator so the registry can route without ever
    /// materializing a key it should not see (core 03 AC7).
    public enum Shape: Sendable {
        case apiKey
        case apiKeyFree
    }
}

// MARK: - AIProvider (core 01, updated core 03)

/// Protocol every AI provider module must conform to (core 01).
///
/// Each provider is responsible for formatting its own headline string —
/// the Core layer never interprets it.
///
/// The effective base URL is resolved by Core (default vs. per-provider
/// override) and passed into `fetchQuota` so providers never read the
/// override themselves (core 02).
public protocol AIProvider: Sendable {
    static var providerId: String { get }
    static var providerName: String { get }
    /// Short, localized description shown in the Settings provider list (ui 02).
    static var providerDescription: String { get }
    /// Production host root for this provider, e.g.
    /// `URL(string: "https://api.z.ai")!` (core 02 AC1). Path segments stay
    /// inside `fetchQuota`.
    static var baseURL: URL { get }
    /// Non-payload discriminator the registry branches on so it never
    /// materializes a key it should not see (core 03 AC4/AC7).
    static var authShape: ProviderAuth.Shape { get }

    // MARK: - Quota fetch

    /// Fetches the provider's current quota, hitting `<baseURL>` resolved by
    /// the registry (core 02 AC2, core 03 AC2).
    ///
    /// - Parameter auth: The provider's authentication shape. Providers that
    ///   expect `.apiKey` should pattern-match `.apiKey(let key)`; providers
    ///   that are `.apiKeyFree` should never see `.apiKey` and vice versa.
    /// - Parameter baseURL: The effective host root, either the provider's
    ///   default or a user-saved proxy override.
    func fetchQuota(auth: ProviderAuth, baseURL: URL) async throws -> ProviderQuota

    // MARK: - Configuration (core 03 AC5/AC6)

    /// Whether this provider is ready to fetch. The default returns `true`,
    /// which is only correct for `.apiKey` providers — the registry routes
    /// `.apiKey` providers through the Keychain path and never calls this.
    /// `.apiKeyFree` providers MUST override to return their real state
    /// (binary present, helper installed, etc.).
    func isConfigured() -> Bool

    /// `.apiKeyFree` providers return their current setup state, e.g. why the
    /// provider is not ready. `.apiKey` providers never need this — the
    /// registry never calls it for them (core 03 AC6).
    func currentSetupState() async -> ProviderState?
}

// MARK: - AIProvider defaults (core 03 AC3/AC5/AC6)

public extension AIProvider {
    /// Defaults to `.apiKey` so existing providers need zero changes beyond
    /// the `fetchQuota` signature (core 03 Plan 2/3).
    static var authShape: ProviderAuth.Shape { .apiKey }

    /// Defaults to `true` — only correct for `.apiKey` providers. The
    /// registry routes `.apiKey` providers through the Keychain path and
    /// never calls this (core 03 AC5).
    func isConfigured() -> Bool { true }

    /// Defaults to `nil` — `.apiKey` providers are never asked for setup
    /// state (core 03 AC6).
    func currentSetupState() async -> ProviderState? { nil }
}

/// Metadata about a registered provider, surfaced by the registry (ui 02 Plan 1).
public struct ProviderInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String
    /// Production host root the provider hits when no override is set (core 02).
    /// Surfaced so the Settings UI can show what the user would be overriding
    /// (ui 03 Plan 3).
    public let defaultBaseURL: URL

    public init(
        id: String,
        displayName: String,
        description: String,
        defaultBaseURL: URL
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.defaultBaseURL = defaultBaseURL
    }
}

/// Per-provider state the view model tracks (ui 02 Plan 2, core 03 AC6).
public enum ProviderState: Sendable {
    case unconfigured
    /// `.apiKeyFree` providers report why they aren't ready via a
    /// human-readable reason (core 03 AC6).
    case setup(String)
    case loading
    case loaded(ProviderQuota)
    case error(String)
}

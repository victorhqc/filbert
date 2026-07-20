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
    /// Provider-set flag indicating the data is beyond its freshness window.
    /// Defaults to `false`; the provider is solely responsible for setting it
    /// (providers 02 AC5b).
    public let isStale: Bool

    public init(
        providerId: String,
        providerName: String,
        headline: String,
        lines: [UsageLine],
        lastUpdated: Date,
        error: String? = nil,
        isStale: Bool = false
    ) {
        self.providerId = providerId
        self.providerName = providerName
        self.headline = headline
        self.lines = lines
        self.lastUpdated = lastUpdated
        self.error = error
        self.isStale = isStale
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

    // MARK: - Helper management (ui 05 AC4/AC5)

    /// Installs the provider's helper (binary, config file, etc.). Only
    /// `.apiKeyFree` providers that require a local helper override this;
    /// the default throws `ProviderSetupError.notSupported` (ui 05 Plan 2).
    func installHelper() async throws

    /// Removes the provider's helper and restores any configuration the
    /// install touched. Only `.apiKeyFree` providers override this (ui 05 AC5).
    func removeHelper() async throws

    /// Whether the helper can currently be installed (binary present, etc.).
    /// Returns `false` for `.apiKey` providers and for `.apiKeyFree` providers
    /// whose binary is missing (ui 05 AC3/AC4).
    func canInstallHelper() -> Bool
}

// MARK: - AIProvider defaults (core 03 AC3/AC5/AC6)

public extension AIProvider {
    /// Defaults to `.apiKey` so existing providers need zero changes beyond
    /// the `fetchQuota` signature (core 03 Plan 2/3).
    static var authShape: ProviderAuth.Shape {
        .apiKey
    }

    /// Defaults to `true` — only correct for `.apiKey` providers. The
    /// registry routes `.apiKey` providers through the Keychain path and
    /// never calls this (core 03 AC5).
    func isConfigured() -> Bool {
        true
    }

    /// Defaults to `nil` — `.apiKey` providers are never asked for setup
    /// state (core 03 AC6).
    func currentSetupState() async -> ProviderState? {
        nil
    }

    /// Default throws — `.apiKey` providers don't support helper installation.
    func installHelper() async throws {
        throw ProviderSetupError.notSupported
    }

    /// Default throws — `.apiKey` providers don't support helper removal.
    func removeHelper() async throws {
        throw ProviderSetupError.notSupported
    }

    /// Default returns `false` — only `.apiKeyFree` providers with an
    /// installable helper override this.
    func canInstallHelper() -> Bool {
        false
    }
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
    /// Payload-free discriminator so the App layer can dispatch row variants
    /// without inspecting a provider ID string (ui 05 AC1).
    public let authShape: ProviderAuth.Shape

    public init(
        id: String,
        displayName: String,
        description: String,
        defaultBaseURL: URL,
        authShape: ProviderAuth.Shape
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.defaultBaseURL = defaultBaseURL
        self.authShape = authShape
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

// MARK: - ProviderSetupError (ui 05 Plan 2)

/// Thrown by `AIProvider.installHelper()` / `removeHelper()` default
/// implementations when called on a provider that does not support helper
/// management (e.g. `.apiKey` providers, or `.apiKeyFree` providers whose
/// setup mechanism does not involve a local helper).
public enum ProviderSetupError: Error, Equatable, Sendable {
    case notSupported
}

extension ProviderSetupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notSupported:
            String(localized: "This provider does not support helper installation.")
        }
    }
}

// MARK: - ProactiveRefreshable (providers 03)

/// Opt-in capability for providers that can refresh their data on demand
/// before the next `fetchQuota` call (providers 03 AC3).
///
/// Conformance is optional: providers that derive their data purely from
/// the network on every fetch (e.g. `.apiKey` providers like ZAI) never
/// conform, and the registry reports `ProviderSetupError.notSupported` for
/// them. Providers whose data comes from a side channel that an external
/// action can refresh (e.g. Claude Code's statusline cache) conform and
/// implement `proactiveRefresh()` to trigger that action.
public protocol ProactiveRefreshable: AIProvider {
    /// Trigger an out-of-band refresh of the provider's data source.
    ///
    /// Implementations should block until the refresh is observably complete
    /// (e.g. the cache file has been rewritten) or a bounded timeout elapses,
    /// so the caller's subsequent `fetchQuota` reads fresh data. Failures
    /// should throw; the view model catches them and proceeds to
    /// `fetchQuota` regardless, surfacing whatever cached data is available
    /// (providers 03 AC3).
    func proactiveRefresh() async throws
}

import Foundation

public struct ProviderQuota: Sendable {
    public let providerId: String
    public let providerName: String
    public let headline: String
    public let lines: [UsageLine]
    public let lastUpdated: Date
    public let error: String?
    public let isStale: Bool
    public let activityObservation: ProviderActivityObservation?
    /// Optional peak-hours pricing config. Providers that have time-based
    /// multipliers (e.g. z.ai's GLM Coding Plan) populate this so the view
    /// can render a peak/off-peak block without any provider-specific code.
    public let peakHoursConfig: PeakHoursConfig?

    public init(
        providerId: String,
        providerName: String,
        headline: String,
        lines: [UsageLine],
        lastUpdated: Date,
        error: String? = nil,
        isStale: Bool = false,
        activityObservation: ProviderActivityObservation? = nil,
        peakHoursConfig: PeakHoursConfig? = nil
    ) {
        self.providerId = providerId
        self.providerName = providerName
        self.headline = headline
        self.lines = lines
        self.lastUpdated = lastUpdated
        self.error = error
        self.isStale = isStale
        self.activityObservation = activityObservation
        self.peakHoursConfig = peakHoursConfig
    }
}

public struct ProviderActivityObservation: Equatable, Sendable {
    public let metrics: [ProviderActivityMetric]
    public let availability: ProviderAvailability?

    public init(
        metrics: [ProviderActivityMetric] = [],
        availability: ProviderAvailability? = nil
    ) {
        self.metrics = metrics
        self.availability = availability
    }
}

public struct ProviderActivityMetric: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case usage
        case credits
    }

    public enum Value: Equatable, Sendable {
        case number(Decimal)
        case discrete(String)
    }

    public let id: String
    public let kind: Kind
    public let value: Value

    public init(id: String, kind: Kind, value: Value) {
        self.id = id
        self.kind = kind
        self.value = value
    }
}

public enum ProviderAvailability: Equatable, Sendable {
    case available
    case unavailable
    case unknown
}

// MARK: - Peak-hours config

/// Provider-agnostic: adding a new provider with peak hours requires no
/// changes to the view layer.
public struct PeakHoursConfig: Sendable {
    public let timeZone: TimeZone?

    /// Peak window is `[peakStartHour, peakEndHour)` in `timeZone`.
    public let peakStartHour: Int
    public let peakEndHour: Int

    public let peakMultiplier: Int

    public let offPeakMultiplier: Int

    public let promoMultiplier: Int?

    public let promoEndDate: Date?

    public init(
        timeZone: TimeZone?,
        peakStartHour: Int,
        peakEndHour: Int,
        peakMultiplier: Int,
        offPeakMultiplier: Int,
        promoMultiplier: Int? = nil,
        promoEndDate: Date? = nil
    ) {
        self.timeZone = timeZone
        self.peakStartHour = peakStartHour
        self.peakEndHour = peakEndHour
        self.peakMultiplier = peakMultiplier
        self.offPeakMultiplier = offPeakMultiplier
        self.promoMultiplier = promoMultiplier
        self.promoEndDate = promoEndDate
    }

    // MARK: - Queries

    public func isInPeak(at date: Date) -> Bool {
        guard let timeZone else { return false }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let hour = cal.component(.hour, from: date)
        return hour >= peakStartHour && hour < peakEndHour
    }

    public func multiplier(at date: Date) -> Int {
        if isInPeak(at: date) {
            return peakMultiplier
        }
        if let promoEnd = promoEndDate, date < promoEnd {
            return promoMultiplier ?? offPeakMultiplier
        }
        return offPeakMultiplier
    }
}

public enum UsageWindowDuration {
    public static let fiveHours: TimeInterval = 5 * 60 * 60
    public static let week: TimeInterval = 7 * 24 * 60 * 60
}

public struct UsageLine: Sendable {
    public let label: String
    public let used: Double?
    public let total: Double?
    public let percentage: Double?
    public let unit: String?
    public let resetDate: Date?
    public let windowDuration: TimeInterval?
    public let details: [UsageDetail]?

    public init(
        label: String,
        used: Double? = nil,
        total: Double? = nil,
        percentage: Double? = nil,
        unit: String? = nil,
        resetDate: Date? = nil,
        windowDuration: TimeInterval? = nil,
        details: [UsageDetail]? = nil
    ) {
        self.label = label
        self.used = used
        self.total = total
        self.percentage = percentage
        self.unit = unit
        self.resetDate = resetDate
        self.windowDuration = windowDuration
        self.details = details
    }
}

public struct UsageDetail: Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

// MARK: - ProviderAuth

/// Future auth shapes (e.g. OAuth tokens) get their own case — never bolted on
/// as a Stringly-typed field.
public enum ProviderAuth: Sendable {
    case apiKey(String)
    /// The provider derives its auth from the local environment (installed
    /// binary, helper process, cache file, etc.) — no API key needed.
    case apiKeyFree

    /// Payload-free discriminator so the registry can route without ever
    /// materializing a key it should not see.
    public enum Shape: Sendable {
        case apiKey
        case apiKeyFree
    }
}

// MARK: - AIProvider

/// Each provider formats its own headline string — Core never interprets it.
///
/// Core resolves the effective base URL (default vs. per-provider override)
/// and passes it into `fetchQuota` so providers never read the override
/// themselves.
public protocol AIProvider: Sendable {
    static var providerId: String { get }
    static var providerName: String { get }
    static var providerGlyph: ProviderGlyph { get }
    static var providerDescription: String { get }
    static var providerDisclaimer: String? { get }
    static var automaticRefreshDisclosure: ProviderAutomaticRefreshDisclosure? { get }
    /// Host root only; path segments stay inside `fetchQuota`.
    static var baseURL: URL { get }
    /// Non-payload discriminator the registry branches on so it never
    /// materializes a key it should not see.
    static var authShape: ProviderAuth.Shape { get }
    static var setupHelp: ProviderSetupHelp? { get }
    /// `nil` means this provider has no external credential source.
    static var credentialImportActionTitle: String? { get }

    // MARK: - Quota fetch

    /// Providers that expect `.apiKey` should pattern-match `.apiKey(let key)`;
    /// providers that are `.apiKeyFree` never see `.apiKey`, and vice versa.
    func fetchQuota(auth: ProviderAuth, baseURL: URL) async throws -> ProviderQuota

    // MARK: - Configuration

    /// The default returns `true`, which is only correct for `.apiKey`
    /// providers — the registry routes `.apiKey` providers through the
    /// Keychain path and never calls this. `.apiKeyFree` providers MUST
    /// override to return their real state (binary present, helper installed,
    /// etc.).
    func isConfigured() -> Bool

    /// `.apiKeyFree` providers return their current setup state (e.g. why the
    /// provider is not ready). `.apiKey` providers never need this — the
    /// registry never calls it for them.
    func currentSetupState() async -> ProviderState?

    // MARK: - Helper management

    /// Only `.apiKeyFree` providers that require a local helper override this;
    /// the default throws `ProviderSetupError.notSupported`.
    func installHelper() async throws

    /// Restores any configuration the install touched. Only `.apiKeyFree`
    /// providers override this.
    func removeHelper() async throws

    /// Returns `false` for `.apiKey` providers and for `.apiKeyFree` providers
    /// whose binary is missing.
    func canInstallHelper() -> Bool

    /// Provider-owned external source; only on explicit user action.
    func importCredentials() async throws
}

// MARK: - AIProvider defaults

public extension AIProvider {
    static var providerGlyph: ProviderGlyph {
        .sfSymbol("cpu")
    }

    static var authShape: ProviderAuth.Shape {
        .apiKey
    }

    static var setupHelp: ProviderSetupHelp? {
        nil
    }

    static var credentialImportActionTitle: String? {
        nil
    }

    static var providerDisclaimer: String? {
        nil
    }

    static var automaticRefreshDisclosure: ProviderAutomaticRefreshDisclosure? {
        nil
    }

    /// Defaults to `true` — only correct for `.apiKey` providers, which the
    /// registry routes through the Keychain path, never calling this.
    func isConfigured() -> Bool {
        true
    }

    /// Defaults to `nil` — `.apiKey` providers are never asked for setup state.
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

    func importCredentials() async throws {
        throw ProviderSetupError.notSupported
    }
}

public enum ProviderState: Sendable {
    case unconfigured
    /// The associated value is a human-readable reason the provider isn't ready.
    case setup(String)
    case loading
    case loaded(ProviderQuota)
    case error(String)
}

// MARK: - ProviderSetupError

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
            String(localized: "This provider does not support this action.")
        }
    }
}

// MARK: - ProactiveRefreshable

/// Opt-in: providers that derive data purely from the network on every fetch
/// (e.g. `.apiKey` providers like ZAI) never conform, and the registry reports
/// `ProviderSetupError.notSupported` for them. Providers whose data comes from
/// a side channel that an external action can refresh (e.g. Claude Code's
/// statusline cache) conform and implement `proactiveRefresh()` to trigger
/// that action.
public protocol ProactiveRefreshable: AIProvider {
    /// Implementations should block until the refresh is observably complete
    /// (e.g. the cache file has been rewritten) or a bounded timeout elapses,
    /// so the caller's subsequent `fetchQuota` reads fresh data. Failures
    /// should throw; the view model catches them and proceeds to `fetchQuota`
    /// regardless, surfacing whatever cached data is available.
    func proactiveRefresh() async throws
}

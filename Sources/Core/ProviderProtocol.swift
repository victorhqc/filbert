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

/// Protocol every AI provider module must conform to (core 01).
///
/// Each provider is responsible for formatting its own headline string —
/// the Core layer never interprets it.
public protocol AIProvider: Sendable {
    static var providerId: String { get }
    static var providerName: String { get }
    /// Short, localized description shown in the Settings provider list (ui 02).
    static var providerDescription: String { get }
    func fetchQuota(apiKey: String) async throws -> ProviderQuota
}

/// Metadata about a registered provider, surfaced by the registry (ui 02 Plan 1).
public struct ProviderInfo: Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let description: String

    public init(id: String, displayName: String, description: String) {
        self.id = id
        self.displayName = displayName
        self.description = description
    }
}

/// Per-provider state the view model tracks (ui 02 Plan 2).
public enum ProviderState: Sendable {
    case unconfigured
    case loading
    case loaded(ProviderQuota)
    case error(String)
}

import Core
import Foundation

// MARK: - Cache path

public let claudeCodeCacheFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".cache")
    .appendingPathComponent("filbert")
    .appendingPathComponent("claude-code.json")

// MARK: - Cache model

/// Mirrors the `rate_limits` shape documented at
/// https://code.claude.com/docs/en/statusline as of 2026-07.
struct StatuslineCache: Codable {
    let writtenAt: TimeInterval
    /// `nil` for free-tier or brand-new sessions that carry no rate-limit data.
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case writtenAt = "written_at"
        case rateLimits = "rate_limits"
    }
}

struct RateLimits: Codable {
    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

/// Every field is optional, so a percentage survives an unparseable reset.
struct Window: Codable {
    let usedPercentage: Double?
    /// Unix seconds, not milliseconds.
    let resetsAt: TimeInterval?
    /// Unix seconds. A carried-over window keeps its time, so a later write
    /// cannot make it fresh.
    let writtenAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
        case writtenAt = "written_at"
    }

    init(usedPercentage: Double? = nil, resetsAt: TimeInterval? = nil, writtenAt: TimeInterval? = nil) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
        self.writtenAt = writtenAt
    }

    var populated: Window? {
        usedPercentage != nil || resetsAt != nil ? self : nil
    }

    func stamped(at time: TimeInterval) -> Window {
        Window(usedPercentage: usedPercentage, resetsAt: resetsAt, writtenAt: time)
    }

    /// A helper-written window has no time of its own, so it ages with its cache.
    func aged(fromCacheWrittenAt time: TimeInterval?) -> Window {
        guard writtenAt == nil, let time else { return self }
        return Window(usedPercentage: usedPercentage, resetsAt: resetsAt, writtenAt: time)
    }
}

// MARK: - Cache store

enum StatuslineCacheError: Error, LocalizedError, Equatable, DiagnosticError {
    case readFailed
    case decodeFailed

    var diagnosticCode: String {
        switch self {
        case .readFailed: "cache-read-failed"
        case .decodeFailed: "cache-decode-failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .readFailed:
            String(displayLocalized: "Couldn't read Claude Code usage data. Try again.", bundle: .module)
        case .decodeFailed:
            String(displayLocalized: "Claude Code usage data is in an unexpected format. Try again.", bundle: .module)
        }
    }
}

public struct StatuslineCacheStore: Sendable {
    private let cacheURL: URL
    private let fallbackCacheURL: URL?
    private let errorLog: ErrorLog

    public init() {
        cacheURL = claudeCodeCacheFileURL
        fallbackCacheURL = LegacyClaudeBrandConfiguration.production.cacheURL
        errorLog = .shared
    }

    public init(cacheURL: URL, errorLog: ErrorLog = .shared) {
        self.cacheURL = cacheURL
        fallbackCacheURL = nil
        self.errorLog = errorLog
    }

    init(cacheURL: URL, fallbackCacheURL: URL?, errorLog: ErrorLog = .shared) {
        self.cacheURL = cacheURL
        self.fallbackCacheURL = fallbackCacheURL
        self.errorLog = errorLog
    }

    func read() -> StatuslineCache? {
        do {
            return try readForQuota()
        } catch {
            errorLog.record(
                component: "claude-code-cache", operation: "read-cache",
                code: (error as? StatuslineCacheError) == .decodeFailed ? "cache-decode-failed" : "cache-read-failed",
                providerID: "claude-code", error: error
            )
            return nil
        }
    }

    func readForQuota() throws -> StatuslineCache? {
        if let cache = try read(at: cacheURL) {
            return cache
        }
        guard let fallbackCacheURL else {
            return nil
        }
        return try read(at: fallbackCacheURL)
    }

    private func read(at url: URL) throws -> StatuslineCache? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let error = error as NSError
            let isMissing = error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
            if isMissing {
                return nil
            }
            throw StatuslineCacheError.readFailed
        }
        do {
            return try JSONDecoder().decode(StatuslineCache.self, from: data)
        } catch {
            throw StatuslineCacheError.decodeFailed
        }
    }

    func write(_ cache: StatuslineCache) throws {
        let dir = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(cache)

        try data.write(to: cacheURL, options: .atomic)
    }
}

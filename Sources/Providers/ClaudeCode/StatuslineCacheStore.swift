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

/// Both fields are optional so a partial parse (e.g. a percentage whose reset
/// phrase couldn't be parsed) still surfaces what it has rather than dropping
/// the whole window.
struct Window: Codable {
    let usedPercentage: Double?
    /// Unix epoch **seconds** when this window resets.
    let resetsAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    init(usedPercentage: Double? = nil, resetsAt: TimeInterval? = nil) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

// MARK: - Cache store

public struct StatuslineCacheStore: Sendable {
    private let cacheURL: URL
    private let fallbackCacheURL: URL?

    public init() {
        cacheURL = claudeCodeCacheFileURL
        fallbackCacheURL = LegacyClaudeBrandConfiguration.production.cacheURL
    }

    public init(cacheURL: URL) {
        self.cacheURL = cacheURL
        fallbackCacheURL = nil
    }

    init(cacheURL: URL, fallbackCacheURL: URL?) {
        self.cacheURL = cacheURL
        self.fallbackCacheURL = fallbackCacheURL
    }

    /// A missing or unparseable cache is a data state, not an error.
    func read() -> StatuslineCache? {
        if let cache = read(at: cacheURL) {
            return cache
        }
        guard let fallbackCacheURL else {
            return nil
        }
        return read(at: fallbackCacheURL)
    }

    private func read(at url: URL) -> StatuslineCache? {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            ClaudeCodeLog.log("read: cache file missing at \(path)")
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            ClaudeCodeLog.log("read: failed to read \(path)")
            return nil
        }
        guard let cache = try? JSONDecoder().decode(StatuslineCache.self, from: data) else {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
            ClaudeCodeLog.log("read: failed to decode \(path) bytes=\(data.count) preview=\(preview)")
            return nil
        }
        ClaudeCodeLog.log("read: ok path=\(path) writtenAt=\(cache.writtenAt) hasRateLimits=\(cache.rateLimits != nil)")
        return cache
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

        let tempURL = dir.appendingPathComponent(
            ".claude-code.tmp.\(UUID().uuidString)"
        )
        try data.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(
            cacheURL,
            withItemAt: tempURL,
            backupItemName: nil
        )
    }
}

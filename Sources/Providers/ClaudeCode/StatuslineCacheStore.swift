import Foundation

// MARK: - Cache path (providers 02 AC4)

/// `~/.cache/ai-usage/claude-code.json` — the single source of truth
/// for Claude Code usage data (providers 02 AC4).
public let claudeCodeCacheFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".cache")
    .appendingPathComponent("ai-usage")
    .appendingPathComponent("claude-code.json")

// MARK: - Cache model (providers 02 AC5)

/// Full cache payload the helper script writes and the provider reads.
/// Mirrors the `rate_limits` shape documented at
/// https://code.claude.com/docs/en/statusline as of 2026-07.
struct StatuslineCache: Codable {
    /// Unix epoch seconds of when the helper wrote this cache file.
    let writtenAt: TimeInterval
    /// The `rate_limits` subtree from Claude Code's statusline JSON.
    /// `nil` when the subscription does not carry rate-limit data
    /// (free-tier or brand-new session) (providers 02 AC5).
    let rateLimits: RateLimits?

    enum CodingKeys: String, CodingKey {
        case writtenAt = "written_at"
        case rateLimits = "rate_limits"
    }
}

/// The two sliding windows Claude Code reports for Pro/Max subscribers.
struct RateLimits: Codable {
    let fiveHour: Window?
    let sevenDay: Window?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

/// One usage window: a used-percentage value and a reset timestamp.
struct Window: Codable {
    /// Percentage of the window consumed (0–100).
    let usedPercentage: Double
    /// Unix epoch **seconds** when this window resets (providers 02 AC5).
    let resetsAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

// MARK: - Cache store (providers 02 AC4, AC7)

/// Reads (and, in tests, writes) the Claude Code statusline cache.
///
/// In production the helper script owns writes; the provider only reads.
/// The `write` method exists so tests can seed cache fixtures and verify
/// the atomic-write contract (providers 02 AC7).
public struct StatuslineCacheStore: Sendable {
    private let cacheURL: URL

    public init(cacheURL: URL = claudeCodeCacheFileURL) {
        self.cacheURL = cacheURL
    }

    /// Reads and decodes the cache file. Returns `nil` when the file is
    /// absent or unparseable — a missing cache is a data state, not an error
    /// (providers 02 AC10).
    func read() -> StatuslineCache? {
        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(StatuslineCache.self, from: data)
        else {
            return nil
        }
        return cache
    }

    /// Writes `cache` atomically via temp-file + rename so a concurrent
    /// reader never sees a half-written file (providers 02 AC7).
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

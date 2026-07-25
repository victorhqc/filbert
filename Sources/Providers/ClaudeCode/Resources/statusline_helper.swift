#!/usr/bin/env swift
import Foundation

// Reads Claude Code statusline JSON from stdin, extracts `rate_limits`,
// and writes an atomic cache for the filbert menu bar app.
//
// This source is compiled at install time with `swiftc -O` so the helper
// binary has near-zero cold-start latency when Claude Code spawns it on
// every statusline update (providers 02 Plan §5).

// MARK: - Codable shapes

//
// The input and output JSON shapes are mirrored as Codable structs instead of
// `[String: Any]` + `JSONSerialization` so this file stays free of the `Any`
// type (ci 04 AC7). Field names and nesting match the shape the cache reader
// (`StatuslineCacheStore`) decodes.

/// One window inside the statusline payload. Fields are optional so a partial
/// payload (missing `used_percentage` or `resets_at`) still decodes; the
/// defaults are applied when building the cache (matching the previous
/// `as? Double ?? 0` behaviour).
struct StatuslineWindow: Decodable {
    let usedPercentage: Double?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

struct StatuslineRateLimits: Decodable {
    let fiveHour: StatuslineWindow?
    let sevenDay: StatuslineWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct StatuslineInput: Decodable {
    let rateLimits: StatuslineRateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

/// A non-optional window in the cache. The previous implementation defaulted
/// missing values to `0`, and the cache reader treats `0` as "unknown" via the
/// optional fields on its own model, so writing `0` here preserves that.
struct CacheWindow: Encodable {
    let usedPercentage: Double
    let resetsAt: Double

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }
}

struct CacheRateLimits: Encodable {
    let fiveHour: CacheWindow?
    let sevenDay: CacheWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct CachePayload: Encodable {
    let writtenAt: Double
    let rateLimits: CacheRateLimits?

    enum CodingKeys: String, CodingKey {
        case writtenAt = "written_at"
        case rateLimits = "rate_limits"
    }
}

// MARK: - Paths

let cacheDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".cache")
    .appendingPathComponent("filbert")
let cachePath = cacheDir.appendingPathComponent("claude-code.json")

// MARK: - Read stdin

let rawInput = FileHandle.standardInput.readDataToEndOfFile()

// MARK: - Parse

let writtenAt = Date().timeIntervalSince1970

// Diagnostic log: every invocation lands here so we can confirm Claude
// Code is actually spawning the helper. Writes to a sibling file next to
// the cache so it never interferes with stdout (which Claude Code captures).
let debugLogURL = cacheDir.appendingPathComponent("claude-code.helper.log")
let debugLine = "\(Date()) invoked pid=\(ProcessInfo.processInfo.processIdentifier) bytes=\(rawInput.count)\n"
appendDiagnosticLine(debugLine, to: debugLogURL)

/// Decode the statusline payload, tolerating empty/absent/unparseable input.
/// A failed decode writes a cache with no `rate_limits` so the provider
/// surfaces "No data" rather than silently clearing the last known state
/// (providers 02 AC10).
let input = (try? JSONDecoder().decode(StatuslineInput.self, from: rawInput))
    ?? StatuslineInput(rateLimits: nil)

/// Convert the decoded optional windows into non-optional cache windows,
/// applying the historical `?? 0` default for missing fields.
let fiveHour: CacheWindow? = input.rateLimits?.fiveHour.map {
    CacheWindow(
        usedPercentage: $0.usedPercentage ?? 0,
        resetsAt: $0.resetsAt ?? 0
    )
}

let sevenDay: CacheWindow? = input.rateLimits?.sevenDay.map {
    CacheWindow(
        usedPercentage: $0.usedPercentage ?? 0,
        resetsAt: $0.resetsAt ?? 0
    )
}

/// Match the previous "only write rate_limits when at least one window is
/// present" behaviour: an empty `rate_limits` object is never written.
let rateLimits: CacheRateLimits? = (fiveHour != nil || sevenDay != nil)
    ? CacheRateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
    : nil

writeCache(CachePayload(writtenAt: writtenAt, rateLimits: rateLimits))

// MARK: - Atomic write (providers 02 AC7)

func writeCache(_ payload: CachePayload) {
    try? FileManager.default.createDirectory(
        at: cacheDir,
        withIntermediateDirectories: true
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(payload) else { return }

    let tempPath = cachePath.path + ".tmp." + UUID().uuidString
    let tempURL = URL(fileURLWithPath: tempPath)

    try? data.write(to: tempURL, options: .atomic)
    _ = try? FileManager.default.replaceItemAt(
        cachePath,
        withItemAt: tempURL,
        backupItemName: nil
    )
}

// MARK: - Diagnostic log

/// Appends `line` to `logURL`, creating the file on first write. Best-effort:
/// any I/O failure is silently dropped so diagnostics never break the cache
/// write path.
func appendDiagnosticLine(_ line: String, to logURL: URL) {
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logURL.path) {
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    } else {
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: logURL, options: .atomic)
    }
}

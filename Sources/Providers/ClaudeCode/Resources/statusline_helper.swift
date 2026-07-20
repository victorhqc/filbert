#!/usr/bin/env swift
import Foundation

// Reads Claude Code statusline JSON from stdin, extracts `rate_limits`,
// and writes an atomic cache for the ai-usage menu bar app.
//
// This source is compiled at install time with `swiftc -O` so the helper
// binary has near-zero cold-start latency when Claude Code spawns it on
// every statusline update (providers 02 Plan §5).

// MARK: - Paths

let cacheDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".cache")
    .appendingPathComponent("ai-usage")
let cachePath = cacheDir.appendingPathComponent("claude-code.json")

// MARK: - Read stdin

let rawInput = FileHandle.standardInput.readDataToEndOfFile()

// MARK: - Parse

let writtenAt = Date().timeIntervalSince1970

guard !rawInput.isEmpty,
      let root = try? JSONSerialization.jsonObject(with: rawInput) as? [String: Any]
else {
    // No input or unparseable — write a cache with no rate_limits so the
    // provider surfaces "No data" rather than silently clearing the last
    // known state (providers 02 AC10).
    writeCache(["written_at": writtenAt])
    exit(0)
}

var cache: [String: Any] = ["written_at": writtenAt]

if let rateLimits = root["rate_limits"] as? [String: Any] {
    var rateLimitDict: [String: Any] = [:]

    if let fiveHourDict = rateLimits["five_hour"] as? [String: Any] {
        rateLimitDict["five_hour"] = [
            "used_percentage": fiveHourDict["used_percentage"] as? Double ?? 0,
            "resets_at": fiveHourDict["resets_at"] as? TimeInterval ?? 0,
        ]
    }

    if let sevenDayDict = rateLimits["seven_day"] as? [String: Any] {
        rateLimitDict["seven_day"] = [
            "used_percentage": sevenDayDict["used_percentage"] as? Double ?? 0,
            "resets_at": sevenDayDict["resets_at"] as? TimeInterval ?? 0,
        ]
    }

    if !rateLimitDict.isEmpty {
        cache["rate_limits"] = rateLimitDict
    }
}

writeCache(cache)

// MARK: - Atomic write (providers 02 AC7)

func writeCache(_ dict: [String: Any]) {
    try? FileManager.default.createDirectory(
        at: cacheDir,
        withIntermediateDirectories: true
    )

    guard let data = try? JSONSerialization.data(
        withJSONObject: dict,
        options: [.sortedKeys]
    ) else { return }

    let tempPath = cachePath.path + ".tmp." + UUID().uuidString
    let tempURL = URL(fileURLWithPath: tempPath)

    try? data.write(to: tempURL, options: .atomic)
    _ = try? FileManager.default.replaceItemAt(
        cachePath,
        withItemAt: tempURL,
        backupItemName: nil
    )
}

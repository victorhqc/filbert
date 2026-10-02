import Core
import Foundation

struct StatuslineWindow: Codable {
    let usedPercentage: Double?
    let resetsAt: Double?

    enum CodingKeys: String, CodingKey {
        case usedPercentage = "used_percentage"
        case resetsAt = "resets_at"
    }

    var populated: StatuslineWindow? {
        usedPercentage != nil || resetsAt != nil ? self : nil
    }
}

struct StatuslineRateLimits: Codable {
    let fiveHour: StatuslineWindow?
    let sevenDay: StatuslineWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }

    var populated: StatuslineRateLimits? {
        let fiveHour = fiveHour?.populated
        let sevenDay = sevenDay?.populated
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return StatuslineRateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
    }
}

struct StatuslineInput: Decodable {
    let rateLimits: StatuslineRateLimits?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }
}

struct CachePayload: Encodable {
    let writtenAt: Double
    let rateLimits: StatuslineRateLimits?

    enum CodingKeys: String, CodingKey {
        case writtenAt = "written_at"
        case rateLimits = "rate_limits"
    }
}

func option(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let home = FileManager.default.homeDirectoryForCurrentUser
let cacheURL = option("--cache-path").map { URL(fileURLWithPath: $0) }
    ?? home.appendingPathComponent(".cache/filbert/claude-code.json")
let log = option("--log-directory").map { ErrorLog(directoryURL: URL(fileURLWithPath: $0)) }
    ?? .shared
let rawInput = FileHandle.standardInput.readDataToEndOfFile()

func updateCache() {
    let input: StatuslineInput
    do {
        input = try JSONDecoder().decode(StatuslineInput.self, from: rawInput)
    } catch {
        log.record(
            component: "claude-code-helper", operation: "decode-input",
            code: "invalid-input", providerID: "claude-code", error: error
        )
        return
    }

    do {
        let payload = CachePayload(
            writtenAt: Date().timeIntervalSince1970,
            rateLimits: input.rateLimits?.populated
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: cacheURL, options: .atomic)
    } catch {
        log.record(
            component: "claude-code-helper", operation: "write-cache",
            code: "cache-write-failed", providerID: "claude-code", error: error
        )
    }
}

updateCache()

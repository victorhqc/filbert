import Core
import Foundation

// MARK: - Parse & write

/// `/usage` prints lines like:
///   Current session: 77% used · resets Jul 21 at 12:59am (Europe/Berlin)
///   Current week (all models): 37% used · resets Jul 24 at 5:59am (Europe/Berlin)
/// "Current session" is the 5-hour window; "Current week (all models)" is the
/// 7-day window. Lines that don't match are skipped rather than guessed.
extension ClaudeCodeRefresher {
    enum WindowSlot {
        case fiveHour
        case sevenDay
    }

    struct ParsedWindow {
        let slot: WindowSlot
        let window: Window
    }

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// `resets_at` is a strict ISO 8601 instant with optional fractional seconds
    /// and a `Z` or `±HH:MM` offset. Foundation's formatters accept trailing text
    /// and normalize impossible dates, so the whole string is matched and the
    /// parsed components are round-tripped before the value is trusted.
    static func parseISOTimestamp(_ text: String) -> TimeInterval? {
        let pattern = #"\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})\z"#
        guard let match = firstMatch(pattern, in: text),
              let year = integerValue(match[1]),
              let month = integerValue(match[2]),
              let day = integerValue(match[3]),
              let hour = integerValue(match[4]),
              let minute = integerValue(match[5]),
              let second = integerValue(match[6]),
              let timeZone = timeZone(fromOffset: match[8])
        else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day,
              roundTrip.hour == hour, roundTrip.minute == minute, roundTrip.second == second
        else { return nil }

        return date.timeIntervalSince1970 + (match[7].flatMap { Double("0" + $0) } ?? 0)
    }

    private static func integerValue(_ text: String?) -> Int? {
        text.flatMap { Int($0) }
    }

    private static func timeZone(fromOffset offset: String?) -> TimeZone? {
        guard let offset else { return nil }
        guard offset != "Z" else { return TimeZone(secondsFromGMT: 0) }
        let parts = offset.dropFirst().split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else { return nil }
        let seconds = hours * 3600 + minutes * 60
        return TimeZone(secondsFromGMT: offset.hasPrefix("-") ? -seconds : seconds)
    }

    static func parseUsageWindows(fromText text: String) -> [ParsedWindow] {
        var parsed: [ParsedWindow] = []
        if let window = parseUsageLine(in: text, prefix: "Current session") {
            parsed.append(ParsedWindow(slot: .fiveHour, window: window))
        }
        if let window = parseUsageLine(in: text, prefix: "Current week (all models)") {
            parsed.append(ParsedWindow(slot: .sevenDay, window: window))
        }
        return parsed
    }

    static func parseUsageLine(in text: String, prefix: String) -> Window? {
        let escaped = NSRegularExpression.escapedPattern(for: prefix)
        guard let match = firstMatch(escaped + #":\s*(\d+)%\s*used([^\n]*)"#, in: text),
              let percentageString = match[1],
              let percentage = Double(percentageString)
        else { return nil }

        let remainder = match[2] ?? ""
        return Window(
            usedPercentage: percentage,
            resetsAt: parseResetPhrase(remainder)
        )
    }

    /// The year is absent from the reset text, so it's inferred as the nearest
    /// occurrence (this year, rolled to next year if that would already be in
    /// the past). Accepts both `12:59am` and `1am` styles.
    static func parseResetPhrase(_ phrase: String) -> TimeInterval? {
        let pattern = #"([A-Za-z]{3,})\s+(\d{1,2})\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*\(([^)]+)\)"#
        guard let match = firstMatch(pattern, in: phrase),
              let monthRaw = match[1],
              let monthNumber = monthNumbers[String(monthRaw.lowercased().prefix(3))],
              let dayString = match[2], let day = Int(dayString),
              let hourString = match[3], var hour = Int(hourString),
              let meridiem = match[5]?.lowercased(),
              let timeZoneID = match[6],
              let timeZone = TimeZone(identifier: timeZoneID)
        else { return nil }

        let minute = match[4].flatMap { Int($0) } ?? 0
        if meridiem == "pm", hour != 12 {
            hour += 12
        }
        if meridiem == "am", hour == 12 {
            hour = 0
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date()
        let currentYear = calendar.component(.year, from: now)
        var components = DateComponents()
        components.month = monthNumber
        components.day = day
        components.hour = hour
        components.minute = minute
        components.year = currentYear

        guard let candidate = calendar.date(from: components) else { return nil }
        // A reset that already passed (allowing 2-day slack for clock skew /
        // month boundaries) must belong to next year.
        if candidate < now.addingTimeInterval(-2 * 86400) {
            components.year = currentYear + 1
            if let rolled = calendar.date(from: components) {
                return rolled.timeIntervalSince1970
            }
        }
        return candidate.timeIntervalSince1970
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        return (0 ..< match.numberOfRanges).map { index in
            let matchRange = match.range(at: index)
            guard matchRange.location != NSNotFound,
                  let swiftRange = Range(matchRange, in: text)
            else { return nil }
            return String(text[swiftRange])
        }
    }

    /// Each parsed window replaces its slot; windows this run didn't report are
    /// carried over from the existing cache as a defensive measure (`/usage`
    /// normally prints both windows together).
    static func mergeAndWriteCache(
        windows: [ParsedWindow],
        into cacheStore: StatuslineCacheStore
    ) throws {
        let existing = cacheStore.read()
        let existingWrittenAt = existing?.writtenAt
        var fiveHour = existing?.rateLimits?.fiveHour?.aged(fromCacheWrittenAt: existingWrittenAt)
        var sevenDay = existing?.rateLimits?.sevenDay?.aged(fromCacheWrittenAt: existingWrittenAt)

        let now = Date().timeIntervalSince1970
        for parsed in windows {
            switch parsed.slot {
            case .fiveHour: fiveHour = parsed.window.stamped(at: now)
            case .sevenDay: sevenDay = parsed.window.stamped(at: now)
            }
        }

        let cache = StatuslineCache(
            writtenAt: now,
            rateLimits: RateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
        )

        try cacheStore.write(cache)
    }
}

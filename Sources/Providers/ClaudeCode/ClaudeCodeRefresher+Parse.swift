import Foundation

// MARK: - Parse & write (providers 03)

/// Turns the `claude -p "/usage" --output-format json` output into cache
/// windows and writes them. Split out of `ClaudeCodeRefresher` so each file
/// stays focused: the main type owns the process lifecycle, this extension
/// owns the text → cache mapping.
///
/// The `/usage` command prints (inside the JSON `result` field) lines like:
/// ```
/// Current session: 77% used · resets Jul 21 at 12:59am (Europe/Berlin)
/// Current week (all models): 37% used · resets Jul 24 at 5:59am (Europe/Berlin)
/// ```
/// "Current session" is the 5-hour window; "Current week (all models)" is the
/// 7-day window. The parse is English-oriented (the CLI's default); if a line
/// doesn't match, that window is simply skipped rather than guessed.
extension ClaudeCodeRefresher {
    /// Which cache slot a parsed line maps to.
    enum WindowSlot {
        case fiveHour
        case sevenDay
    }

    /// One usage window parsed out of the `/usage` text, tagged with its slot.
    struct ParsedWindow {
        let slot: WindowSlot
        let window: Window
    }

    private static let monthNumbers: [String: Int] = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]

    /// Decodes the `/usage` JSON envelope. The CLI emits a single object whose
    /// `result` field carries the usage text; the wrapper replaces
    /// `JSONSerialization` + `[String: Any]` so `Sources/` stays free of the
    /// `Any` type (ci 04 AC7).
    private struct UsageEnvelope: Decodable {
        let result: String
    }

    /// Decodes the `/usage` JSON, pulls the `result` text, and parses the
    /// session (5-hour) and week (7-day) lines out of it.
    static func parseUsageWindows(fromUsageJSON data: Data) -> [ParsedWindow] {
        guard let envelope = try? JSONDecoder().decode(UsageEnvelope.self, from: data) else {
            return []
        }
        let text = envelope.result

        var parsed: [ParsedWindow] = []
        if let window = parseUsageLine(in: text, prefix: "Current session") {
            parsed.append(ParsedWindow(slot: .fiveHour, window: window))
        }
        if let window = parseUsageLine(in: text, prefix: "Current week (all models)") {
            parsed.append(ParsedWindow(slot: .sevenDay, window: window))
        }
        return parsed
    }

    /// Parses a single `"<prefix>: NN% used · resets …"` line into a `Window`.
    /// Returns `nil` when the percentage can't be found; a missing/unparseable
    /// reset phrase yields a window with a percentage but no `resetsAt`.
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

    /// Parses a reset phrase such as `"Jul 21 at 12:59am (Europe/Berlin)"` or
    /// `"Jul 21 at 1am (Europe/Berlin)"` into a Unix timestamp. The year is
    /// absent from the text, so it's inferred as the nearest occurrence (this
    /// year, rolled to next year if that would already be well in the past).
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
        // 12-hour → 24-hour.
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
        // A reset that already passed (allowing a 2-day slack for clock skew /
        // month boundaries) must belong to next year.
        if candidate < now.addingTimeInterval(-2 * 86400) {
            components.year = currentYear + 1
            if let rolled = calendar.date(from: components) {
                return rolled.timeIntervalSince1970
            }
        }
        return candidate.timeIntervalSince1970
    }

    /// Runs `pattern` against `text` and returns its capture groups (index 0 is
    /// the whole match). A group that didn't participate is `nil`.
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

    /// Merges the freshly parsed windows over whatever the cache already holds
    /// and writes the result. Each parsed window *replaces* its slot; windows
    /// this run didn't report are carried over from the existing cache (a
    /// defensive measure — `/usage` normally prints both windows together).
    static func mergeAndWriteCache(
        windows: [ParsedWindow],
        into cacheStore: StatuslineCacheStore
    ) {
        let existing = cacheStore.read()
        var fiveHour = existing?.rateLimits?.fiveHour
        var sevenDay = existing?.rateLimits?.sevenDay

        for parsed in windows {
            switch parsed.slot {
            case .fiveHour: fiveHour = parsed.window
            case .sevenDay: sevenDay = parsed.window
            }
        }

        let cache = StatuslineCache(
            writtenAt: Date().timeIntervalSince1970,
            rateLimits: RateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
        )

        do {
            try cacheStore.write(cache)
            ClaudeCodeRefresherLog.log(
                "mergeAndWriteCache: wrote cache fiveHour=\(fiveHour != nil) sevenDay=\(sevenDay != nil)"
            )
        } catch {
            ClaudeCodeRefresherLog.log(
                "mergeAndWriteCache: write failed: \(error.localizedDescription)"
            )
        }
    }
}

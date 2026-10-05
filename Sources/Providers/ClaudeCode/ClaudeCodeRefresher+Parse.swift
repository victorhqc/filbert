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

    struct UsageOutputValidation {
        let windows: [ParsedWindow]
        let failure: OutputFailure?
        let cliReportedError: Bool?
    }

    private enum JSONShape {
        case invalid
        case nonObject
        case object
    }

    static func validateUsageOutput(_ data: Data, truncated: Bool) -> UsageOutputValidation {
        if truncated {
            return UsageOutputValidation(windows: [], failure: .outputTooLarge, cliReportedError: nil)
        }
        guard !isWhitespaceOnly(data) else {
            return UsageOutputValidation(windows: [], failure: .emptyOutput, cliReportedError: nil)
        }
        guard let envelope = try? JSONDecoder().decode(UsageEnvelope.self, from: data) else {
            return UsageOutputValidation(
                windows: [],
                failure: jsonShape(data) == .invalid ? .invalidJSON : .invalidEnvelope,
                cliReportedError: nil
            )
        }
        guard envelope.isError != true else {
            return UsageOutputValidation(windows: [], failure: .cliReportedError, cliReportedError: true)
        }

        var prose: [ParsedWindow] = []
        if case let .present(text) = envelope.resultState {
            prose = parseUsageWindows(fromText: text)
        }
        let windows = mergeWindows(
            prose: prose,
            structured: parseStructuredWindows(from: envelope.limitRows)
        )
        guard windows.isEmpty else {
            return UsageOutputValidation(windows: windows, failure: nil, cliReportedError: envelope.isError)
        }
        return UsageOutputValidation(
            windows: [],
            failure: failureReason(for: envelope),
            cliReportedError: envelope.isError
        )
    }

    /// Structured rows win per slot; the prose parser only fills a slot the
    /// structured report left empty. Repeated structured rows for one kind
    /// collapse to the last one.
    private static func mergeWindows(prose: [ParsedWindow], structured: [ParsedWindow]) -> [ParsedWindow] {
        var fiveHour: Window?
        var sevenDay: Window?
        for parsed in prose + structured {
            switch parsed.slot {
            case .fiveHour: fiveHour = parsed.window
            case .sevenDay: sevenDay = parsed.window
            }
        }
        var merged: [ParsedWindow] = []
        if let fiveHour {
            merged.append(ParsedWindow(slot: .fiveHour, window: fiveHour))
        }
        if let sevenDay {
            merged.append(ParsedWindow(slot: .sevenDay, window: sevenDay))
        }
        return merged
    }

    private static func failureReason(for envelope: UsageEnvelope) -> OutputFailure {
        if envelope.hasUsageReport {
            return .usageWindowsMissing
        }
        switch envelope.resultState {
        case .missing: return .resultMissing
        case .invalid: return .resultInvalid
        case .present: return .usageWindowsMissing
        }
    }

    private static func parseStructuredWindows(from rows: [UsageRow]) -> [ParsedWindow] {
        rows.compactMap { row in
            guard let slot = structuredSlot(for: row.kind), let percent = row.percent else {
                return nil
            }
            return ParsedWindow(
                slot: slot,
                window: Window(usedPercentage: percent, resetsAt: row.resetsAt.flatMap(parseISOTimestamp))
            )
        }
    }

    private static func structuredSlot(for kind: String?) -> WindowSlot? {
        switch kind {
        case "session": .fiveHour
        case "weekly_all": .sevenDay
        default: nil
        }
    }

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

    private static func isWhitespaceOnly(_ data: Data) -> Bool {
        data.allSatisfy { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0B || byte == 0x0C
        }
    }

    private static func jsonShape(_ data: Data) -> JSONShape {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return .invalid
        }
        return root is NSDictionary ? .object : .nonObject
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

/// A `/usage --output-format json` response. The root object carries the prose
/// `result` and/or a structured `usage_report`; every other field is ignored.
private struct UsageEnvelope: Decodable {
    enum ResultState {
        case missing
        case invalid
        case present(String)
    }

    let isError: Bool?
    let resultState: ResultState
    let hasUsageReport: Bool
    let limitRows: [UsageRow]

    private enum CodingKeys: String, CodingKey {
        case isError = "is_error"
        case result
        case usageReport = "usage_report"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isError = try? container.decode(Bool.self, forKey: .isError)
        if !container.contains(.result) {
            resultState = .missing
        } else if let text = try? container.decode(String.self, forKey: .result) {
            resultState = .present(text)
        } else {
            resultState = .invalid
        }

        hasUsageReport = container.contains(.usageReport)
        limitRows = (try? container.decode(UsageReport.self, forKey: .usageReport))?
            .rateLimits?.limits?.compactMap(\.value) ?? []
    }
}

private struct UsageReport: Decodable {
    let rateLimits: Payload?

    enum CodingKeys: String, CodingKey {
        case rateLimits = "rate_limits"
    }

    struct Payload: Decodable {
        let limits: [Lossy<UsageRow>]?
    }
}

private struct UsageRow: Decodable {
    let kind: String?
    let percent: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case kind, percent
        case resetsAt = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try? container.decode(String.self, forKey: .kind)
        percent = try? container.decode(Double.self, forKey: .percent)
        resetsAt = try? container.decode(String.self, forKey: .resetsAt)
    }
}

/// Decodes each element independently so one malformed row does not drop the
/// rest of the array.
private struct Lossy<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

import Core
import Foundation

// MARK: - Validate

/// `--output-format json` normally prints one result object. A verbose view
/// mode that `--settings` cannot override, such as a managed setting, prints
/// an array of every session message instead (providers 16).
extension ClaudeCodeRefresher {
    struct UsageOutputValidation {
        let windows: [ParsedWindow]
        let failure: OutputFailure?
        let cliReportedError: Bool?
        let rootShape: JSONRootShape?

        static func failed(
            _ failure: OutputFailure,
            cliReportedError: Bool? = nil,
            rootShape: JSONRootShape? = nil
        ) -> UsageOutputValidation {
            UsageOutputValidation(
                windows: [],
                failure: failure,
                cliReportedError: cliReportedError,
                rootShape: rootShape
            )
        }
    }

    static func validateUsageOutput(_ data: Data, truncated: Bool) -> UsageOutputValidation {
        if truncated {
            return .failed(.outputTooLarge)
        }
        guard !isWhitespaceOnly(data) else {
            return .failed(.emptyOutput)
        }
        guard let root = try? JSONDecoder().decode(UsageRoot.self, from: data) else {
            return .failed(.invalidJSON)
        }
        switch root {
        case let .object(envelope): return validate(envelope)
        case let .array(messages): return validate(messages)
        case .scalar: return .failed(.invalidEnvelope, rootShape: .scalar)
        case .null: return .failed(.invalidEnvelope, rootShape: .null)
        }
    }

    private static func validate(_ envelope: UsageEnvelope) -> UsageOutputValidation {
        guard envelope.isError != true else {
            return .failed(.cliReportedError, cliReportedError: true, rootShape: .object)
        }

        var prose = WindowSlots()
        if case let .present(text) = envelope.resultState {
            prose.record(parseUsageWindows(fromText: text))
        }
        var structured = WindowSlots()
        structured.record(parseStructuredWindows(from: envelope.limitRows))

        let windows = structured.fillingGaps(from: prose).windows
        guard windows.isEmpty else {
            return UsageOutputValidation(
                windows: windows,
                failure: nil,
                cliReportedError: envelope.isError,
                rootShape: .object
            )
        }
        return .failed(failureReason(for: envelope), cliReportedError: envelope.isError, rootShape: .object)
    }

    private static func validate(_ messages: MessageArraySummary) -> UsageOutputValidation {
        guard messages.elementCount > 0, !messages.containsNonObject else {
            return .failed(.invalidEnvelope, rootShape: .array)
        }
        guard messages.containsResultMessage else {
            return .failed(.resultMissing, rootShape: .array)
        }
        guard messages.cliReportedError != true else {
            return .failed(.cliReportedError, cliReportedError: true, rootShape: .array)
        }

        let windows = messages.windows
        guard windows.isEmpty else {
            return UsageOutputValidation(
                windows: windows,
                failure: nil,
                cliReportedError: messages.cliReportedError,
                rootShape: .array
            )
        }
        return .failed(messages.failureReason, cliReportedError: messages.cliReportedError, rootShape: .array)
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

    fileprivate static func parseStructuredWindows(from rows: [UsageRow]) -> [ParsedWindow] {
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

    private static func isWhitespaceOnly(_ data: Data) -> Bool {
        data.allSatisfy { byte in
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0B || byte == 0x0C
        }
    }
}

/// The last window recorded for each slot.
private struct WindowSlots {
    private var fiveHour: Window?
    private var sevenDay: Window?

    mutating func record(_ windows: [ClaudeCodeRefresher.ParsedWindow]) {
        for parsed in windows {
            switch parsed.slot {
            case .fiveHour: fiveHour = parsed.window
            case .sevenDay: sevenDay = parsed.window
            }
        }
    }

    func fillingGaps(from fallback: WindowSlots) -> WindowSlots {
        var merged = self
        merged.fiveHour = fiveHour ?? fallback.fiveHour
        merged.sevenDay = sevenDay ?? fallback.sevenDay
        return merged
    }

    var windows: [ClaudeCodeRefresher.ParsedWindow] {
        var windows: [ClaudeCodeRefresher.ParsedWindow] = []
        if let fiveHour {
            windows.append(ClaudeCodeRefresher.ParsedWindow(slot: .fiveHour, window: fiveHour))
        }
        if let sevenDay {
            windows.append(ClaudeCodeRefresher.ParsedWindow(slot: .sevenDay, window: sevenDay))
        }
        return windows
    }
}

/// `JSONDecoder` rejects malformed JSON before this initializer runs, so every
/// throw from decoding a `UsageRoot` means invalid JSON.
private enum UsageRoot: Decodable {
    case object(UsageEnvelope)
    case array(MessageArraySummary)
    case scalar
    case null

    init(from decoder: Decoder) throws {
        if let envelope = try? UsageEnvelope(from: decoder) {
            self = .object(envelope)
        } else if (try? decoder.unkeyedContainer()) != nil {
            self = try .array(MessageArraySummary(from: decoder))
        } else {
            self = try decoder.singleValueContainer().decodeNil() ? .null : .scalar
        }
    }
}

/// Folds each array element into fixed state as it is decoded, so no
/// collection of complete messages is kept. `result` and `is_error` count only
/// on `type: "result"` elements; a `usage_report` counts on any element but
/// ranks below everything a result element supplies, because the `init`
/// message is emitted before `/usage` runs.
private struct MessageArraySummary: Decodable {
    private(set) var elementCount = 0
    private(set) var containsNonObject = false
    private(set) var containsResultMessage = false
    private var containsUsageReport = false
    private var containsStringResult = false
    private var containsInvalidResult = false
    private var containsErrorTrue = false
    private var containsErrorFalse = false
    private var resultReports = WindowSlots()
    private var resultProse = WindowSlots()
    private var otherReports = WindowSlots()

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            try record(container.decode(MessageElement.self))
        }
    }

    var cliReportedError: Bool? {
        if containsErrorTrue {
            return true
        }
        return containsErrorFalse ? false : nil
    }

    var windows: [ClaudeCodeRefresher.ParsedWindow] {
        resultReports
            .fillingGaps(from: resultProse)
            .fillingGaps(from: otherReports)
            .windows
    }

    var failureReason: OutputFailure {
        if containsUsageReport || containsStringResult {
            return .usageWindowsMissing
        }
        return containsInvalidResult ? .resultInvalid : .resultMissing
    }

    private mutating func record(_ element: MessageElement) {
        elementCount += 1
        guard case let .object(envelope) = element else {
            containsNonObject = true
            return
        }

        containsUsageReport = containsUsageReport || envelope.hasUsageReport
        let reportWindows = ClaudeCodeRefresher.parseStructuredWindows(from: envelope.limitRows)
        guard envelope.messageType == "result" else {
            otherReports.record(reportWindows)
            return
        }

        containsResultMessage = true
        resultReports.record(reportWindows)
        containsErrorTrue = containsErrorTrue || envelope.isError == true
        containsErrorFalse = containsErrorFalse || envelope.isError == false
        switch envelope.resultState {
        case .missing:
            break
        case .invalid:
            containsInvalidResult = true
        case let .present(text):
            containsStringResult = true
            resultProse.record(ClaudeCodeRefresher.parseUsageWindows(fromText: text))
        }
    }
}

private enum MessageElement: Decodable {
    case object(UsageEnvelope)
    case nonObject

    init(from decoder: Decoder) {
        guard let envelope = try? UsageEnvelope(from: decoder) else {
            self = .nonObject
            return
        }
        self = .object(envelope)
    }
}

/// A result object, or one element of a message array. Only the root must be
/// an object; every field decodes leniently and other fields are ignored.
private struct UsageEnvelope: Decodable {
    enum ResultState {
        case missing
        case invalid
        case present(String)
    }

    let messageType: String?
    let isError: Bool?
    let resultState: ResultState
    let hasUsageReport: Bool
    let limitRows: [UsageRow]

    private enum CodingKeys: String, CodingKey {
        case messageType = "type"
        case isError = "is_error"
        case result
        case usageReport = "usage_report"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageType = try? container.decode(String.self, forKey: .messageType)
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

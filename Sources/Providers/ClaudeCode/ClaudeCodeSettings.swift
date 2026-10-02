import Core
import Foundation

public let claudeHelperDestURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude")
    .appendingPathComponent("filbert-statusline")

public let claudeSettingsFileURL: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".claude")
    .appendingPathComponent("settings.json")

public enum InstallerError: Error, Equatable, Sendable {
    case unparseableSettings
    case helperExecutableNotFound
    case configurationVerificationFailed
}

extension InstallerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unparseableSettings:
            String(localized: "Could not parse ~/.claude/settings.json.")
        case .helperExecutableNotFound:
            String(localized: "Helper executable not found in app bundle. Reinstall Filbert and retry.")
        case .configurationVerificationFailed:
            String(localized: "Could not verify the helper installation.")
        }
    }
}

extension InstallerError: DiagnosticError {
    public var diagnosticCode: String {
        switch self {
        case .unparseableSettings: "invalid-settings"
        case .helperExecutableNotFound: "helper-executable-missing"
        case .configurationVerificationFailed: "helper-verification-failed"
        }
    }
}

enum StatusLineValue: Equatable {
    case string(String)
    case object(StatusLineObject)
}

struct StatusLineObject: Equatable {
    var command: String?
    var type: String?
    var extra: [String: AnyJSON]

    init(command: String? = nil, type: String? = nil, extra: [String: AnyJSON] = [:]) {
        self.command = command
        self.type = type
        self.extra = extra
    }
}

struct ClaudeSettings: Equatable {
    var statusLine: StatusLineValue?
    var extra: [String: AnyJSON]

    init(statusLine: StatusLineValue? = nil, extra: [String: AnyJSON] = [:]) {
        self.statusLine = statusLine
        self.extra = extra
    }
}

extension ClaudeSettings: Codable {
    private static let statusLineKey = "statusLine"

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: AnyJSON].self)
        if let value = raw[Self.statusLineKey] {
            statusLine = try Self.decodeStatusLine(value)
        } else {
            statusLine = nil
        }
        extra = raw.filter { $0.key != Self.statusLineKey }
    }

    func encode(to encoder: Encoder) throws {
        var raw = extra
        if let statusLine {
            raw[Self.statusLineKey] = Self.encodeStatusLine(statusLine)
        }
        var container = encoder.singleValueContainer()
        try container.encode(raw)
    }

    private static func decodeStatusLine(_ value: AnyJSON) throws -> StatusLineValue {
        switch value {
        case let .string(string):
            return .string(string)
        case let .object(dict):
            return .object(Self.decodeStatusLineObject(dict))
        case .null, .bool, .number, .array:
            throw DecodingError.dataCorrupted(.init(
                codingPath: [], debugDescription: "statusLine must be a string or an object"
            ))
        }
    }

    private static func decodeStatusLineObject(_ dict: [String: AnyJSON]) -> StatusLineObject {
        var object = StatusLineObject()
        var extra = dict
        if case let .string(command) = extra["command"] {
            object.command = command
            extra.removeValue(forKey: "command")
        }
        if case let .string(type) = extra["type"] {
            object.type = type
            extra.removeValue(forKey: "type")
        }
        object.extra = extra
        return object
    }

    private static func encodeStatusLine(_ value: StatusLineValue) -> AnyJSON {
        switch value {
        case let .string(string): .string(string)
        case let .object(object): .object(Self.encodeStatusLineObject(object))
        }
    }

    private static func encodeStatusLineObject(_ object: StatusLineObject) -> [String: AnyJSON] {
        var raw = object.extra
        if let command = object.command {
            raw["command"] = .string(command)
        }
        if let type = object.type {
            raw["type"] = .string(type)
        }
        return raw
    }
}

import Foundation

/// Type-erased JSON value used when a JSON shape is user-owned or externally
/// defined and may carry keys this app does not know about (e.g. Claude Code's
/// `~/.claude/settings.json` accepts arbitrary sibling keys alongside
/// `statusLine`). Holding it as `AnyJSON` — not `[String: Any]` — lets the
/// `Codable` model preserve unknown keys through a read/modify/write cycle
/// while keeping `Sources/` free of the `Any` type.
///
/// Minimal by design: `Codable` + `Equatable` only. Each addition broadens
/// the public API surface of `Core`.
public enum AnyJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    // MARK: - Decoding

    /// `decode(Bool.self)` must precede `decode(Double.self)`, and both must
    /// precede `decode(String.self)`, so the JSON kind is detected unambiguously
    /// — a JSON `true` is not a `1.0`, and a JSON `"42"` is not a number.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyJSON].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyJSON].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "AnyJSON: value is not a valid JSON kind"
            )
        }
    }

    // MARK: - Encoding

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(bool):
            try container.encode(bool)
        case let .number(number):
            try container.encode(number)
        case let .string(string):
            try container.encode(string)
        case let .array(array):
            try container.encode(array)
        case let .object(object):
            try container.encode(object)
        }
    }
}

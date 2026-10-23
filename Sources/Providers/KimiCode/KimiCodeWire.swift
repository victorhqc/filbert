import Foundation

/// The usages endpoint mixes legacy counters with a newer ratio map, and its
/// field spellings drift, so every block decodes on its own and a malformed
/// entry is dropped instead of failing the response.
struct KimiCodeUsagesResponse: Decodable {
    /// The legacy weekly window.
    let usage: KimiCodeCounter?
    let limits: [KimiCodeLimit]
    let usages: [String: KimiCodeRatio]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKey.self)
        usage = try? container.decodeIfPresent(KimiCodeCounter.self, forKey: WireKey("usage"))
        let limits = try? container.decodeIfPresent([Lenient<KimiCodeLimit>].self, forKey: WireKey("limits"))
        self.limits = limits?.compactMap(\.value) ?? []
        let usages = try? container.decodeIfPresent([String: Lenient<KimiCodeRatio>].self, forKey: WireKey("usages"))
        self.usages = usages?.compactMapValues(\.value) ?? [:]
    }
}

struct KimiCodeCounter: Decodable {
    let limit: Double
    let used: Double
    let resetDate: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKey.self)
        guard let limit = container.lenientNumber(forKey: WireKey("limit")), limit > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: WireKey("limit"),
                in: container,
                debugDescription: "Expected a positive limit."
            )
        }
        let remaining = container.lenientNumber(forKey: WireKey("remaining"))
        guard let used = container.lenientNumber(forKey: WireKey("used")) ?? remaining.map({ limit - $0 }) else {
            throw DecodingError.dataCorruptedError(
                forKey: WireKey("used"),
                in: container,
                debugDescription: "Expected used or remaining."
            )
        }
        self.limit = limit
        self.used = used
        resetDate = container.resetDate()
    }
}

struct KimiCodeLimit: Decodable {
    let window: KimiCodeWindow
    let detail: KimiCodeCounter
}

struct KimiCodeWindow: Decodable {
    let duration: TimeInterval

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKey.self)
        let unit = try container.decode(String.self, forKey: WireKey("timeUnit"))
        guard let count = container.lenientNumber(forKey: WireKey("duration")),
              let unitLength = Self.unitLengths[unit]
        else {
            throw DecodingError.dataCorruptedError(
                forKey: WireKey("timeUnit"),
                in: container,
                debugDescription: "Unknown window."
            )
        }
        duration = count * unitLength
    }

    private static let unitLengths: [String: TimeInterval] = [
        "TIME_UNIT_MINUTE": 60,
        "TIME_UNIT_HOUR": 60 * 60,
        "TIME_UNIT_DAY": 24 * 60 * 60,
        "TIME_UNIT_WEEK": 7 * 24 * 60 * 60,
    ]
}

struct KimiCodeRatio: Decodable {
    let usedRatio: Double
    let resetDate: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKey.self)
        guard let usedRatio = container.lenientNumber(forKey: WireKey("used_ratio")) else {
            throw DecodingError.dataCorruptedError(
                forKey: WireKey("used_ratio"),
                in: container,
                debugDescription: "Expected a used ratio."
            )
        }
        self.usedRatio = usedRatio
        resetDate = container.resetDate()
    }
}

private struct WireKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(_ stringValue: String) {
        self.stringValue = stringValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

private struct Lenient<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

private extension KeyedDecodingContainer where Key == WireKey {
    static var resetKeys: [WireKey] {
        ["resetTime", "resetAt", "reset_time", "reset_at"].map(WireKey.init)
    }

    /// Counts arrive as JSON numbers or as decimal strings.
    func lenientNumber(forKey key: WireKey) -> Double? {
        let number = (try? decodeIfPresent(Double.self, forKey: key))
            ?? (try? decodeIfPresent(String.self, forKey: key)).flatMap { Double($0) }
        guard let number, number.isFinite else { return nil }
        return number
    }

    func resetDate() -> Date? {
        for key in Self.resetKeys {
            guard let text = try? decodeIfPresent(String.self, forKey: key) else { continue }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(text) {
                return date
            }
        }
        return nil
    }
}

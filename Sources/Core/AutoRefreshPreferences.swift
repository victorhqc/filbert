import Foundation

public enum AutoRefreshMode: String, CaseIterable, Hashable, Sendable {
    case regular
    case smart
}

public enum AutoRefreshPreferences {
    public static let defaultSlowInterval: TimeInterval = 5 * 60
    public static let defaultFastInterval: TimeInterval = 30
    public static let slowIntervalOptions: [TimeInterval] = (1 ... 60).map { TimeInterval($0 * 60) }
    public static let fastIntervalOptions: [TimeInterval] = stride(from: 10, through: 60, by: 5).map(TimeInterval.init)

    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static func isEnabled(for providerId: String) -> Bool {
        savedEnabledValues()[providerId] ?? false
    }

    public static func setEnabled(_ enabled: Bool, for providerId: String) {
        var values = savedEnabledValues()
        values[providerId] = enabled
        defaults.set(values, forKey: enabledStorageKey)
    }

    public static var mode: AutoRefreshMode {
        get {
            guard let rawValue = defaults.string(forKey: modeStorageKey),
                  let mode = AutoRefreshMode(rawValue: rawValue)
            else {
                return .regular
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: modeStorageKey)
        }
    }

    public static var slowInterval: TimeInterval {
        get {
            interval(
                forKey: slowIntervalStorageKey,
                supportedValues: slowIntervalOptions,
                defaultValue: defaultSlowInterval
            )
        }
        set { defaults.set(supportedSlowInterval(newValue), forKey: slowIntervalStorageKey) }
    }

    public static var fastInterval: TimeInterval {
        get {
            interval(
                forKey: fastIntervalStorageKey,
                supportedValues: fastIntervalOptions,
                defaultValue: defaultFastInterval
            )
        }
        set { defaults.set(supportedFastInterval(newValue), forKey: fastIntervalStorageKey) }
    }

    public static func supportedSlowInterval(_ interval: TimeInterval) -> TimeInterval {
        supportedInterval(interval, supportedValues: slowIntervalOptions, defaultValue: defaultSlowInterval)
    }

    public static func supportedFastInterval(_ interval: TimeInterval) -> TimeInterval {
        supportedInterval(interval, supportedValues: fastIntervalOptions, defaultValue: defaultFastInterval)
    }

    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private static func savedEnabledValues() -> [String: Bool] {
        defaults.dictionary(forKey: enabledStorageKey) as? [String: Bool] ?? [:]
    }

    private static func interval(
        forKey key: String,
        supportedValues: [TimeInterval],
        defaultValue: TimeInterval
    ) -> TimeInterval {
        guard let value = defaults.object(forKey: key) as? NSNumber else {
            return defaultValue
        }
        return supportedInterval(value.doubleValue, supportedValues: supportedValues, defaultValue: defaultValue)
    }

    private static func supportedInterval(
        _ interval: TimeInterval,
        supportedValues: [TimeInterval],
        defaultValue: TimeInterval
    ) -> TimeInterval {
        supportedValues.contains(interval) ? interval : defaultValue
    }

    private static let enabledStorageKey = "automatic-refresh-enabled"
    private static let modeStorageKey = "automatic-refresh-mode"
    private static let slowIntervalStorageKey = "automatic-refresh-slow-interval"
    private static let fastIntervalStorageKey = "automatic-refresh-fast-interval"
}

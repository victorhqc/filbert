import Foundation

public enum BalanceThresholds {
    // `nonisolated(unsafe)`: production never mutates after startup; only the
    // test-injection API writes, and XCTest runs serially.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static var low: Double {
        if let raw = defaults.object(forKey: Keys.low) as? Double {
            return raw
        }
        return Defaults.low
    }

    public static var ok: Double { // swiftlint:disable:this identifier_name
        if let raw = defaults.object(forKey: Keys.okThreshold) as? Double {
            return raw
        }
        return Defaults.okThreshold
    }

    /// Negative `low` is silently ignored, not asserted — the UI stepper
    /// already bounds it, so a negative value here is unexpected.
    public static func set(low: Double, ok okValue: Double) {
        guard low >= 0 else { return }
        let clampedOk = max(okValue, low + 1)
        defaults.set(low, forKey: Keys.low)
        defaults.set(clampedOk, forKey: Keys.okThreshold)
    }

    /// Test-only escape hatch: swaps the backing store.
    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private enum Keys {
        static let low = "balance-thresholds-low"
        static let okThreshold = "balance-thresholds-ok"
    }

    private enum Defaults {
        static let low: Double = 5
        static let okThreshold: Double = 20
    }
}

import Foundation

/// Reads and writes the user-configurable low/ok balance thresholds that
/// drive the amount-tier coloring for balance-only `UsageLine`s (ui 08).
///
/// Mirrors `ProviderOverrides`: UserDefaults-backed (thresholds are not
/// secrets, so the Keychain stays reserved for API keys per AGENTS.md §3).
/// Raw keys are private so the storage shape can change without touching the
/// App layer (ui 08 AC2).
public enum BalanceThresholds {
    /// Standard `UserDefaults` the App writes to. Held as a parameter-free
    /// accessor so tests can swap it via `setUserDefaults(_:)` — identical
    /// pattern to (core 02 Plan 4).
    private static var defaults: UserDefaults = .standard

    /// Returns the saved "low" threshold, or the default when unset (ui 08 AC2).
    public static var low: Double {
        if let raw = defaults.object(forKey: Keys.low) as? Double {
            return raw
        }
        return Defaults.low
    }

    /// Returns the saved "ok" threshold, or the default when unset (ui 08 AC2).
    /// Named `ok` per spec (ui 08 Plan 1).
    public static var ok: Double { // swiftlint:disable:this identifier_name
        if let raw = defaults.object(forKey: Keys.okThreshold) as? Double {
            return raw
        }
        return Defaults.okThreshold
    }

    /// Writes both thresholds, validating `low >= 0` and clamping `ok` upward
    /// so `ok > low` always holds. Negative `low` is ignored to keep the UI
    /// simple — the stepper already bounds `low >= 0` (ui 08 AC2).
    public static func set(low: Double, ok okValue: Double) {
        guard low >= 0 else { return }
        let clampedOk = max(okValue, low + 1)
        defaults.set(low, forKey: Keys.low)
        defaults.set(clampedOk, forKey: Keys.okThreshold)
    }

    /// Test-only escape hatch: swaps the backing store. Production code never
    /// needs this (same pattern as `ProviderOverrides` core 02).
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

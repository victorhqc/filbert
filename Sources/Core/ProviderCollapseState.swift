import Foundation

/// A missing value stays `nil`; the App layer owns the positional default
/// because only it knows the current provider order.
public enum ProviderCollapseState {
    // `nonisolated(unsafe)`: production never mutates after startup; only the
    // test-injection API writes, and XCTest runs serially.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static func collapsedState(for providerId: String) -> Bool? {
        savedStates()[providerId]
    }

    public static func setCollapsed(_ collapsed: Bool, for providerId: String) {
        var states = savedStates()
        states[providerId] = collapsed
        defaults.set(states, forKey: storageKey)
    }

    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private static func savedStates() -> [String: Bool] {
        defaults.dictionary(forKey: storageKey) as? [String: Bool] ?? [:]
    }

    private static let storageKey = "provider-collapse-state"
}

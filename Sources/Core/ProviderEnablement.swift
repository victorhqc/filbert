import Foundation

/// Enablement is user preference state, not a secret, so it belongs in
/// `UserDefaults` alongside provider ordering and collapse state.
public enum ProviderEnablement {
    // `nonisolated(unsafe)`: production sets this once to `.standard` and never
    // mutates it; the only writer is the test-injection API, and XCTest runs
    // tests serially. `UserDefaults` itself is thread-safe for reads/writes.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static func isEnabled(
        for providerId: String,
        authShape: ProviderAuth.Shape,
        keychain: Keychain = .shared
    ) -> Bool {
        if let enabled = savedEnabled(for: providerId) {
            return enabled
        }

        let initialValue = switch authShape {
        case .apiKey:
            (try? keychain.load(for: providerId)) != nil
        case .apiKeyFree:
            false
        }
        setEnabled(initialValue, for: providerId)
        return initialValue
    }

    public static func savedEnabled(for providerId: String) -> Bool? {
        savedValues()[providerId]
    }

    public static func setEnabled(_ enabled: Bool, for providerId: String) {
        var values = savedValues()
        values[providerId] = enabled
        defaults.set(values, forKey: storageKey)
    }

    /// Test-only escape hatch: swaps the backing store.
    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private static func savedValues() -> [String: Bool] {
        defaults.dictionary(forKey: storageKey) as? [String: Bool] ?? [:]
    }

    private static let storageKey = "provider-enablement"
}

import Foundation

/// Order is presentation state, not a secret — `UserDefaults`, not the Keychain
/// (AGENTS.md §3).
public enum ProviderOrder {
    // `nonisolated(unsafe)`: production sets this once to `.standard` and never
    // mutates it; the only writer is the test-injection API, and XCTest runs
    // tests serially. `UserDefaults` itself is thread-safe for reads/writes.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static func effectiveOrder(for providerIds: [String]) -> [String] {
        let saved = savedOrder() ?? []
        let savedSet = Set(saved)
        let inputSet = Set(providerIds)

        let savedKnown = saved.filter { inputSet.contains($0) }
        let unsaved = providerIds.filter { !savedSet.contains($0) }

        return savedKnown + unsaved
    }

    /// Prefer `effectiveOrder(for:)` for live resolution; this raw read is used
    /// only to seed the editor. Filtering against the live registry is the
    /// caller's responsibility.
    public static func savedOrder() -> [String]? {
        defaults.array(forKey: storageKey) as? [String]
    }

    public static func setOrder(_ providerIds: [String]) {
        defaults.set(providerIds, forKey: storageKey)
    }

    /// Test-only escape hatch: swaps the backing store.
    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private static let storageKey = "provider-order"
}

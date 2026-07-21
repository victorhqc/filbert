import Foundation

/// Reads and writes the user's preferred provider ordering (ui 09).
///
/// The order lives in `UserDefaults` — it is presentation state, not a
/// secret, so the Keychain stays reserved for API keys (AGENTS.md §3). Raw
/// keys are kept private so the storage shape can change without touching the
/// App layer, mirroring the encapsulation of `ProviderOverrides` (core 02).
public enum ProviderOrder {
    /// Standard `UserDefaults` the App writes to. Held as a parameterless
    /// accessor so tests can swap it via `setUserDefaults(_:)`.
    private static var defaults: UserDefaults = .standard

    /// Returns the passed provider IDs re-sorted so saved-order IDs come first
    /// in their saved sequence, then any unsaved IDs in their original
    /// relative order (ui 09 AC4/AC5/AC6).
    ///
    /// The caller passes `[String]`, not display names, so Core stays
    /// name-agnostic; the view model resolves names from `ProviderInfo`.
    /// Saved IDs that are no longer in `providerIds` are dropped on read.
    /// `providerIds` that are not in the saved list keep their input order
    /// after the saved ones.
    public static func effectiveOrder(for providerIds: [String]) -> [String] {
        let saved = savedOrder() ?? []
        let savedSet = Set(saved)
        let inputSet = Set(providerIds)

        // Saved IDs that are still registered, in their saved sequence.
        let savedKnown = saved.filter { inputSet.contains($0) }
        // Registered IDs with no saved position, in the caller's order.
        let unsaved = providerIds.filter { !savedSet.contains($0) }

        return savedKnown + unsaved
    }

    /// Raw read of the saved order, or `nil` if none is stored (ui 09 Plan 1).
    ///
    /// Used only to seed the editor; `effectiveOrder(for:)` is the call sites
    /// should use for resolution. Filtering against the live registry is the
    /// caller's responsibility here.
    public static func savedOrder() -> [String]? {
        defaults.array(forKey: storageKey) as? [String]
    }

    /// Writes the full ordered list of provider IDs (ui 09 AC3).
    public static func setOrder(_ providerIds: [String]) {
        defaults.set(providerIds, forKey: storageKey)
    }

    /// Test-only escape hatch: swaps the backing store. Production code never
    /// needs this.
    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private static let storageKey = "provider-order"
}

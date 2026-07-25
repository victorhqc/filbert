import Foundation

/// Reads and writes per-provider base-URL overrides (core 02).
///
/// Overrides live in `UserDefaults` — they are not secrets, so the Keychain
/// stays reserved for API keys (AGENTS.md §3). Raw keys are kept private so
/// the storage shape can change without touching the App layer (core 02 AC5).
public enum ProviderOverrides {
    /// Standard `UserDefaults` the App writes to. Held as a parameter-free
    /// accessor so tests can swap it via `setUserDefaults(_:for:)`.
    ///
    /// `nonisolated(unsafe)`: production never mutates this after startup; only
    /// the test-injection API writes, and XCTest runs serially.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    /// Returns the saved override URL for a provider, or `nil` if none.
    ///
    /// Invalid entries (unparseable, empty host, or non-`https`) are treated
    /// as unset and removed — a working default is always preferable to a
    /// confusing URL error (core 02 AC6).
    public static func baseURL(for providerId: String) -> URL? {
        let raw = defaults.string(forKey: key(for: providerId))
        guard let raw,
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            if raw != nil {
                defaults.removeObject(forKey: key(for: providerId))
            }
            return nil
        }
        return url
    }

    /// Saves an override URL for a provider. Pass `nil` to clear.
    ///
    /// Only `https` URLs with a non-empty host are accepted; anything else
    /// throws (core 02 AC5).
    @discardableResult
    public static func setBaseURL(_ url: URL?, for providerId: String) throws -> URL? {
        guard let url else {
            defaults.removeObject(forKey: key(for: providerId))
            return nil
        }

        guard let scheme = url.scheme?.lowercased(),
              scheme == "https",
              let host = url.host,
              !host.isEmpty
        else {
            throw ProviderOverrideError.invalidURL
        }

        defaults.set(url.absoluteString, forKey: key(for: providerId))
        return url
    }

    /// Test-only escape hatch: swaps the backing store. Production code never
    /// needs this.
    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private static func key(for providerId: String) -> String {
        "provider-\(providerId)-base-url"
    }
}

public enum ProviderOverrideError: Error, Equatable {
    /// URL was missing a scheme, not `https`, or had no host.
    case invalidURL
}

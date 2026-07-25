import Foundation

/// Overrides are not secrets — `UserDefaults`, not the Keychain (AGENTS.md §3).
public enum ProviderOverrides {
    // `nonisolated(unsafe)`: production never mutates after startup; only the
    // test-injection API writes, and XCTest runs serially.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    /// Invalid entries (unparseable, empty host, or non-`https`) are treated
    /// as unset and removed — a working default is always preferable to a
    /// confusing URL error.
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

    /// Pass `nil` to clear.
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

    /// Test-only escape hatch: swaps the backing store.
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

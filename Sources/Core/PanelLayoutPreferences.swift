import Foundation

public enum PanelLayout: String, Sendable, CaseIterable {
    case stacked
    case tabs
}

/// The saved tab stays as chosen even when its provider is gone; the App layer
/// owns the fallback because only it knows which providers are configured.
public enum PanelLayoutPreferences {
    // `nonisolated(unsafe)`: production never mutates after startup; only the
    // test-injection API writes, and XCTest runs serially.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static var layout: PanelLayout {
        guard let rawValue = defaults.string(forKey: Keys.layout) else { return .stacked }
        return PanelLayout(rawValue: rawValue) ?? .stacked
    }

    public static func setLayout(_ layout: PanelLayout) {
        defaults.set(layout.rawValue, forKey: Keys.layout)
    }

    public static var selectedTabProviderId: String? {
        defaults.string(forKey: Keys.selectedTabProviderId)
    }

    public static func setSelectedTabProviderId(_ providerId: String) {
        defaults.set(providerId, forKey: Keys.selectedTabProviderId)
    }

    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private enum Keys {
        static let layout = "panel-layout"
        static let selectedTabProviderId = "panel-selected-tab-provider-id"
    }
}

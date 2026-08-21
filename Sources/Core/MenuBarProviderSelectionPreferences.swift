import Foundation

public enum MenuBarProviderSelectionPreferences {
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static var isAutomatic: Bool {
        get {
            defaults.object(forKey: Keys.isAutomatic) as? Bool ?? true
        }
        set {
            defaults.set(newValue, forKey: Keys.isAutomatic)
        }
    }

    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    private enum Keys {
        static let isAutomatic = "menu-bar-provider-selection-automatic"
    }
}

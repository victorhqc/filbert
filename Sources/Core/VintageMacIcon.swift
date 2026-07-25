import Foundation

public enum VintageMacIcon {
    // `nonisolated(unsafe)`: production never mutates after startup; only the
    // test-injection API writes, and XCTest runs serially.
    private nonisolated(unsafe) static var defaults: UserDefaults = .standard

    public static var isEnabled: Bool {
        defaults.object(forKey: Keys.isEnabled) as? Bool ?? false
    }

    public static func setEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Keys.isEnabled)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    public static func setUserDefaults(_ defaults: UserDefaults) {
        Self.defaults = defaults
    }

    public static let didChangeNotification = Notification.Name("VintageMacIcon.didChange")

    private enum Keys {
        static let isEnabled = "vintage-mac-icon-enabled"
    }
}

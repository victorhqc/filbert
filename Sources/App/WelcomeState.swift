import Core
import Foundation

// `@unchecked`: `UserDefaults` is documented as thread-safe but is not marked `Sendable`.
struct WelcomeState: @unchecked Sendable {
    static let completionKey = "welcome-completed"
    static let showArgument = "--show-welcome"

    private let defaults: UserDefaults
    private let arguments: [String]
    private let hasExistingInstall: @Sendable () -> Bool

    init(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        hasExistingInstall: @escaping @Sendable () -> Bool = { ProviderEnablement.hasSavedValues }
    ) {
        self.defaults = defaults
        self.arguments = arguments
        self.hasExistingInstall = hasExistingInstall
    }

    var isCompleted: Bool {
        defaults.bool(forKey: Self.completionKey)
    }

    /// Read before the registry first resolves enablement, because that resolution saves a value.
    var shouldShowOnLaunch: Bool {
        arguments.contains(Self.showArgument) || (!isCompleted && !hasExistingInstall())
    }

    func markCompleted() {
        defaults.set(true, forKey: Self.completionKey)
    }
}

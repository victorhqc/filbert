import AppKit
import Foundation
import LocalAuthentication

/// Wraps the `LAContext` used for every Keychain authorization in a session.
/// One shared instance is reused by all `SecItem*` calls so macOS can batch
/// the user's authorization decisions; a fresh context is created lazily on
/// first use and again after invalidation (core 07 AC1).
///
/// The wrapper holds no credential data. It only carries the `LAContext`
/// that batches authorization within its valid window.
public final class KeychainAuthenticationContext: @unchecked Sendable {
    /// Session-scoped singleton. The first access also starts the lifecycle
    /// observer so sleep/wake/lock invalidate the underlying `LAContext`
    /// (core 07 AC5).
    public static let shared: KeychainAuthenticationContext = {
        KeychainLifecycleObserver.shared.start()
        return KeychainAuthenticationContext()
    }()

    private let lock = NSLock()
    private var storedContext: LAContext

    public var localAuthenticationContext: LAContext {
        lock.withLock { storedContext }
    }

    public init() {
        storedContext = LAContext()
    }

    /// Tears down the current `LAContext` so the next Keychain access
    /// prompts again. Called on system sleep, wake, and session lock, where
    /// macOS closes the prior authorization window (core 07 AC5). The
    /// consolidated item's in-memory cache is unaffected; only the
    /// authorization state resets.
    func invalidate() {
        lock.withLock {
            storedContext.invalidate()
            storedContext = LAContext()
        }
    }
}

/// Wires system sleep/wake and session lock/unlock notifications to
/// `KeychainAuthenticationContext.shared.invalidate()`. Started once per
/// process on first use of the shared context (core 07 AC5).
final class KeychainLifecycleObserver: @unchecked Sendable {
    static let shared = KeychainLifecycleObserver()

    private let lock = NSLock()
    private var started = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    private init() {}

    func start() {
        lock.withLock {
            guard !started else { return }
            started = true
            installObservers()
        }
    }

    private func installObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(
                workspaceCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil
                ) { _ in
                    KeychainAuthenticationContext.shared.invalidate()
                }
            )
        }

        let distributedCenter = DistributedNotificationCenter.default()
        for name in [
            Notification.Name("com.apple.screenIsLocked"),
            Notification.Name("com.apple.screenIsUnlocked"),
        ] {
            distributedObservers.append(
                distributedCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil
                ) { _ in
                    KeychainAuthenticationContext.shared.invalidate()
                }
            )
        }
    }
}

import AppKit
import Foundation
import LocalAuthentication

/// One shared `LAContext` is reused by all `SecItem*` calls so macOS can batch
/// the user's authorization decisions; a fresh context is created lazily on
/// first use and again after invalidation. The wrapper holds no credential
/// data — it only carries the `LAContext` that batches authorization within
/// its valid window.
public final class KeychainAuthenticationContext: @unchecked Sendable {
    /// First access also starts the lifecycle observer so sleep/wake/lock
    /// invalidate the underlying `LAContext`.
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

    /// Called on system sleep, wake, and session lock, where macOS closes the
    /// prior authorization window. The consolidated item's in-memory cache is
    /// unaffected; only the authorization state resets.
    func invalidate() {
        lock.withLock {
            storedContext.invalidate()
            storedContext = LAContext()
        }
    }
}

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

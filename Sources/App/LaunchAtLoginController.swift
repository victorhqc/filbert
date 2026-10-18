import AppKit
import Core
import Observation

@MainActor
@Observable
final class LaunchAtLoginController: NSObject {
    private let client: any LaunchAtLoginManaging

    private(set) var status: LaunchAtLoginStatus
    private(set) var errorMessage: DisplayText?

    init(client: any LaunchAtLoginManaging = SystemLaunchAtLoginClient()) {
        self.client = client
        status = client.status
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    var isRegistered: Bool {
        status == .enabled || status == .requiresApproval
    }

    var isAvailable: Bool {
        status != .unavailable
    }

    func refreshStatus() {
        let currentStatus = client.status
        if status != currentStatus {
            errorMessage = nil
        }
        status = currentStatus
    }

    func setRegistered(_ registered: Bool) {
        refreshStatus()
        guard isAvailable, registered != isRegistered else { return }

        errorMessage = nil
        do {
            if registered {
                try client.register()
            } else {
                try client.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            errorMessage = DisplayText {
                registered
                    ? String(displayLocalized: "Could not enable launch at login. Try again.", bundle: .module)
                    : String(displayLocalized: "Could not disable launch at login. Try again.", bundle: .module)
            }
        }
    }

    func openLoginItemsSettings() {
        client.openLoginItemsSettings()
    }

    @objc private func applicationDidBecomeActive(_: Notification) {
        refreshStatus()
    }
}

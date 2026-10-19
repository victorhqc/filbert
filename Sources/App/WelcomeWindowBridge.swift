import AppKit
import SwiftUI

/// Sits in the menu bar label, which SwiftUI renders at launch. `AppMain.init` cannot reach the
/// delegate that `NSApplicationDelegateAdaptor` creates, so the reopen handler is connected here.
@MainActor
struct WelcomeWindowBridge: View {
    let controller: WelcomeWindowController
    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                appDelegate.onReopen = controller.handleReopen
            }
    }
}

@MainActor
enum StatusItemVisibility {
    /// AppKit keeps the status item in an `NSWindow` at the status bar level. SwiftUI also keeps an
    /// off-screen copy with no screen, so one visible window on a screen is enough.
    /// `nil` when no such window exists.
    static var current: Bool? {
        let windows = NSApp.windows.filter { $0.level == .statusBar && !($0 is NSPanel) }
        guard !windows.isEmpty else { return nil }
        return windows.contains { window in
            window.isVisible && window.screen != nil && window.occlusionState.contains(.visible)
        }
    }
}

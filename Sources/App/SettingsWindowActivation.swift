import AppKit
import SwiftUI

/// `EnvironmentValues.openSettings` reliably creates the Settings window on
/// first open but does not always raise an already-existing window under the
/// `.accessory` activation policy, so this modifier also activates Filbert and
/// explicitly raises the Settings `NSWindow`.
///
/// The window is matched by structural traits (titled, non-panel) rather than
/// localized title text, so the lookup is stable across locales.
///
/// `@MainActor`: every touch here (`NSApp`, `windows`, `styleMask`) is
/// MainActor-isolated AppKit.
@MainActor
private struct OpenAndRaiseSettingsModifier: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        Button {
            openSettings()
            raiseSettingsWindow()
        } label: {
            content
        }
    }

    /// Dispatched to the next run-loop tick because `openSettings()` does not
    /// always create the window synchronously on first open.
    private func raiseSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            SettingsWindowLookup.settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

/// `@MainActor`: `NSApp.windows` is MainActor-isolated AppKit.
@MainActor
enum SettingsWindowLookup {
    /// The menu-bar popover is an `NSPanel` without `.titled`; the Settings scene
    /// is a regular titled `NSWindow`. Filtering on those structural traits keeps
    /// the lookup locale-independent.
    static var settingsWindow: NSWindow? {
        NSApp.windows.first { window in
            window.styleMask.contains(.titled) && !(window is NSPanel)
        }
    }
}

extension View {
    func openAndRaiseSettings() -> some View {
        modifier(OpenAndRaiseSettingsModifier())
    }
}

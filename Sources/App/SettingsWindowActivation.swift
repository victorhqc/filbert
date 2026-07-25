import AppKit
import SwiftUI

/// Wraps a button label so a tap opens the Settings scene and raises its
/// window (ui 16).
///
/// SwiftUI's `EnvironmentValues.openSettings` reliably creates the Settings
/// window on first open but does not always raise an already-existing window
/// when Filbert runs under the `.accessory` activation policy — a second
/// "Settings…" tap can leave the window behind the frontmost app. This
/// modifier calls `openSettings()`, activates Filbert, and explicitly raises
/// the Settings `NSWindow` so subsequent taps always bring it forward.
///
/// The window is matched by structural traits (titled, non-panel) rather than
/// localized title text, so the lookup is stable across locales.
///
/// `@MainActor`: SwiftUI invokes `ViewModifier.body` on the main actor, and
/// every touch here (`NSApp`, `windows`, `styleMask`) is MainActor-isolated
/// AppKit (ci 04 Plan §4).
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

    /// Activates Filbert and raises the Settings window on the next main
    /// run-loop tick. The dispatch is needed because `openSettings()` does
    /// not always create the window synchronously on first open (ui 16).
    private func raiseSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            SettingsWindowLookup.settingsWindow?.makeKeyAndOrderFront(nil)
        }
    }
}

/// `@MainActor`: the lookup touches `NSApp.windows`, which is MainActor-
/// isolated AppKit (ci 04 Plan §4).
@MainActor
enum SettingsWindowLookup {
    /// The Settings scene's `NSWindow`, identified without relying on
    /// localized title text (ui 16).
    ///
    /// The menu-bar popover is hosted in an `NSPanel` without `.titled`; the
    /// Settings scene uses a regular titled `NSWindow`. Filtering on those
    /// structural traits keeps the lookup locale-independent. If SwiftUI
    /// ever exposes a stable scene identifier on macOS 14, prefer that.
    static var settingsWindow: NSWindow? {
        NSApp.windows.first { window in
            window.styleMask.contains(.titled) && !(window is NSPanel)
        }
    }
}

extension View {
    /// Wraps the view in a Button that opens the Settings scene and raises
    /// its window (ui 16).
    func openAndRaiseSettings() -> some View {
        modifier(OpenAndRaiseSettingsModifier())
    }
}

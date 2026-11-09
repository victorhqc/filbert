import AppKit
import SwiftUI

/// Calls `onBecomeKey` each time the hosting window becomes key, including
/// when the view joins a window that is already key.
struct WindowKeyObserver: NSViewRepresentable {
    let onBecomeKey: @MainActor () -> Void

    func makeNSView(context _: Context) -> WindowKeyObserverView {
        WindowKeyObserverView()
    }

    func updateNSView(_ view: WindowKeyObserverView, context _: Context) {
        view.onBecomeKey = onBecomeKey
    }
}

final class WindowKeyObserverView: NSView {
    var onBecomeKey: (@MainActor () -> Void)?
    private var token: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
        guard let window else { return }
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onBecomeKey?()
            }
        }
        if window.isKeyWindow {
            DispatchQueue.main.async { [weak self] in
                self?.onBecomeKey?()
            }
        }
    }
}

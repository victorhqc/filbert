import AppKit
import SwiftUI

/// An `NSHostingController` in a plain `NSWindow` ignores `navigationTitle`. The title is hidden
/// but still names the window for VoiceOver and Mission Control.
struct WindowTitle: NSViewRepresentable {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    func makeNSView(context _: Context) -> TitleApplyingView {
        TitleApplyingView(title: title)
    }

    func updateNSView(_ view: TitleApplyingView, context _: Context) {
        view.title = title
    }
}

final class TitleApplyingView: NSView {
    var title: String {
        didSet { window?.title = title }
    }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.title = title
    }
}

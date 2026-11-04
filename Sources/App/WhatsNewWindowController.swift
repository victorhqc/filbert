import AppKit
import Core
import Observation
import SwiftUI

@MainActor
@Observable
final class WhatsNewContent {
    fileprivate(set) var releases: [ReleaseHighlights.Release] = []
    fileprivate(set) var releaseNotesVersion: ReleaseVersion?

    var releaseNotesURL: URL? {
        releaseNotesVersion.flatMap { version in
            URL(string: "https://github.com/victorhqc/filbert/releases/tag/v\(version)")
        }
    }
}

@MainActor
@Observable
final class WhatsNewWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("filbert.whats-new")
    static let recentReleaseLimit = 3

    /// Versions announced in the popover until the user opens or dismisses them.
    private(set) var announcedReleases: [ReleaseHighlights.Release]

    @ObservationIgnored let content = WhatsNewContent()
    @ObservationIgnored private let state: WhatsNewState
    @ObservationIgnored private let highlights: ReleaseHighlights
    @ObservationIgnored private let displayLanguage: DisplayLanguageModel
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var launchObserver: NSObjectProtocol?

    /// `announcedReleases` comes from `state`, read before the registry resolves enablement.
    init(
        state: WhatsNewState,
        announcedReleases: [ReleaseHighlights.Release],
        highlights: ReleaseHighlights,
        displayLanguage: DisplayLanguageModel
    ) {
        self.state = state
        self.announcedReleases = announcedReleases
        self.highlights = highlights
        self.displayLanguage = displayLanguage
        super.init()
        guard state.opensOnLaunch else { return }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The next tick runs after AppDelegate sets the accessory activation policy.
            DispatchQueue.main.async { [weak self] in
                self?.showNewest()
            }
        }
    }

    var announcedVersion: ReleaseVersion? {
        announcedReleases.isEmpty ? nil : state.runningVersion
    }

    func showAnnouncement() {
        let releases = announcedReleases
        dismissAnnouncement()
        show(releases)
    }

    func dismissAnnouncement() {
        guard !announcedReleases.isEmpty else { return }
        state.markSeen()
        announcedReleases = []
    }

    func showRecent() {
        show(highlights.recentReleases(through: state.runningVersion, limit: Self.recentReleaseLimit))
    }

    func close() {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
    }

    private func showNewest() {
        show(highlights.recentReleases(through: nil, limit: 1))
    }

    private func show(_ releases: [ReleaseHighlights.Release]) {
        guard !releases.isEmpty else { return }
        content.releases = releases
        content.releaseNotesVersion = state.runningVersion ?? releases.first?.version
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let content = DisplayLanguageRoot(model: displayLanguage) { [unowned self] in
            WhatsNewView(content: self.content, onDone: { [weak self] in self?.close() })
        }
        let window = EscapeClosingWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: content)
        window.setContentSize(window.contentView?.fittingSize ?? .zero)
        window.contentMinSize = NSSize(width: WhatsNewView.width, height: WhatsNewView.minimumHeight)
        window.contentMaxSize = NSSize(width: WhatsNewView.width, height: .greatestFiniteMagnitude)
        window.identifier = Self.windowIdentifier
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

private final class EscapeClosingWindow: NSWindow {
    // The AppKit override signature is untyped.
    // swiftlint:disable:next no_any_type
    override func cancelOperation(_: Any?) {
        performClose(nil)
    }
}

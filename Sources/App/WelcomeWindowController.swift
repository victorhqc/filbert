import AppKit
import Core
import SwiftUI

@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
    static let windowIdentifier = NSUserInterfaceItemIdentifier("filbert.welcome")

    let flow = WelcomeFlow()

    private let state: WelcomeState
    private let viewModel: QuotaViewModel
    private let sleepPrevention: SleepPreventionController
    private let launchAtLogin: LaunchAtLoginController
    private let displayLanguage: DisplayLanguageModel
    private var window: NSWindow?
    private var occlusionObserver: NSObjectProtocol?
    private var launchObserver: NSObjectProtocol?

    /// `showsOnLaunch` comes from `state`, read before the registry resolves enablement.
    init(
        state: WelcomeState,
        showsOnLaunch: Bool,
        viewModel: QuotaViewModel,
        sleepPrevention: SleepPreventionController,
        launchAtLogin: LaunchAtLoginController,
        displayLanguage: DisplayLanguageModel
    ) {
        self.state = state
        self.viewModel = viewModel
        self.sleepPrevention = sleepPrevention
        self.launchAtLogin = launchAtLogin
        self.displayLanguage = displayLanguage
        super.init()
        guard showsOnLaunch else { return }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The next tick runs after AppDelegate sets the accessory activation policy.
            DispatchQueue.main.async { [weak self] in
                self?.show()
            }
        }
    }

    func show() {
        flow.restart()
        let window = window ?? makeWindow()
        self.window = window
        observeStatusItemOcclusion()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func handleReopen() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else if !state.isCompleted {
            show()
        }
    }

    func finish() {
        window?.close()
    }

    func updateStatusItemVisibility() {
        flow.isStatusItemVisible = StatusItemVisibility.current
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        state.markCompleted()
        window = nil
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
    }

    private func observeStatusItemOcclusion() {
        guard occlusionObserver == nil else { return }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusItemVisibility()
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let content = DisplayLanguageRoot(model: displayLanguage) { [unowned self] in
            WelcomeView(
                flow: flow,
                viewModel: viewModel,
                sleepPrevention: sleepPrevention,
                launchAtLogin: launchAtLogin,
                displayLanguage: displayLanguage,
                onStatusItemCheck: { [weak self] in self?.updateStatusItemVisibility() },
                onFinish: { [weak self] in self?.finish() }
            )
        }
        let window = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: content)
        window.setContentSize(window.contentView?.fittingSize ?? .zero)
        window.identifier = Self.windowIdentifier
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}

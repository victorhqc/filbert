import ClaudeCodeProvider
import Core
import CursorProvider
import DeepSeekProvider
import GeminiCLIProvider
import OpenAICodexProvider
import OpenCodeGoProvider
import SwiftUI
import ZAIProvider

@main
struct AppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var viewModel: QuotaViewModel
    @State private var sleepPrevention: SleepPreventionController
    @State private var launchAtLogin: LaunchAtLoginController
    @State private var displayLanguage: DisplayLanguageModel
    @State private var settingsTab = SettingsTab.general
    private let updateCoordinator: UpdateCoordinator
    private let welcomeWindow: WelcomeWindowController

    init() {
        let welcomeState = WelcomeState()
        let showsWelcome = welcomeState.shouldShowOnLaunch

        let registry = ProviderRegistry()
        registry.register(ZAIProvider())
        registry.register(ClaudeCodeProvider())
        registry.register(DeepSeekProvider())
        registry.register(OpenAICodexProvider())
        registry.register(OpenCodeGoProvider())
        registry.register(CursorProvider())
        registry.register(GeminiCLIProvider())
        let viewModel = QuotaViewModel(
            registry: registry,
            networkPath: SystemNetworkPathObserver()
        )
        let sleepPrevention = SleepPreventionController()
        let launchAtLogin = LaunchAtLoginController()
        let displayLanguage = DisplayLanguageModel()
        _viewModel = State(initialValue: viewModel)
        _sleepPrevention = State(initialValue: sleepPrevention)
        _launchAtLogin = State(initialValue: launchAtLogin)
        _displayLanguage = State(initialValue: displayLanguage)
        updateCoordinator = UpdateCoordinator()
        welcomeWindow = WelcomeWindowController(
            state: welcomeState,
            showsOnLaunch: showsWelcome,
            viewModel: viewModel,
            sleepPrevention: sleepPrevention,
            launchAtLogin: launchAtLogin,
            displayLanguage: displayLanguage
        )
    }

    var body: some Scene {
        MenuBarExtra {
            DisplayLanguageRoot(model: displayLanguage) {
                QuotaView(
                    viewModel: viewModel,
                    sleepPrevention: sleepPrevention,
                    updateCoordinator: updateCoordinator
                )
                .frame(width: 280)
            }
        } label: {
            DisplayLanguageRoot(model: displayLanguage) {
                MenuBarStatusIcon(viewModel: viewModel, sleepPrevention: sleepPrevention)
                    .background(WelcomeWindowBridge(controller: welcomeWindow, appDelegate: appDelegate))
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            DisplayLanguageRoot(model: displayLanguage) {
                SettingsView(
                    viewModel: viewModel,
                    updateCoordinator: updateCoordinator,
                    sleepPrevention: sleepPrevention,
                    launchAtLogin: launchAtLogin,
                    displayLanguage: displayLanguage,
                    welcomeWindow: welcomeWindow,
                    selectedTab: $settingsTab
                )
            }
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var onReopen: (@MainActor () -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApplication.shared.setActivationPolicy(.accessory)

        // The app runs as a SwiftPM executable without a full `.app` bundle, so
        // the icon is set programmatically from the bundled `.icns`.
        let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        let icon = iconURL.flatMap(NSImage.init(contentsOf:))
        if let icon {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    /// Brings back an unfinished Welcome window. After that, a reopen shows nothing, as before.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        MainActor.assumeIsolated {
            onReopen?()
        }
        return false
    }
}

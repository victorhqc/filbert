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
    @State private var sleepPrevention = SleepPreventionController()
    @State private var launchAtLogin = LaunchAtLoginController()
    @State private var displayLanguage = DisplayLanguageModel()
    @State private var settingsTab = SettingsTab.general
    private let updateCoordinator: UpdateCoordinator

    init() {
        let registry = ProviderRegistry()
        registry.register(ZAIProvider())
        registry.register(ClaudeCodeProvider())
        registry.register(DeepSeekProvider())
        registry.register(OpenAICodexProvider())
        registry.register(OpenCodeGoProvider())
        registry.register(CursorProvider())
        registry.register(GeminiCLIProvider())
        _viewModel = State(initialValue: QuotaViewModel(
            registry: registry,
            networkPath: SystemNetworkPathObserver()
        ))
        updateCoordinator = UpdateCoordinator()
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
                    selectedTab: $settingsTab
                )
            }
        }
        .defaultSize(width: 620, height: 520)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
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
}

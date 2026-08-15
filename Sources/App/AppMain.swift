import ClaudeCodeProvider
import Core
import CursorProvider
import DeepSeekProvider
import OpenAICodexProvider
import OpenCodeGoProvider
import SwiftUI
import ZAIProvider

@main
struct AppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var viewModel: QuotaViewModel

    init() {
        let registry = ProviderRegistry()
        registry.register(ZAIProvider())
        registry.register(ClaudeCodeProvider())
        registry.register(DeepSeekProvider())
        registry.register(OpenAICodexProvider())
        registry.register(OpenCodeGoProvider())
        registry.register(CursorProvider())
        _viewModel = State(initialValue: QuotaViewModel(registry: registry))
    }

    var body: some Scene {
        MenuBarExtra {
            QuotaView(viewModel: viewModel)
                .frame(width: 280)
        } label: {
            MenuBarStatusIcon(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
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

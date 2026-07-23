import ClaudeCodeProvider
import Core
import CursorProvider
import DeepSeekProvider
import OpenAICodexProvider
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
        registry.register(CursorProvider())
        do {
            try LegacyBrandMigration.migratePreferences(
                providerIds: registry.registeredProviders.map(\.id)
            )
        } catch {
            FileHandle.standardError.write(
                Data("[Filbert] Preference migration failed: \(error.localizedDescription)\n".utf8)
            )
        }
        _viewModel = State(initialValue: QuotaViewModel(registry: registry))
    }

    var body: some Scene {
        // AC1: Menu Bar popover (ui 02). The visible menu-bar content is the
        // `label:` view — a live status ring (ui 10). The `MenuBarStatusIcon`
        // carries its own accessibility label: a per-state sentence for
        // window/balance modes (ui 10 AC9), and "Filbert" for the fallback,
        // preserving the original menu-bar announcement.
        MenuBarExtra {
            QuotaView(viewModel: viewModel)
                .frame(width: 280)
        } label: {
            MenuBarStatusIcon(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)

        // AC1: Standalone Settings scene (ui 02)
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
        // set the application icon programmatically from the bundled `.icns`.
        // This is what Notification Center widgets and any window chrome pick up.
        let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        let icon = iconURL.flatMap(NSImage.init(contentsOf:))
        if let icon {
            NSApplication.shared.applicationIconImage = icon
        }
    }
}

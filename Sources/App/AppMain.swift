import ClaudeCodeProvider
import Core
import DeepSeekProvider
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
        _viewModel = State(initialValue: QuotaViewModel(registry: registry))
    }

    var body: some Scene {
        // AC1: Menu Bar popover (ui 02)
        MenuBarExtra(String(localized: "AI Usage"), systemImage: "brain.head.profile") {
            QuotaView(viewModel: viewModel)
                .frame(width: 280)
        }
        .menuBarExtraStyle(.window)

        // AC1: Standalone Settings scene (ui 02)
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

import Core
import SwiftUI
import ZAIProvider

@main
struct AppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var viewModel: QuotaViewModel

    init() {
        let registry = ProviderRegistry()
        registry.register(ZAIProvider())
        _viewModel = State(initialValue: QuotaViewModel(registry: registry))
    }

    var body: some Scene {
        MenuBarExtra(String(localized: "AI Usage"), systemImage: "brain.head.profile") {
            VStack(alignment: .leading, spacing: 8) {
                // AC3: unconfigured prompt (ui 01)
                if !viewModel.isConfigured {
                    SettingsView(viewModel: viewModel)
                } else {
                    // AC4/AC6: quota display with loading/error states (ui 01)
                    QuotaView(viewModel: viewModel)
                }

                Divider()
                Button(String(localized: "Quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding()
            .frame(width: 280)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = notification
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}

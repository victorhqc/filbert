import AppKit
import Core
import SwiftUI

@MainActor
struct SettingsView: View {
    let viewModel: QuotaViewModel
    let updateCoordinator: UpdateCoordinator
    let sleepPrevention: SleepPreventionController
    let launchAtLogin: LaunchAtLoginController
    let displayLanguage: DisplayLanguageModel
    let welcomeWindow: WelcomeWindowController
    let whatsNewWindow: WhatsNewWindowController
    let navigation: SettingsNavigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.selectedTab) {
            GeneralSettingsView(
                viewModel: viewModel,
                sleepPrevention: sleepPrevention,
                launchAtLogin: launchAtLogin,
                displayLanguage: displayLanguage
            )
            .tabItem {
                Label(String(displayLocalized: "General", bundle: .module), systemImage: "gearshape")
            }
            .tag(SettingsTab.general)

            ProvidersSettingsTab(viewModel: viewModel, navigation: navigation)
                .tabItem {
                    Label(String(displayLocalized: "Providers", bundle: .module), systemImage: "key.fill")
                }
                .tag(SettingsTab.providers)

            AppearanceTab(viewModel: viewModel)
                .tabItem {
                    Label(String(displayLocalized: "Appearance", bundle: .module), systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)

            AboutSettingsView(
                updateCoordinator: updateCoordinator,
                whatsNewWindow: whatsNewWindow,
                welcomeWindow: welcomeWindow
            )
            .tabItem {
                Label(String(displayLocalized: "About", bundle: .module), systemImage: "info.circle")
            }
            .tag(SettingsTab.about)
        }
        .frame(
            minWidth: SettingsWindowConfigurator.minimumSize.width,
            idealWidth: 720,
            maxWidth: .infinity,
            minHeight: SettingsWindowConfigurator.minimumSize.height,
            idealHeight: 560,
            maxHeight: .infinity
        )
        .environment(navigation)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

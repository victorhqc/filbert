import AppKit
import Core
import SwiftUI

enum SettingsTab: Hashable {
    case general
    case providers
    case appearance
    case refresh
    case about
}

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
                launchAtLogin: launchAtLogin,
                displayLanguage: displayLanguage,
                welcomeWindow: welcomeWindow
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

            AppearanceTab(viewModel: viewModel, sleepPrevention: sleepPrevention)
                .tabItem {
                    Label(String(displayLocalized: "Appearance", bundle: .module), systemImage: "list.bullet.indent")
                }
                .tag(SettingsTab.appearance)

            RefreshSettingsView(viewModel: viewModel)
                .tabItem {
                    Label(String(displayLocalized: "Usage Checks", bundle: .module), systemImage: "arrow.clockwise")
                }
                .tag(SettingsTab.refresh)

            AboutSettingsView(updateCoordinator: updateCoordinator, whatsNewWindow: whatsNewWindow)
                .tabItem {
                    Label(String(displayLocalized: "About", bundle: .module), systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: .infinity,
            minHeight: 420,
            idealHeight: 520,
            maxHeight: .infinity
        )
        .environment(navigation)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

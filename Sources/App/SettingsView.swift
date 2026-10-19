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
    /// Lives above the language rebuild, so a language change keeps the open tab.
    @Binding var selectedTab: SettingsTab

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(
                launchAtLogin: launchAtLogin,
                displayLanguage: displayLanguage,
                welcomeWindow: welcomeWindow
            )
            .tabItem {
                Label(String(displayLocalized: "General", bundle: .module), systemImage: "gearshape")
            }
            .tag(SettingsTab.general)

            providersTab
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
                    Label(String(displayLocalized: "Refresh Settings", bundle: .module), systemImage: "arrow.clockwise")
                }
                .tag(SettingsTab.refresh)

            AboutSettingsView(updateCoordinator: updateCoordinator)
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
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var providersTab: some View {
        SettingsScrollColumn {
            ForEach(viewModel.registeredProvidersOrdered) { provider in
                ProviderSetupCard(viewModel: viewModel, provider: provider)
            }
        }
        .navigationTitle(String(displayLocalized: "Providers", bundle: .module))
    }
}

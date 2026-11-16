import AppKit
import Core
import SwiftUI

enum AboutMascot {
    static func load() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "Mascot", withExtension: "png") else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

struct AboutSettingsView: View {
    let updateCoordinator: UpdateCoordinator
    let whatsNewWindow: WhatsNewWindowController
    let welcomeWindow: WelcomeWindowController

    var body: some View {
        SettingsForm {
            Section {
                identity
            }
            updatesSection
            projectSection
        }
        .navigationTitle(String(displayLocalized: "About", bundle: .module))
    }

    private var identity: some View {
        HStack(alignment: .center, spacing: 16) {
            if let mascot = AboutMascot.load() {
                Image(nsImage: mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(String(displayLocalized: "Filbert", bundle: .module))
                    .font(.title2.weight(.semibold))
                Text(String(displayLocalized: "Filbert is a native macOS AI usage tracker.", bundle: .module))
                    .foregroundStyle(.secondary)
                Text(AppVersion.currentPresentation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 4)
    }

    private var updatesSection: some View {
        Section {
            Toggle(
                String(displayLocalized: "Check for updates automatically", bundle: .module),
                isOn: Binding(
                    get: { updateCoordinator.automaticallyChecksForUpdates },
                    set: { updateCoordinator.setAutomaticChecksForUpdates($0) }
                )
            )
            .disabled(!updateCoordinator.isAvailable)

            LabeledContent(String(displayLocalized: "Check now", bundle: .module)) {
                Button(String(displayLocalized: "Check for Updates…", bundle: .module)) {
                    updateCoordinator.checkForUpdates()
                }
                .disabled(!updateCoordinator.canCheckForUpdates)
                .accessibilityHint(String(displayLocalized: "Check for a newer Filbert release", bundle: .module))
            }

            LabeledContent(String(displayLocalized: "What's New", bundle: .module)) {
                Button(String(displayLocalized: "Show…", bundle: .module)) {
                    whatsNewWindow.showRecent()
                }
                .accessibilityLabel(String(displayLocalized: "What's New", bundle: .module))
                .accessibilityHint(String(
                    displayLocalized: "Show the new features and fixes in recent versions",
                    bundle: .module
                ))
            }

            LabeledContent(String(displayLocalized: "Welcome window", bundle: .module)) {
                Button(String(displayLocalized: "Show…", bundle: .module)) {
                    welcomeWindow.show()
                }
                .accessibilityLabel(String(displayLocalized: "Show Welcome Window", bundle: .module))
                .accessibilityHint(String(displayLocalized: "See the introduction to Filbert again.", bundle: .module))
            }
        } header: {
            Text(String(displayLocalized: "Updates", bundle: .module))
        } footer: {
            if !updateCoordinator.isAvailable {
                SettingsCaption(String(
                    displayLocalized: "Automatic updates are available only in installed releases.",
                    bundle: .module
                ))
            }
        }
    }

    private var projectSection: some View {
        Section {
            LabeledContent(String(displayLocalized: "Source code", bundle: .module)) {
                Link(
                    String(displayLocalized: "View on GitHub", bundle: .module),
                    destination: AboutAcknowledgements.projectURL
                )
                .accessibilityLabel(String(displayLocalized: "Open Filbert on GitHub", bundle: .module))
                .accessibilityHint(AboutAcknowledgements.projectURL.absoluteString)
            }

            LabeledContent(String(displayLocalized: "License", bundle: .module)) {
                Link(
                    String(displayLocalized: "View the MIT License", bundle: .module),
                    destination: AboutAcknowledgements.licenseURL
                )
                .accessibilityLabel(String(displayLocalized: "Open the MIT License on GitHub", bundle: .module))
                .accessibilityHint(AboutAcknowledgements.licenseURL.absoluteString)
            }

            DisclosureGroup(String(displayLocalized: "Acknowledgements", bundle: .module)) {
                acknowledgements
            }
        } header: {
            Text(String(displayLocalized: "Project", bundle: .module))
        } footer: {
            SettingsCaption(String(displayLocalized: "Filbert is open source under the MIT License.", bundle: .module))
        }
    }

    private var acknowledgements: some View {
        VStack(alignment: .leading, spacing: 10) {
            runtimeLibraries

            Text(String(
                displayLocalized: "Claude, DeepSeek, and OpenCode provider glyphs are derived from Simple Icons.",
                bundle: .module
            ))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            ForEach(AboutAcknowledgements.assetCredits, id: \.name) { credit in
                Link(credit.name, destination: credit.url)
                    .accessibilityLabel(String(displayLocalized: "Open Simple Icons on GitHub", bundle: .module))
                    .accessibilityHint(credit.url.absoluteString)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var runtimeLibraries: some View {
        ForEach(AboutAcknowledgements.runtimeLibraries, id: \.name) { library in
            HStack(spacing: 4) {
                Link(library.name, destination: library.url)
                Text(verbatim: "—")
                    .foregroundStyle(.secondary)
                Link(String(displayLocalized: "MIT License", bundle: .module), destination: library.licenseURL)
            }
        }
    }
}

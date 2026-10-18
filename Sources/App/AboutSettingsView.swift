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

    var body: some View {
        SettingsScrollColumn {
            identityCard
            projectCard
            updatesCard
            openSourceCard
        }
        .navigationTitle(String(displayLocalized: "About", bundle: .module))
    }

    private var identityCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 16) {
                if let mascot = AboutMascot.load() {
                    Image(nsImage: mascot)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
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
                }
            }
        }
    }

    private var projectCard: some View {
        SettingsCard(heading: String(displayLocalized: "Project", bundle: .module)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(displayLocalized: "Filbert is open source under the MIT License.", bundle: .module))
                    .foregroundStyle(.secondary)

                Link(
                    String(displayLocalized: "View on GitHub", bundle: .module),
                    destination: AboutAcknowledgements.projectURL
                )
                .accessibilityLabel(String(displayLocalized: "Open Filbert on GitHub", bundle: .module))
                .accessibilityHint(AboutAcknowledgements.projectURL.absoluteString)

                Link(
                    String(displayLocalized: "View the MIT License", bundle: .module),
                    destination: AboutAcknowledgements.licenseURL
                )
                .accessibilityLabel(String(displayLocalized: "Open the MIT License on GitHub", bundle: .module))
                .accessibilityHint(AboutAcknowledgements.licenseURL.absoluteString)
            }
        }
    }

    private var updatesCard: some View {
        SettingsCard(heading: String(displayLocalized: "Updates", bundle: .module)) {
            VStack(alignment: .leading, spacing: 10) {
                Button(String(displayLocalized: "Check for Updates…", bundle: .module)) {
                    updateCoordinator.checkForUpdates()
                }
                .disabled(!updateCoordinator.canCheckForUpdates)
                .accessibilityHint(String(displayLocalized: "Check for a newer Filbert release", bundle: .module))

                Toggle(
                    String(displayLocalized: "Check for updates automatically", bundle: .module),
                    isOn: Binding(
                        get: { updateCoordinator.automaticallyChecksForUpdates },
                        set: { updateCoordinator.setAutomaticChecksForUpdates($0) }
                    )
                )
                .disabled(!updateCoordinator.isAvailable)

                Toggle(
                    String(displayLocalized: "Download updates automatically", bundle: .module),
                    isOn: Binding(
                        get: { updateCoordinator.automaticallyDownloadsUpdates },
                        set: { updateCoordinator.setAutomaticDownloadsUpdates($0) }
                    )
                )
                .disabled(!updateCoordinator.allowsAutomaticUpdates)

                if !updateCoordinator.isAvailable {
                    Text(String(
                        displayLocalized: "Automatic updates are available only in installed releases.",
                        bundle: .module
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var openSourceCard: some View {
        SettingsCard(heading: String(displayLocalized: "Open Source", bundle: .module)) {
            VStack(alignment: .leading, spacing: 10) {
                runtimeLibraries

                Text(String(
                    displayLocalized: "Claude, DeepSeek, and OpenCode provider glyphs are derived from Simple Icons.",
                    bundle: .module
                ))
                .foregroundStyle(.secondary)

                ForEach(AboutAcknowledgements.assetCredits, id: \.name) { credit in
                    Link(credit.name, destination: credit.url)
                        .accessibilityLabel(String(displayLocalized: "Open Simple Icons on GitHub", bundle: .module))
                        .accessibilityHint(credit.url.absoluteString)
                }
            }
        }
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

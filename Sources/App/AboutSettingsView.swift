import AppKit
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
        .navigationTitle(String(localized: "About"))
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
                    Text(String(localized: "Filbert"))
                        .font(.title2.weight(.semibold))
                    Text(String(localized: "Filbert is a native macOS AI usage tracker."))
                        .foregroundStyle(.secondary)
                    Text(AppVersion.currentPresentation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var projectCard: some View {
        SettingsCard(heading: String(localized: "Project")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Filbert is open source under the MIT License."))
                    .foregroundStyle(.secondary)

                Link(String(localized: "View on GitHub"), destination: AboutAcknowledgements.projectURL)
                    .accessibilityLabel(String(localized: "Open Filbert on GitHub"))
                    .accessibilityHint(AboutAcknowledgements.projectURL.absoluteString)

                Link(String(localized: "View the MIT License"), destination: AboutAcknowledgements.licenseURL)
                    .accessibilityLabel(String(localized: "Open the MIT License on GitHub"))
                    .accessibilityHint(AboutAcknowledgements.licenseURL.absoluteString)
            }
        }
    }

    private var updatesCard: some View {
        SettingsCard(heading: String(localized: "Updates")) {
            VStack(alignment: .leading, spacing: 10) {
                Button(String(localized: "Check for Updates…")) {
                    updateCoordinator.checkForUpdates()
                }
                .disabled(!updateCoordinator.canCheckForUpdates)
                .accessibilityHint(String(localized: "Check for a newer Filbert release"))

                Toggle(
                    String(localized: "Check for updates automatically"),
                    isOn: Binding(
                        get: { updateCoordinator.automaticallyChecksForUpdates },
                        set: { updateCoordinator.setAutomaticChecksForUpdates($0) }
                    )
                )
                .disabled(!updateCoordinator.isAvailable)

                Toggle(
                    String(localized: "Download updates automatically"),
                    isOn: Binding(
                        get: { updateCoordinator.automaticallyDownloadsUpdates },
                        set: { updateCoordinator.setAutomaticDownloadsUpdates($0) }
                    )
                )
                .disabled(!updateCoordinator.allowsAutomaticUpdates)

                if !updateCoordinator.isAvailable {
                    Text(String(localized: "Automatic updates are available only in installed releases."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var openSourceCard: some View {
        SettingsCard(heading: String(localized: "Open Source")) {
            VStack(alignment: .leading, spacing: 10) {
                runtimeLibraries

                Text(String(localized: "Claude, DeepSeek, and OpenCode provider glyphs are derived from Simple Icons."))
                    .foregroundStyle(.secondary)

                ForEach(AboutAcknowledgements.assetCredits, id: \.name) { credit in
                    Link(credit.name, destination: credit.url)
                        .accessibilityLabel(String(localized: "Open Simple Icons on GitHub"))
                        .accessibilityHint(credit.url.absoluteString)
                }
            }
        }
    }

    private var runtimeLibraries: some View {
        ForEach(AboutAcknowledgements.runtimeLibraries, id: \.name) { library in
            HStack(spacing: 4) {
                Link(library.name, destination: library.url)
                Text("—")
                    .foregroundStyle(.secondary)
                Link(String(localized: "MIT License"), destination: library.licenseURL)
            }
        }
    }
}

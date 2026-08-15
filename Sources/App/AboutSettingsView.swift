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
    var body: some View {
        SettingsScrollColumn {
            identityCard
            projectCard
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

    private var openSourceCard: some View {
        SettingsCard(heading: String(localized: "Open Source")) {
            VStack(alignment: .leading, spacing: 10) {
                runtimeLibraries

                Text(String(localized: "Claude and DeepSeek provider glyphs are derived from Simple Icons."))
                    .foregroundStyle(.secondary)

                ForEach(AboutAcknowledgements.assetCredits, id: \.name) { credit in
                    Link(credit.name, destination: credit.url)
                        .accessibilityLabel(String(localized: "Open Simple Icons on GitHub"))
                        .accessibilityHint(credit.url.absoluteString)
                }
            }
        }
    }

    @ViewBuilder
    private var runtimeLibraries: some View {
        if AboutAcknowledgements.runtimeLibraries.isEmpty {
            Text(
                String(
                    localized:
                    "Filbert has no third-party runtime library dependencies and is built with Apple system frameworks."
                )
            )
            .foregroundStyle(.secondary)
        } else {
            ForEach(AboutAcknowledgements.runtimeLibraries, id: \.name) { library in
                Link(library.name, destination: library.url)
            }
        }
    }
}

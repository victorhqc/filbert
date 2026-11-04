import AppKit
import Core
import SwiftUI

@MainActor
struct WhatsNewView: View {
    static let width: CGFloat = 420
    static let minimumHeight: CGFloat = 320
    private static let idealHeight: CGFloat = 440

    let content: WhatsNewContent
    let onDone: () -> Void

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 16)
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(content.releases) { release in
                        releaseSection(release)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: Self.width)
        .frame(minHeight: Self.minimumHeight, idealHeight: Self.idealHeight, maxHeight: .infinity)
        .background(WindowTitle(title))
    }

    private var title: String {
        String(displayLocalized: "What's New in Filbert", bundle: .module)
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let mascot = AboutMascot.load() {
                Image(nsImage: mascot)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
    }

    private func releaseSection(_ release: ReleaseHighlights.Release) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String.localizedStringWithFormat(
                String(displayLocalized: "Version %@", bundle: .module),
                release.version.description
            ))
            .font(.headline)
            .accessibilityAddTraits(.isHeader)

            itemGroup(
                heading: String(displayLocalized: "New Features", bundle: .module),
                systemImage: "sparkles",
                items: release.features
            )
            itemGroup(
                heading: String(displayLocalized: "Bug Fixes", bundle: .module),
                systemImage: "wrench.and.screwdriver",
                items: release.fixes
            )
        }
    }

    @ViewBuilder
    private func itemGroup(heading: String, systemImage: String, items: [ReleaseHighlight]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: systemImage)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(item.text(for: locale))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let url = content.releaseNotesURL {
                Link(String(displayLocalized: "Full release notes", bundle: .module), destination: url)
                    .accessibilityHint(url.absoluteString)
            }

            Spacer(minLength: 8)

            Button(String(displayLocalized: "Done", bundle: .module), action: onDone)
                .keyboardShortcut(.defaultAction)
        }
    }
}

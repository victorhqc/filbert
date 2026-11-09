import Core
import SwiftUI

@MainActor
struct ActivityDetectionNotice: View {
    let model: ActivityDetectionModel
    let providerId: String
    let providerName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                String(displayLocalized: "Finish setting up activity detection", bundle: .module),
                systemImage: "bolt.badge.clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(String.localizedStringWithFormat(
                String(displayLocalized: "Finish setting up activity detection for %@", bundle: .module),
                providerName
            ))

            HStack(spacing: 12) {
                Text(String(displayLocalized: "Set Up…", bundle: .module))
                    .openAndRaiseSettings(at: SettingsDestination(tab: .providers, providerId: providerId))
                    .accessibilityLabel(String.localizedStringWithFormat(
                        String(displayLocalized: "Set up activity detection for %@", bundle: .module),
                        providerName
                    ))

                Button(String(displayLocalized: "Not Now", bundle: .module)) {
                    model.dismissNotice(for: providerId)
                }
                .accessibilityLabel(String.localizedStringWithFormat(
                    String(displayLocalized: "Hide the activity detection notice for %@", bundle: .module),
                    providerName
                ))
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.top, 2)
    }
}

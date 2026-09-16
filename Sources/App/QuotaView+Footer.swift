import AppKit
import SwiftUI

extension QuotaView {
    var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                HStack {
                    Text(String(localized: "Settings…"))
                        .font(.caption)
                        .layoutPriority(1)
                        .openAndRaiseSettings()

                    Spacer()

                    Button(String(localized: "Quit")) {
                        NSApplication.shared.terminate(nil)
                    }
                    .font(.caption)
                    .keyboardShortcut("q")
                    .layoutPriority(1)
                }

                Text(AppVersion.currentPresentation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }

            if let update = updateCoordinator.popoverUpdate {
                updateAvailabilityRow(update)
            }
        }
    }

    private func updateAvailabilityRow(_ update: PopoverUpdate) -> some View {
        HStack(spacing: 8) {
            Text(
                String.localizedStringWithFormat(
                    String(localized: "Filbert %@ is available"),
                    update.availableVersion
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .layoutPriority(1)

            Spacer(minLength: 0)

            Button(String(localized: "Update")) {
                updateCoordinator.checkForUpdates()
            }
            .controlSize(.small)
            .disabled(!update.canStartUpdate)
            .accessibilityLabel(
                String.localizedStringWithFormat(
                    String(localized: "Update Filbert to version %@"),
                    update.availableVersion
                )
            )
        }
    }
}

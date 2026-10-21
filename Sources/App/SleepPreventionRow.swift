import Core
import SwiftUI

@MainActor
struct SleepPreventionRow: View {
    let controller: SleepPreventionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(String(displayLocalized: "Keep Mac Awake", bundle: .module))
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Menu {
                    ForEach(SleepPreventionDuration.allCases) { duration in
                        Button(duration.title) {
                            controller.start(duration)
                        }
                    }

                    if controller.isActive {
                        Divider()

                        Button(String(displayLocalized: "Turn Off", bundle: .module)) {
                            controller.stop()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(controller.durationMenuTitle)
                            .monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(String(displayLocalized: "Keep Mac Awake duration", bundle: .module))
                .accessibilityValue(controller.accessibilityValue)
                .accessibilityHint(String(
                    displayLocalized: "Choose how long Filbert keeps your Mac awake",
                    bundle: .module
                ))
                .fixedSize(horizontal: true, vertical: false)
            }

            if controller.didFailToActivate {
                Text(String(displayLocalized: "Keep Mac Awake couldn't start. Try again.", bundle: .module))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension SleepPreventionDuration {
    var title: String {
        switch self {
        case .fiveMinutes:
            String(displayLocalized: "5 minutes", bundle: .module)
        case .tenMinutes:
            String(displayLocalized: "10 minutes", bundle: .module)
        case .twentyMinutes:
            String(displayLocalized: "20 minutes", bundle: .module)
        case .thirtyMinutes:
            String(displayLocalized: "30 minutes", bundle: .module)
        case .oneHour:
            String(displayLocalized: "1 hour", bundle: .module)
        case .twoHours:
            String(displayLocalized: "2 hours", bundle: .module)
        case .untilTurnedOff:
            String(displayLocalized: "Until turned off", bundle: .module)
        }
    }
}

import SwiftUI

@MainActor
struct SleepPreventionRow: View {
    let controller: SleepPreventionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(String(localized: "Prevent Mac from sleeping"))
                    .font(.callout)
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

                        Button(String(localized: "Turn Off")) {
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
                .accessibilityLabel(String(localized: "Sleep prevention duration"))
                .accessibilityValue(controller.accessibilityValue)
                .accessibilityHint(String(localized: "Choose how long Filbert keeps your Mac awake"))
                .fixedSize(horizontal: true, vertical: false)
            }

            if controller.didFailToActivate {
                Text(String(localized: "Sleep prevention couldn't start. Try again."))
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
            String(localized: "5 minutes")
        case .tenMinutes:
            String(localized: "10 minutes")
        case .twentyMinutes:
            String(localized: "20 minutes")
        case .thirtyMinutes:
            String(localized: "30 minutes")
        case .oneHour:
            String(localized: "1 hour")
        case .twoHours:
            String(localized: "2 hours")
        case .untilTurnedOff:
            String(localized: "Until turned off")
        }
    }
}

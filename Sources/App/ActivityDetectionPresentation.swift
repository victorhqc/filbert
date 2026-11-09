import Core

struct ActivityDetectionPresentation {
    enum Action: Equatable {
        case install
        case remove
    }

    let summary: String
    let detail: String?
    let symbol: String
    let action: Action?

    init(status: ActivitySignalStatus, providerName: String) {
        switch status {
        case let .notInstalled(reason):
            summary = String(displayLocalized: "Off", bundle: .module)
            detail = reason?.resolved
            symbol = "circle"
            action = .install
        case let .awaitingFirstSignal(nextStep):
            summary = String.localizedStringWithFormat(
                String(displayLocalized: "Installed. Finish setup in %@", bundle: .module),
                providerName
            )
            detail = nextStep?.resolved
            symbol = "hourglass"
            action = .remove
        case .active:
            summary = String(displayLocalized: "On", bundle: .module)
            detail = nil
            symbol = "checkmark.circle.fill"
            action = .remove
        case let .unavailable(reason):
            summary = reason.resolved
            detail = nil
            symbol = "exclamationmark.circle"
            action = nil
        }
    }
}

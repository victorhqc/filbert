import Observation

enum WelcomeStep: Int, CaseIterable {
    case introduction
    case provider
    case menuBar

    var number: Int {
        rawValue + 1
    }
}

/// Lives above `DisplayLanguageRoot`, so a language change keeps the step.
@MainActor
@Observable
final class WelcomeFlow {
    private(set) var step = WelcomeStep.introduction
    var selectedProviderId: String?
    /// `nil` when Filbert cannot read the status item's window.
    var isStatusItemVisible: Bool?

    var isFirstStep: Bool {
        step == WelcomeStep.allCases.first
    }

    var isLastStep: Bool {
        step == WelcomeStep.allCases.last
    }

    func goForward() {
        step = WelcomeStep(rawValue: step.rawValue + 1) ?? step
    }

    func goBack() {
        step = WelcomeStep(rawValue: step.rawValue - 1) ?? step
    }

    func restart() {
        step = .introduction
        selectedProviderId = nil
    }
}

import Foundation
import Observation
import Sparkle

enum UpdateConfiguration {
    static let feedURLKey = "SUFeedURL"
    static let publicEDKey = "SUPublicEDKey"
    static let automaticChecksKey = "SUEnableAutomaticChecks"
    static let allowsAutomaticUpdatesKey = "SUAllowsAutomaticUpdates"
    static let checkIntervalKey = "SUScheduledCheckInterval"
    static let feedURL = "https://victorhqc.github.io/filbert/appcast.xml"
    static let defaultCheckInterval: TimeInterval = 4 * 60 * 60
}

enum UpdateEligibility {
    static func isEligible(bundle: Bundle) -> Bool {
        guard bundle.bundleURL.pathExtension == "app",
              let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let bundleVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let normalizedShortVersion = AppVersion.normalizedReleaseVersion(shortVersion),
              AppVersion.normalizedReleaseVersion(bundleVersion) == normalizedShortVersion,
              let feedURL = bundle.object(forInfoDictionaryKey: UpdateConfiguration.feedURLKey) as? String,
              feedURL == UpdateConfiguration.feedURL,
              isHTTPSURL(feedURL),
              let publicEDKey = bundle.object(forInfoDictionaryKey: UpdateConfiguration.publicEDKey) as? String,
              isEdDSAPublicKey(publicEDKey)
        else {
            return false
        }

        return true
    }

    static func isReleaseVersion(_ rawVersion: String) -> Bool {
        AppVersion.normalizedReleaseVersion(rawVersion) != nil
    }

    private static func isHTTPSURL(_ rawURL: String) -> Bool {
        guard let url = URL(string: rawURL) else {
            return false
        }
        return url.scheme?.lowercased() == "https" && url.host != nil
    }

    private static func isEdDSAPublicKey(_ key: String) -> Bool {
        guard key.range(of: #"^[A-Za-z0-9+/]{43}=$"#, options: .regularExpression) != nil else {
            return false
        }
        return Data(base64Encoded: key)?.count == 32
    }
}

/// Sparkle resumes a staged update on every later check without reading the feed,
/// so a scheduled check must never download one. It becomes an information-only check.
enum ScheduledCheckGate {
    static let refusal = NSError(
        domain: "com.victorhqc.filbert.ScheduledCheckGate",
        code: 1,
        userInfo: [
            NSLocalizedDescriptionKey: "Filbert runs an information-only check in place of this scheduled check.",
        ]
    )

    static func allows(_ updateCheck: SPUUpdateCheck) -> Bool {
        updateCheck != .updatesInBackground
    }

    static func isRefusal(_ error: (any Error)?) -> Bool {
        guard let error = error as NSError? else {
            return false
        }
        return error.domain == refusal.domain && error.code == refusal.code
    }

    static func startsInformationCheck(after updateCheck: SPUUpdateCheck, error: (any Error)?) -> Bool {
        updateCheck == .updatesInBackground && isRefusal(error)
    }
}

enum UpdateCheckResult: Equatable {
    case updateAvailable(version: String)
    case noUpdate
    case failed
}

enum UpdateProgress: Equatable {
    case downloadStarted
    case preparationStarted
    case interrupted
}

enum UpdatePhase: Equatable {
    case available(version: String)
    case downloading(version: String)
    case preparing(version: String)

    var version: String {
        switch self {
        case let .available(version),
             let .downloading(version),
             let .preparing(version):
            version
        }
    }
}

struct PopoverUpdate: Equatable {
    enum Action: Equatable {
        case update
    }

    let phase: UpdatePhase
    let action: Action?

    init?(phase: UpdatePhase?, canCheckForUpdates: Bool) {
        guard let phase else {
            return nil
        }

        self.phase = phase
        switch phase {
        case .available:
            action = canCheckForUpdates ? .update : nil
        case .downloading, .preparing:
            action = nil
        }
    }

    var showsProgress: Bool {
        action == nil
    }
}

@MainActor
@Observable
final class UpdateCoordinator: NSObject, SPUUpdaterDelegate {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var updatePhase: UpdatePhase?
    let isAvailable: Bool

    @ObservationIgnored
    private var updaterController: SPUStandardUpdaterController?

    @ObservationIgnored
    private var updaterObservations: [NSKeyValueObservation] = []

    init(bundle: Bundle = .main) {
        guard bundle === Bundle.main, UpdateEligibility.isEligible(bundle: bundle) else {
            isAvailable = false
            super.init()
            return
        }

        isAvailable = true
        super.init()
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        updaterController = controller
        observeUpdaterState(controller.updater)
        refreshState(from: controller.updater)
    }

    var popoverUpdate: PopoverUpdate? {
        PopoverUpdate(phase: updatePhase, canCheckForUpdates: canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController?.updater.checkForUpdates()
    }

    func setAutomaticChecksForUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater else {
            return
        }
        updater.automaticallyChecksForUpdates = enabled
        refreshState(from: updater)
    }

    func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordUpdateCheckResult(.updateAvailable(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_: SPUUpdater, error _: any Error) {
        recordUpdateCheckResult(.noUpdate)
    }

    func updater(_: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard ScheduledCheckGate.allows(updateCheck) else {
            throw ScheduledCheckGate.refusal
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if ScheduledCheckGate.startsInformationCheck(after: updateCheck, error: error) {
            updater.checkForUpdateInformation()
        } else {
            recordUpdateCycleEnd(updateCheck)
        }
    }

    func updater(_: SPUUpdater, didAbortWithError error: any Error) {
        recordUpdateAbort(error)
    }

    func updater(_: SPUUpdater, willDownloadUpdate _: SUAppcastItem, with _: NSMutableURLRequest) {
        recordUpdateProgress(.downloadStarted)
    }

    func updater(_: SPUUpdater, failedToDownloadUpdate _: SUAppcastItem, error _: any Error) {
        recordUpdateProgress(.interrupted)
    }

    func userDidCancelDownload(_: SPUUpdater) {
        recordUpdateProgress(.interrupted)
    }

    func updater(_: SPUUpdater, didDownloadUpdate _: SUAppcastItem) {
        recordUpdateProgress(.preparationStarted)
    }

    func updater(_: SPUUpdater, willExtractUpdate _: SUAppcastItem) {
        recordUpdateProgress(.preparationStarted)
    }

    func recordUpdateCheckResult(_ result: UpdateCheckResult) {
        switch result {
        case let .updateAvailable(version):
            updatePhase = .available(version: version)
        case .noUpdate:
            updatePhase = nil
        case .failed:
            recordUpdateProgress(.interrupted)
        }
    }

    func recordUpdateAbort(_ error: any Error) {
        guard !ScheduledCheckGate.isRefusal(error) else {
            return
        }
        recordUpdateCheckResult(.failed)
    }

    /// Sparkle skips `didAbortWithError` when the user closes its window after the download,
    /// so the end of the user check is the only signal that the work stopped.
    func recordUpdateCycleEnd(_ updateCheck: SPUUpdateCheck) {
        guard updateCheck == .updates else {
            return
        }
        recordUpdateProgress(.interrupted)
    }

    func recordUpdateProgress(_ progress: UpdateProgress) {
        guard let version = updatePhase?.version else {
            return
        }

        switch progress {
        case .downloadStarted:
            updatePhase = .downloading(version: version)
        case .preparationStarted:
            updatePhase = .preparing(version: version)
        case .interrupted:
            updatePhase = .available(version: version)
        }
    }

    private func observeUpdaterState(_ updater: SPUUpdater) {
        let keyPaths: [KeyPath<SPUUpdater, Bool>] = [
            \.canCheckForUpdates,
            \.automaticallyChecksForUpdates,
        ]
        updaterObservations = keyPaths.map { keyPath in
            updater.observe(keyPath, options: [.initial, .new]) { [weak self] updater, _ in
                Task { @MainActor [weak self] in
                    self?.refreshState(from: updater)
                }
            }
        }
    }

    private func refreshState(from updater: SPUUpdater) {
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
    }
}

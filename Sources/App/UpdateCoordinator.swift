import Foundation
import Observation
import Sparkle

enum UpdateConfiguration {
    static let feedURLKey = "SUFeedURL"
    static let publicEDKey = "SUPublicEDKey"
    static let automaticChecksKey = "SUEnableAutomaticChecks"
    static let automaticDownloadsKey = "SUAutomaticallyUpdate"
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

enum UpdateCheckResult: Equatable {
    case updateAvailable(version: String)
    case noUpdate
    case failed
}

struct PopoverUpdate: Equatable {
    let availableVersion: String
    let canStartUpdate: Bool

    init?(availableVersion: String?, canStartUpdate: Bool) {
        guard let availableVersion else {
            return nil
        }

        self.availableVersion = availableVersion
        self.canStartUpdate = canStartUpdate
    }
}

@MainActor
@Observable
final class UpdateCoordinator: NSObject, SPUUpdaterDelegate {
    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecksForUpdates = false
    private(set) var automaticallyDownloadsUpdates = false
    private(set) var allowsAutomaticUpdates = false
    private(set) var availableUpdateVersion: String?
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
        PopoverUpdate(
            availableVersion: availableUpdateVersion,
            canStartUpdate: canCheckForUpdates
        )
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

    func setAutomaticDownloadsUpdates(_ enabled: Bool) {
        guard let updater = updaterController?.updater, updater.allowsAutomaticUpdates else {
            return
        }
        updater.automaticallyDownloadsUpdates = enabled
        refreshState(from: updater)
    }

    func updater(_: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        recordUpdateCheckResult(.updateAvailable(version: item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_: SPUUpdater, error _: any Error) {
        recordUpdateCheckResult(.noUpdate)
    }

    func updater(_: SPUUpdater, didAbortWithError _: any Error) {
        recordUpdateCheckResult(.failed)
    }

    func recordUpdateCheckResult(_ result: UpdateCheckResult) {
        switch result {
        case let .updateAvailable(version):
            availableUpdateVersion = version
        case .noUpdate:
            availableUpdateVersion = nil
        case .failed:
            break
        }
    }

    private func observeUpdaterState(_ updater: SPUUpdater) {
        let keyPaths: [KeyPath<SPUUpdater, Bool>] = [
            \.canCheckForUpdates,
            \.automaticallyChecksForUpdates,
            \.automaticallyDownloadsUpdates,
            \.allowsAutomaticUpdates,
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
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
    }
}

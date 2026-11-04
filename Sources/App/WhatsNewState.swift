import Foundation

// `@unchecked`: `UserDefaults` is documented as thread-safe but is not marked `Sendable`.
struct WhatsNewState: @unchecked Sendable {
    static let lastSeenKey = "whats-new-last-seen-version"
    static let showArgument = "--show-whats-new"

    let runningVersion: ReleaseVersion?
    private let defaults: UserDefaults
    private let arguments: [String]
    private let hasExistingInstall: @Sendable () -> Bool

    init(
        defaults: UserDefaults = .standard,
        runningVersion: ReleaseVersion? = WhatsNewState.bundleVersion(.main),
        arguments: [String] = ProcessInfo.processInfo.arguments,
        hasExistingInstall: @escaping @Sendable () -> Bool
    ) {
        self.defaults = defaults
        self.runningVersion = runningVersion
        self.arguments = arguments
        self.hasExistingInstall = hasExistingInstall
    }

    var opensOnLaunch: Bool {
        arguments.contains(Self.showArgument)
    }

    var lastSeenVersion: ReleaseVersion? {
        defaults.string(forKey: Self.lastSeenKey).flatMap(ReleaseVersion.init)
    }

    /// Read before the registry first resolves enablement, because that resolution saves a value.
    /// With nothing to announce, the running version counts as seen, so a new install stays quiet.
    func resolveLaunchAnnouncement(in highlights: ReleaseHighlights) -> [ReleaseHighlights.Release] {
        guard let runningVersion else {
            return []
        }

        let releases = if let lastSeenVersion {
            highlights.releases(after: lastSeenVersion, through: runningVersion)
        } else if hasExistingInstall() {
            highlights.releases(after: nil, through: runningVersion).filter { $0.version == runningVersion }
        } else {
            [ReleaseHighlights.Release]()
        }

        if releases.isEmpty {
            markSeen()
        }
        return releases
    }

    func markSeen() {
        guard let runningVersion else {
            return
        }
        defaults.set(runningVersion.description, forKey: Self.lastSeenKey)
    }

    static func bundleVersion(_ bundle: Bundle) -> ReleaseVersion? {
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.normalizedReleaseVersion)
            .flatMap(ReleaseVersion.init)
    }
}

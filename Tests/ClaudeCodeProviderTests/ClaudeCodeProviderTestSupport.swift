@testable import ClaudeCodeProvider
import Core
import XCTest

extension ClaudeCodeProviderTests {
    func makeProvider(
        locator: ClaudeCodeLocator = ClaudeCodeLocator(injectedPath: "/usr/local/bin/claude"),
        installer: StatuslineHelperInstaller? = nil
    ) -> ClaudeCodeProvider {
        ClaudeCodeProvider(
            locator: locator,
            cacheStore: StatuslineCacheStore(cacheURL: cacheURL),
            installer: installer ?? makeInstaller(helperInstalled: true)
        )
    }

    func makeInstaller(helperInstalled: Bool) -> StatuslineHelperInstaller {
        let helperURL = tmpDir.appendingPathComponent("helper")
        let installer = StatuslineHelperInstaller(
            settingsURL: tmpDir.appendingPathComponent("settings.json"),
            helperDestURL: helperURL, cacheURL: cacheURL
        )
        if helperInstalled {
            try? "#!/bin/sh\nexit 0\n".write(to: helperURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helperURL.path)
            try? installer.installSettingsOnly()
        }
        return installer
    }

    func writeCache(
        fiveHourPct: Double?, fiveHourReset: TimeInterval?,
        sevenDayPct: Double?, sevenDayReset: TimeInterval?
    ) throws {
        let fiveHour = fiveHourPct.map { Window(usedPercentage: $0, resetsAt: fiveHourReset) }
        let sevenDay = sevenDayPct.map { Window(usedPercentage: $0, resetsAt: sevenDayReset) }
        let rateLimits: RateLimits? = if fiveHour != nil || sevenDay != nil {
            RateLimits(fiveHour: fiveHour, sevenDay: sevenDay)
        } else {
            nil
        }
        try StatuslineCacheStore(cacheURL: cacheURL).write(StatuslineCache(
            writtenAt: Date().timeIntervalSince1970, rateLimits: rateLimits
        ))
    }

    func futureEpoch() -> TimeInterval {
        Date().addingTimeInterval(3600).timeIntervalSince1970
    }
}

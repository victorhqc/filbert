@testable import ClaudeCodeProvider
import Core
import XCTest

final class StatuslineHelperRemovalRecoveryTests: XCTestCase {
    private var directory: URL!
    private var settingsURL: URL!
    private var helperURL: URL!
    private var cacheURL: URL!
    private var legacyHelperURL: URL!
    private var legacyCacheURL: URL!
    private var installer: StatuslineHelperInstaller!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-removal-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        settingsURL = directory.appendingPathComponent("settings.json")
        helperURL = directory.appendingPathComponent("helper")
        cacheURL = directory.appendingPathComponent("cache/current.json")
        legacyHelperURL = directory.appendingPathComponent("legacy-helper")
        legacyCacheURL = directory.appendingPathComponent("legacy-cache/cache.json")
        installer = StatuslineHelperInstaller(
            settingsURL: settingsURL, helperDestURL: helperURL, cacheURL: cacheURL,
            legacyConfiguration: LegacyClaudeBrandConfiguration(
                helperURL: legacyHelperURL, cacheURL: legacyCacheURL,
                chainStart: "###AI-USAGE-CHAIN-START###",
                chainSeparator: "###AI-USAGE-CHAIN-SEPARATOR###"
            ),
            errorLog: ErrorLog(directoryURL: directory.appendingPathComponent("logs"))
        )
    }

    override func tearDownWithError() throws {
        for cache in [cacheURL, legacyCacheURL].compactMap({ $0 }) {
            let parent = cache.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            }
        }
        try FileManager.default.removeItem(at: directory)
    }

    func testCurrentCacheDeletionFailureRetainsIntegrationForRetry() throws {
        try assertCacheDeletionFailureIsRetryable(cacheURL)
    }

    func testLegacyCacheDeletionFailureRetainsIntegrationForRetry() throws {
        try writeCache(cacheURL)
        try assertCacheDeletionFailureIsRetryable(legacyCacheURL)
    }

    func testCurrentCacheOnlyArtifactCanBeRemoved() throws {
        try assertCacheOnlyArtifactCanBeRemoved(cacheURL)
    }

    func testLegacyCacheOnlyArtifactCanBeRemoved() throws {
        try assertCacheOnlyArtifactCanBeRemoved(legacyCacheURL)
    }

    private func assertCacheDeletionFailureIsRetryable(_ cache: URL) throws {
        try writeHelper(helperURL)
        try writeHelper(legacyHelperURL)
        try Data(#"{"statusLine":{"type":"command","command":"printf original","padding":4},"other":true}"#.utf8)
            .write(to: settingsURL)
        try installer.installSettingsOnly()
        let settingsBefore = try Data(contentsOf: settingsURL)
        let helperBefore = try Data(contentsOf: helperURL)
        try writeCache(cache)
        let cacheBefore = try Data(contentsOf: cache)
        let parent = cache.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: parent.path)
        XCTAssertFalse(FileManager.default.isWritableFile(atPath: parent.path))

        XCTAssertThrowsError(try installer.uninstall())

        XCTAssertEqual(try Data(contentsOf: settingsURL), settingsBefore)
        XCTAssertEqual(try Data(contentsOf: helperURL), helperBefore)
        XCTAssertEqual(try Data(contentsOf: cache), cacheBefore)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyHelperURL.path))
        XCTAssertTrue(installer.isHelperInstalled())
        XCTAssertTrue(installer.canRemoveHelper())

        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
        try installer.uninstall()

        XCTAssertFalse(installer.canRemoveHelper())
        XCTAssertFalse(FileManager.default.fileExists(atPath: helperURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyHelperURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyCacheURL.path))
        let settings = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any]
        )
        let statusLine = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["command"] as? String, "printf original")
        XCTAssertEqual(statusLine["padding"] as? Int, 4)
        XCTAssertEqual(settings["other"] as? Bool, true)
    }

    private func assertCacheOnlyArtifactCanBeRemoved(_ cache: URL) throws {
        XCTAssertFalse(installer.canRemoveHelper())
        try writeCache(cache)
        XCTAssertTrue(installer.canRemoveHelper())
        try installer.uninstall()
        XCTAssertFalse(installer.canRemoveHelper())
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsURL.path))
    }

    private func writeHelper(_ url: URL) throws {
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writeCache(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"written_at":1234,"rate_limits":{"five_hour":{"used_percentage":42}}}"#.utf8).write(to: url)
    }
}

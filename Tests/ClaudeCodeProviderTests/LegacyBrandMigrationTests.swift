@testable import ClaudeCodeProvider
import XCTest

final class LegacyBrandMigrationTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var settingsURL: URL!
    private var helperURL: URL!
    private var cacheURL: URL!
    private var legacyHelperURL: URL!
    private var legacyCacheURL: URL!
    private var sourceURL: URL!
    private var compilerURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("filbert-legacy-brand-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        settingsURL = temporaryDirectory.appendingPathComponent("settings.json")
        helperURL = temporaryDirectory.appendingPathComponent("filbert-statusline")
        cacheURL = temporaryDirectory.appendingPathComponent("filbert-cache.json")
        legacyHelperURL = temporaryDirectory.appendingPathComponent("ai-usage-statusline")
        legacyCacheURL = temporaryDirectory.appendingPathComponent("ai-usage-cache.json")
        sourceURL = temporaryDirectory.appendingPathComponent("statusline_helper.swift")
        compilerURL = temporaryDirectory.appendingPathComponent("swiftc")

        try "#!/bin/sh\nexit 0\n".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )
        try """
        #!/bin/sh
        cp "$4" "$3"
        chmod +x "$3"
        """.write(
            to: compilerURL,
            atomically: true,
            encoding: .utf8
        )
        try makeExecutable(compilerURL)
    }

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        compilerURL = nil
        sourceURL = nil
        legacyCacheURL = nil
        legacyHelperURL = nil
        cacheURL = nil
        helperURL = nil
        settingsURL = nil
        temporaryDirectory = nil
        super.tearDown()
    }

    func testMigrationReplacesLegacyChainAndMovesValidCache() throws {
        try createLegacyHelper()
        try writeSettings(
            command: "###AI-USAGE-CHAIN-START###original-command"
                + "###AI-USAGE-CHAIN-SEPARATOR###"
        )
        try writeCache(to: legacyCacheURL)
        let installer = makeInstaller()

        XCTAssertTrue(
            try installer.migrateLegacyInstallationIfNeeded(
                helperSourceURL: sourceURL
            )
        )

        XCTAssertTrue(installer.isHelperInstalled())
        let command = try readCommand()
        XCTAssertTrue(command.contains("original-command"))
        XCTAssertTrue(command.contains("###FILBERT-CHAIN-START###"))
        XCTAssertTrue(command.contains(helperURL.path))
        XCTAssertFalse(command.contains("###AI-USAGE-CHAIN-START###"))
        XCTAssertNotNil(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyHelperURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyCacheURL.path))
    }

    func testMigrationIsIdempotent() throws {
        try createLegacyHelper()
        try writeSettings(command: legacyHelperURL.path)
        let installer = makeInstaller()

        XCTAssertTrue(
            try installer.migrateLegacyInstallationIfNeeded(
                helperSourceURL: sourceURL
            )
        )
        XCTAssertFalse(
            try installer.migrateLegacyInstallationIfNeeded(
                helperSourceURL: sourceURL
            )
        )
        XCTAssertEqual(try readCommand(), helperURL.path)
    }

    func testCacheOnlyMigrationDoesNotInstallHelperOrChangeSettings() throws {
        try writeSettings(command: "my-statusline")
        try writeCache(to: legacyCacheURL)
        let installer = makeInstaller()

        XCTAssertFalse(
            try installer.migrateLegacyInstallationIfNeeded(
                helperSourceURL: sourceURL
            )
        )

        XCTAssertFalse(installer.isHelperInstalled())
        XCTAssertEqual(try readCommand(), "my-statusline")
        XCTAssertNotNil(StatuslineCacheStore(cacheURL: cacheURL).read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyCacheURL.path))
    }

    func testCompilerFailureLeavesLegacyArtifactsAndSettingsIntact() throws {
        try createLegacyHelper()
        let legacyCommand = legacyHelperURL.path
        try writeSettings(command: legacyCommand)
        try writeCache(to: legacyCacheURL)
        let installer = makeInstaller(swiftCompilerPath: "/usr/bin/false")

        XCTAssertThrowsError(
            try installer.migrateLegacyInstallationIfNeeded(
                helperSourceURL: sourceURL
            )
        )

        XCTAssertEqual(try readCommand(), legacyCommand)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyHelperURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyCacheURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: helperURL.path))
    }

    func testCacheStoreReadsLegacyFallback() throws {
        try writeCache(to: legacyCacheURL)
        let store = StatuslineCacheStore(
            cacheURL: cacheURL,
            fallbackCacheURL: legacyCacheURL
        )

        XCTAssertEqual(store.read()?.writtenAt, 1_713_000_000)
    }

    private func makeInstaller(
        swiftCompilerPath: String? = nil
    ) -> StatuslineHelperInstaller {
        StatuslineHelperInstaller(
            settingsURL: settingsURL,
            helperDestURL: helperURL,
            cacheURL: cacheURL,
            legacyConfiguration: LegacyClaudeBrandConfiguration(
                helperURL: legacyHelperURL,
                cacheURL: legacyCacheURL,
                chainStart: "###AI-USAGE-CHAIN-START###",
                chainSeparator: "###AI-USAGE-CHAIN-SEPARATOR###"
            ),
            swiftCompilerPath: swiftCompilerPath ?? compilerURL.path
        )
    }

    private func createLegacyHelper() throws {
        try "#!/bin/sh\nexit 0\n".write(
            to: legacyHelperURL,
            atomically: true,
            encoding: .utf8
        )
        try makeExecutable(legacyHelperURL)
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    private func writeSettings(command: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: [
                "statusLine": [
                    "type": "command",
                    "command": command,
                ],
            ],
            options: [.sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    private func readCommand() throws -> String {
        let data = try Data(contentsOf: settingsURL)
        let settings = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let statusLine = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        return try XCTUnwrap(statusLine["command"] as? String)
    }

    private func writeCache(to url: URL) throws {
        let data = Data("""
        {
          "written_at": 1713000000,
          "rate_limits": {
            "five_hour": {
              "used_percentage": 25
            }
          }
        }
        """.utf8)
        try data.write(to: url, options: .atomic)
    }
}

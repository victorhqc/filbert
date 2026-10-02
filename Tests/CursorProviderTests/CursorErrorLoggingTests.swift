import Core
@testable import CursorProvider
import Foundation
import Security
import XCTest

final class CursorErrorLoggingTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var errorLog: ErrorLog!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        errorLog = ErrorLog(directoryURL: temporaryDirectory.appendingPathComponent("logs"))
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testMissingSQLiteStoreDoesNotRecordError() {
        let value = CursorTokenStore.defaultReadSQLiteValue(
            dbPath: temporaryDirectory.appendingPathComponent("absent.vscdb").path,
            key: CursorAuth.sqliteAccessKey,
            errorLog: errorLog
        )

        XCTAssertNil(value)
        XCTAssertNil(errorLog.availableFileURL)
    }

    func testMalformedSQLiteStoreRecordsOneFailureWithoutContents() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent("state.vscdb")
        try Data("sqlite-credential-secret".utf8).write(to: databaseURL)

        let value = CursorTokenStore.defaultReadSQLiteValue(
            dbPath: databaseURL.path,
            key: CursorAuth.sqliteAccessKey,
            errorLog: errorLog
        )

        XCTAssertNil(value)
        let logURL = try XCTUnwrap(errorLog.availableFileURL)
        let records = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertEqual(records.split(whereSeparator: \.isNewline).count, 1)
        XCTAssertTrue(records.contains("sqlite_prepare_failed"))
        XCTAssertTrue(records.contains("cursor"))
        XCTAssertFalse(records.contains("sqlite-credential-secret"))
        XCTAssertFalse(records.contains(databaseURL.path))
    }

    func testUnavailableExplicitImportRemainsOrdinarySetup() async throws {
        let provider = makeProvider(vault: TestCursorCredentialVault(), externalStorage: ClosureKeychainStorage())
        XCTAssertFalse(provider.isConfigured())

        do {
            try await provider.importCredentials()
            XCTFail("Expected missing credentials")
        } catch let error as ProviderSetupError {
            XCTAssertEqual(error, .missingCredentials)
        }

        guard case .setup = await provider.currentSetupState() else {
            return XCTFail("Expected ordinary setup guidance")
        }
        XCTAssertNil(errorLog.availableFileURL)
    }

    func testCancelledSharedKeychainReadsRemainOrdinarySetup() async {
        let keychain = Keychain(
            storage: ClosureKeychainStorage(read: { _, _ in throw KeychainStorageError.status(errSecUserCanceled) }),
            service: "cursor-tests"
        )
        let provider = makeProvider(
            vault: KeychainCursorCredentialVault(keychain: keychain),
            externalStorage: ClosureKeychainStorage()
        )

        XCTAssertFalse(provider.isConfigured())
        guard case .setup = await provider.currentSetupState() else {
            return XCTFail("Expected ordinary setup guidance")
        }
        XCTAssertNil(errorLog.availableFileURL)
    }

    func testCancelledSharedKeychainFetchAndRemovalStaySilent() async throws {
        let keychain = Keychain(
            storage: ClosureKeychainStorage(read: { _, _ in throw KeychainStorageError.status(errSecUserCanceled) }),
            service: "cursor-tests"
        )
        let provider = makeProvider(
            vault: KeychainCursorCredentialVault(keychain: keychain),
            externalStorage: ClosureKeychainStorage()
        )

        do {
            _ = try await provider.fetchQuota(auth: .apiKeyFree, baseURL: CursorProvider.baseURL)
            XCTFail("Expected credential-read cancellation")
        } catch is CancellationError {}
        do {
            try await provider.removeHelper()
            XCTFail("Expected credential-removal cancellation")
        } catch is CancellationError {}
        XCTAssertNil(errorLog.availableFileURL)
    }

    func testCancelledExternalReadsAndSharedSavesStaySilent() async throws {
        let saveCancelledVault = TestCursorCredentialVault()
        saveCancelledVault.setSaveFailure(true, status: errSecUserCanceled)
        let providers = [
            makeProvider(
                vault: TestCursorCredentialVault(),
                externalStorage: ClosureKeychainStorage(read: { _, _ in
                    throw KeychainStorageError.status(errSecUserCanceled)
                })
            ),
            makeProvider(
                vault: saveCancelledVault,
                externalStorage: ClosureKeychainStorage(read: { _, _ in "fixture-token" })
            ),
        ]
        for provider in providers {
            XCTAssertFalse(provider.isConfigured())
            guard case .setup = await provider.currentSetupState() else {
                return XCTFail("Expected ordinary setup guidance")
            }
            do {
                try await provider.importCredentials()
                XCTFail("Expected cancellation")
            } catch is CancellationError {
                XCTAssertFalse(Task.isCancelled)
            }
            XCTAssertNil(errorLog.availableFileURL)
        }
    }

    private func makeProvider(
        vault: any CursorCredentialVault,
        externalStorage: any KeychainStorage
    ) -> CursorProvider {
        CursorProvider(
            locator: CursorLocator(environment: [:], isExecutable: { _ in false }),
            tokenStore: CursorTokenStore(
                vault: vault,
                homeDirectory: "/test",
                externalStorage: externalStorage,
                readSQLiteValue: { _, _ in nil }
            ),
            session: .shared,
            errorLog: errorLog
        )
    }
}

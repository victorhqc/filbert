import Core
import Foundation
import Security
import XCTest

@MainActor
final class ProviderConfigurationLoggingTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        suiteName = "filbert.tests.configuration-logging.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        ProviderEnablement.setUserDefaults(defaults)
    }

    override func tearDownWithError() throws {
        ProviderEnablement.setUserDefaults(.standard)
        defaults.removePersistentDomain(forName: suiteName)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testConfigurationReadFailuresProduceSafeRecordsAndVisibleReason() throws {
        for outcome in [
            Result<Data?, KeychainStorageError>.failure(.status(errSecAuthFailed)),
            .success(Data("SECRET-invalid-json".utf8)),
        ] {
            let storage = ConfigurationLoggingStorage(outcome: outcome)
            let log = ErrorLog(directoryURL: directory.appendingPathComponent(UUID().uuidString))
            let registry = makeRegistry(storage: storage, errorLog: log)

            XCTAssertFalse(registry.isConfigured(ConfigurationLoggingProvider.providerId))
            XCTAssertNotNil(registry.configurationError(for: ConfigurationLoggingProvider.providerId))
            let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
            XCTAssertTrue(contents.contains("check-configuration"))
            XCTAssertFalse(contents.contains("SECRET"))
            XCTAssertEqual(contents.split(separator: "\n").count, 1)
        }
    }

    func testAbsentCredentialsAndCancelledPromptRemainSilent() {
        for outcome in [
            Result<Data?, KeychainStorageError>.success(nil),
            .failure(.status(errSecUserCanceled)),
        ] {
            let log = ErrorLog(directoryURL: directory.appendingPathComponent(UUID().uuidString))
            let registry = makeRegistry(
                storage: ConfigurationLoggingStorage(outcome: outcome),
                errorLog: log
            )

            XCTAssertFalse(registry.isConfigured(ConfigurationLoggingProvider.providerId))
            XCTAssertNil(registry.configurationError(for: ConfigurationLoggingProvider.providerId))
            XCTAssertNil(log.availableFileURL)
        }
    }

    func testEnablementFailureDoesNotPersistDisabledPreferenceAndCanRecover() throws {
        let id = ConfigurationLoggingProvider.providerId
        let storage = ConfigurationLoggingStorage(outcome: .failure(.status(errSecAuthFailed)))
        let keychain = Keychain(storage: storage, service: suiteName)
        let log = ErrorLog(directoryURL: directory)

        XCTAssertFalse(ProviderEnablement.isEnabled(
            for: id, authShape: .apiKey, keychain: keychain, errorLog: log
        ))
        XCTAssertNil(ProviderEnablement.savedEnabled(for: id))
        XCTAssertEqual(try String(contentsOf: log.fileURL, encoding: .utf8).split(separator: "\n").count, 1)

        storage.setOutcome(.success(validCredentials))

        XCTAssertTrue(ProviderEnablement.isEnabled(
            for: id, authShape: .apiKey, keychain: keychain, errorLog: log
        ))
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: id), true)
        XCTAssertEqual(try String(contentsOf: log.fileURL, encoding: .utf8).split(separator: "\n").count, 1)
    }

    func testCancelledEnablementDoesNotPersistOrLogFailure() {
        let id = ConfigurationLoggingProvider.providerId
        let keychain = Keychain(
            storage: ConfigurationLoggingStorage(outcome: .failure(.status(errSecUserCanceled))),
            service: suiteName
        )
        let log = ErrorLog(directoryURL: directory)

        XCTAssertFalse(ProviderEnablement.isEnabled(
            for: id, authShape: .apiKey, keychain: keychain, errorLog: log
        ))
        XCTAssertNil(ProviderEnablement.savedEnabled(for: id))
        XCTAssertNil(log.availableFileURL)
    }

    func testConfigurationRecoveryClearsPreviousReason() {
        let id = ConfigurationLoggingProvider.providerId
        let storage = ConfigurationLoggingStorage(outcome: .failure(.status(errSecAuthFailed)))
        let registry = makeRegistry(storage: storage, errorLog: ErrorLog(directoryURL: directory))
        XCTAssertFalse(registry.isConfigured(id))
        XCTAssertNotNil(registry.configurationError(for: id))

        storage.setOutcome(.success(validCredentials))

        XCTAssertTrue(registry.isConfigured(id))
        XCTAssertNil(registry.configurationError(for: id))
    }

    private var validCredentials: Data {
        Data("{\"\(ConfigurationLoggingProvider.providerId)\":{\"value\":\"SECRET-key\"}}".utf8)
    }

    private func makeRegistry(
        storage: ConfigurationLoggingStorage,
        errorLog: ErrorLog
    ) -> ProviderRegistry {
        ProviderEnablement.setEnabled(true, for: ConfigurationLoggingProvider.providerId)
        let registry = ProviderRegistry(
            keychain: Keychain(storage: storage, service: suiteName),
            errorLog: errorLog
        )
        registry.register(ConfigurationLoggingProvider())
        return registry
    }
}

private final class ConfigurationLoggingStorage: KeychainStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<Data?, KeychainStorageError>

    init(outcome: Result<Data?, KeychainStorageError>) {
        self.outcome = outcome
    }

    func setOutcome(_ outcome: Result<Data?, KeychainStorageError>) {
        lock.withLock { self.outcome = outcome }
    }

    func readData(
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws -> Data? {
        try lock.withLock { try outcome.get() }
    }

    func replaceData(
        _ data: Data,
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws {
        setOutcome(.success(data))
    }

    func delete(service _: String, account _: String, authenticationContext _: KeychainAuthenticationContext) {
        setOutcome(.success(nil))
    }
}

private struct ConfigurationLoggingProvider: AIProvider {
    static let providerId = "configuration-logging-fixture"
    static let providerName = "Configuration logging fixture"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        XCTFail("Failed configuration must not fetch usage")
        throw ProviderSetupError.notSupported
    }
}

@testable import Core
import Foundation
import XCTest

@MainActor
final class ProviderEnablementTests: XCTestCase {
    private let suiteName = "filbert.tests.provider-enablement"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderEnablement.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    func testMissingAPIKeyDefaultsToDisabledAndPersistsResolution() {
        let storage = InMemoryStorage()
        let keychain = Keychain(storage: storage, service: "enablement")

        XCTAssertFalse(
            ProviderEnablement.isEnabled(
                for: "api-key-provider",
                authShape: .apiKey,
                keychain: keychain
            )
        )
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: "api-key-provider"), false)
        XCTAssertEqual(storage.readCount, 1)
    }

    func testStoredAPIKeyDefaultsToEnabledAndPersistsResolution() throws {
        let storage = InMemoryStorage()
        let keychain = Keychain(storage: storage, service: "enablement")
        try keychain.save("saved-key", for: "api-key-provider")

        XCTAssertTrue(
            ProviderEnablement.isEnabled(
                for: "api-key-provider",
                authShape: .apiKey,
                keychain: keychain
            )
        )
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: "api-key-provider"), true)
    }

    func testAPIKeyFreeProviderDefaultsToDisabledWithoutReadingKeychain() {
        let storage = InMemoryStorage()
        let keychain = Keychain(storage: storage, service: "enablement")

        XCTAssertFalse(
            ProviderEnablement.isEnabled(
                for: "api-key-free-provider",
                authShape: .apiKeyFree,
                keychain: keychain
            )
        )
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: "api-key-free-provider"), false)
        XCTAssertEqual(storage.readCount, 0)
    }

    func testExplicitValueSurvivesLaterKeychainChangesAndStoreRecreation() throws {
        let storage = InMemoryStorage()
        let keychain = Keychain(storage: storage, service: "enablement")
        ProviderEnablement.setEnabled(false, for: "api-key-provider")
        try keychain.save("saved-key", for: "api-key-provider")

        XCTAssertFalse(
            ProviderEnablement.isEnabled(
                for: "api-key-provider",
                authShape: .apiKey,
                keychain: keychain
            )
        )

        let recreatedDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        ProviderEnablement.setUserDefaults(recreatedDefaults)
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: "api-key-provider"), false)
    }

    func testDisabledProviderReceivesNoRegistryOperationCalls() async {
        let provider = GateSpyProvider()
        let registry = ProviderRegistry()
        registry.register(provider)
        ProviderEnablement.setEnabled(false, for: GateSpyProvider.providerId)

        XCTAssertFalse(registry.isConfigured(GateSpyProvider.providerId))
        let fetchAllResults = await registry.fetchAll()
        let scopedFetchResult = await registry.fetchQuota(for: GateSpyProvider.providerId)
        let setupStates = await registry.refreshSetupStates()
        let setupState = await registry.refreshSetupState(for: GateSpyProvider.providerId)
        XCTAssertTrue(fetchAllResults.isEmpty)
        XCTAssertNil(scopedFetchResult)
        XCTAssertTrue(setupStates.isEmpty)
        XCTAssertNil(setupState)
        XCTAssertFalse(registry.canInstallHelper(for: GateSpyProvider.providerId))
        XCTAssertNil(registry.credentialImportActionTitle(for: GateSpyProvider.providerId))

        await assertNotSupported {
            try await registry.installHelper(for: GateSpyProvider.providerId)
        }
        await assertNotSupported {
            try await registry.removeHelper(for: GateSpyProvider.providerId)
        }
        await assertNotSupported {
            try await registry.importCredentials(for: GateSpyProvider.providerId)
        }
        await assertNotSupported {
            try await registry.proactiveRefresh(for: GateSpyProvider.providerId)
        }

        XCTAssertEqual(provider.isConfiguredCallCount, 0)
        XCTAssertEqual(provider.setupStateCallCount, 0)
        XCTAssertEqual(provider.fetchCallCount, 0)
        XCTAssertEqual(provider.canInstallCallCount, 0)
        XCTAssertEqual(provider.installCallCount, 0)
        XCTAssertEqual(provider.removeCallCount, 0)
        XCTAssertEqual(provider.importCallCount, 0)
        XCTAssertEqual(provider.proactiveRefreshCallCount, 0)
    }

    private func assertNotSupported(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected ProviderSetupError.notSupported")
        } catch ProviderSetupError.notSupported {
        } catch {
            XCTFail("Expected ProviderSetupError.notSupported, got \(error)")
        }
    }
}

private final class InMemoryStorage: KeychainStorage, @unchecked Sendable {
    var data: Data?
    var readCount = 0

    func readData(
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws -> Data? {
        readCount += 1
        return data
    }

    func replaceData(
        _ data: Data,
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws {
        self.data = data
    }

    func delete(
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) {}
}

private final class GateSpyProvider: AIProvider, ProactiveRefreshable, @unchecked Sendable {
    static let providerId = "gate-spy"
    static let providerName = "Gate Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let credentialImportActionTitle: String? = "Import credentials"

    var isConfiguredCallCount = 0
    var setupStateCallCount = 0
    var fetchCallCount = 0
    var canInstallCallCount = 0
    var installCallCount = 0
    var removeCallCount = 0
    var importCallCount = 0
    var proactiveRefreshCallCount = 0

    func isConfigured() -> Bool {
        isConfiguredCallCount += 1
        return true
    }

    func currentSetupState() async -> ProviderState? {
        setupStateCallCount += 1
        return nil
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        return ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "Ready",
            lines: [],
            lastUpdated: Date()
        )
    }

    func canInstallHelper() -> Bool {
        canInstallCallCount += 1
        return true
    }

    func installHelper() async throws {
        installCallCount += 1
    }

    func removeHelper() async throws {
        removeCallCount += 1
    }

    func importCredentials() async throws {
        importCallCount += 1
    }

    func proactiveRefresh() async throws {
        proactiveRefreshCallCount += 1
    }
}

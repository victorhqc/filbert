@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class ProviderEnablementViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.provider-enablement-view-model"
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

    func testSavingKeyEnablesProviderAfterKeychainSave() throws {
        let storage = ViewModelKeychainStorage()
        let keychain = Keychain(storage: storage, service: "view-model")
        let registry = ProviderRegistry(keychain: keychain)
        registry.register(APIKeySpyProvider())
        let viewModel = QuotaViewModel(keychain: keychain, registry: registry)

        XCTAssertFalse(viewModel.isEnabled(APIKeySpyProvider.providerId))

        try viewModel.saveKey("saved-key", for: APIKeySpyProvider.providerId)

        XCTAssertTrue(viewModel.isEnabled(APIKeySpyProvider.providerId))
        XCTAssertEqual(try keychain.load(for: APIKeySpyProvider.providerId), "saved-key")
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: APIKeySpyProvider.providerId), true)
    }

    func testFailedKeySaveLeavesEnablementUnchanged() {
        let storage = ViewModelKeychainStorage()
        storage.shouldFailWrites = true
        let keychain = Keychain(storage: storage, service: "view-model")
        let registry = ProviderRegistry(keychain: keychain)
        registry.register(APIKeySpyProvider())
        let viewModel = QuotaViewModel(keychain: keychain, registry: registry)

        XCTAssertThrowsError(
            try viewModel.saveKey("saved-key", for: APIKeySpyProvider.providerId)
        )
        XCTAssertFalse(viewModel.isEnabled(APIKeySpyProvider.providerId))
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: APIKeySpyProvider.providerId), false)
    }

    func testClearingKeyKeepsProviderEnabled() throws {
        let storage = ViewModelKeychainStorage()
        let keychain = Keychain(storage: storage, service: "view-model")
        let registry = ProviderRegistry(keychain: keychain)
        registry.register(APIKeySpyProvider())
        let viewModel = QuotaViewModel(keychain: keychain, registry: registry)
        try viewModel.saveKey("saved-key", for: APIKeySpyProvider.providerId)

        try viewModel.deleteKey(for: APIKeySpyProvider.providerId)

        XCTAssertTrue(viewModel.isEnabled(APIKeySpyProvider.providerId))
        XCTAssertEqual(ProviderEnablement.savedEnabled(for: APIKeySpyProvider.providerId), true)
        XCTAssertFalse(registry.isConfigured(APIKeySpyProvider.providerId))
        XCTAssertFalse(viewModel.configuredProviderIds.contains(APIKeySpyProvider.providerId))
    }

    func testDisablingPreservesKeyAndRemovesProviderFromPopover() throws {
        let storage = ViewModelKeychainStorage()
        let keychain = Keychain(storage: storage, service: "view-model")
        try keychain.save("saved-key", for: APIKeySpyProvider.providerId)
        ProviderEnablement.setEnabled(true, for: APIKeySpyProvider.providerId)
        let registry = ProviderRegistry(keychain: keychain)
        registry.register(APIKeySpyProvider())
        let viewModel = QuotaViewModel(keychain: keychain, registry: registry)

        XCTAssertTrue(viewModel.configuredProviderIds.contains(APIKeySpyProvider.providerId))

        viewModel.setProviderEnabled(false, for: APIKeySpyProvider.providerId)

        XCTAssertFalse(viewModel.isEnabled(APIKeySpyProvider.providerId))
        XCTAssertEqual(try keychain.load(for: APIKeySpyProvider.providerId), "saved-key")
        XCTAssertFalse(viewModel.configuredProviderIds.contains(APIKeySpyProvider.providerId))

        viewModel.setProviderEnabled(true, for: APIKeySpyProvider.providerId)

        XCTAssertTrue(viewModel.isEnabled(APIKeySpyProvider.providerId))
        XCTAssertTrue(viewModel.configuredProviderIds.contains(APIKeySpyProvider.providerId))
    }

    func testDisabledAPIKeyFreeProviderDoesNotProbeDuringViewModelOrSettingsReads() async {
        let provider = APIKeyFreeSpyProvider()
        let registry = ProviderRegistry()
        registry.register(provider)
        let viewModel = QuotaViewModel(registry: registry)

        _ = viewModel.registeredProvidersOrdered
        _ = viewModel.canInstallHelper(for: APIKeyFreeSpyProvider.providerId)
        _ = viewModel.credentialImportActionTitle(for: APIKeyFreeSpyProvider.providerId)
        await Task.yield()

        XCTAssertFalse(viewModel.isEnabled(APIKeyFreeSpyProvider.providerId))
        XCTAssertEqual(provider.isConfiguredCallCount, 0)
        XCTAssertEqual(provider.setupStateCallCount, 0)
        XCTAssertEqual(provider.fetchCallCount, 0)
        XCTAssertEqual(provider.canInstallCallCount, 0)
    }

    func testDisablingRejectsAnInFlightQuotaResult() async throws {
        let storage = ViewModelKeychainStorage()
        let keychain = Keychain(storage: storage, service: "view-model")
        try keychain.save("saved-key", for: DelayedAPIKeyProvider.providerId)
        ProviderEnablement.setEnabled(true, for: DelayedAPIKeyProvider.providerId)
        let provider = DelayedAPIKeyProvider()
        let registry = ProviderRegistry(keychain: keychain)
        registry.register(provider)
        let viewModel = QuotaViewModel(keychain: keychain, registry: registry)

        for _ in 0 ..< 100 where provider.fetchCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(provider.fetchCallCount, 1)

        viewModel.setProviderEnabled(false, for: DelayedAPIKeyProvider.providerId)
        provider.completeFetch()
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isEnabled(DelayedAPIKeyProvider.providerId))
        XCTAssertFalse(viewModel.configuredProviderIds.contains(DelayedAPIKeyProvider.providerId))
        if case .loaded = viewModel.providerStates[DelayedAPIKeyProvider.providerId] {
            XCTFail("A result that completed after disable must not update state")
        }
    }

    func testDisablingOneProviderLeavesAnotherProviderEnabled() throws {
        let storage = ViewModelKeychainStorage()
        let keychain = Keychain(storage: storage, service: "view-model")
        try keychain.save("first-key", for: APIKeySpyProvider.providerId)
        try keychain.save("second-key", for: SecondaryAPIKeySpyProvider.providerId)
        ProviderEnablement.setEnabled(true, for: APIKeySpyProvider.providerId)
        ProviderEnablement.setEnabled(true, for: SecondaryAPIKeySpyProvider.providerId)
        let registry = ProviderRegistry(keychain: keychain)
        registry.register(APIKeySpyProvider())
        registry.register(SecondaryAPIKeySpyProvider())
        let viewModel = QuotaViewModel(keychain: keychain, registry: registry)

        viewModel.setProviderEnabled(false, for: APIKeySpyProvider.providerId)

        XCTAssertFalse(viewModel.isEnabled(APIKeySpyProvider.providerId))
        XCTAssertTrue(viewModel.isEnabled(SecondaryAPIKeySpyProvider.providerId))
        XCTAssertTrue(viewModel.configuredProviderIds.contains(SecondaryAPIKeySpyProvider.providerId))
    }
}

private final class ViewModelKeychainStorage: KeychainStorage, @unchecked Sendable {
    var data: Data?
    var shouldFailWrites = false

    func readData(
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws -> Data? {
        data
    }

    func replaceData(
        _ data: Data,
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) throws {
        if shouldFailWrites {
            throw KeychainStorageError.status(-1)
        }
        self.data = data
    }

    func delete(
        service _: String,
        account _: String,
        authenticationContext _: KeychainAuthenticationContext
    ) {}
}

private struct APIKeySpyProvider: AIProvider {
    static let providerId = "api-key-spy"
    static let providerName = "API Key Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "Ready",
            lines: [],
            lastUpdated: Date()
        )
    }
}

private struct SecondaryAPIKeySpyProvider: AIProvider {
    static let providerId = "secondary-api-key-spy"
    static let providerName = "Secondary API Key Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "Ready",
            lines: [],
            lastUpdated: Date()
        )
    }
}

private final class DelayedAPIKeyProvider: AIProvider, @unchecked Sendable {
    static let providerId = "delayed-api-key"
    static let providerName = "Delayed API Key"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!

    var fetchCallCount = 0
    private var continuation: CheckedContinuation<ProviderQuota, Never>?

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fetchCallCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func completeFetch() {
        continuation?.resume(
            returning: ProviderQuota(
                providerId: Self.providerId,
                providerName: Self.providerName,
                headline: "Late result",
                lines: [],
                lastUpdated: Date()
            )
        )
        continuation = nil
    }
}

private final class APIKeyFreeSpyProvider: AIProvider, @unchecked Sendable {
    static let providerId = "api-key-free-spy"
    static let providerName = "API Key Free Spy"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let credentialImportActionTitle: String? = "Import credentials"

    var isConfiguredCallCount = 0
    var setupStateCallCount = 0
    var fetchCallCount = 0
    var canInstallCallCount = 0

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
}

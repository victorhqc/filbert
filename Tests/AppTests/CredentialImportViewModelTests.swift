@testable import App
import Core
import Foundation
import XCTest

@MainActor
final class CredentialImportViewModelTests: XCTestCase {
    private let suiteName = "filbert.tests.credential-import-view-model"
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

    func testImportActionRoutesThroughViewModelWithoutProviderIDBranch() async {
        let registry = ProviderRegistry()
        let provider = ImportingTestProvider()
        registry.register(provider)
        ProviderEnablement.setEnabled(true, for: ImportingTestProvider.providerId)
        let viewModel = QuotaViewModel(registry: registry)

        XCTAssertEqual(
            viewModel.credentialImportActionTitle(for: ImportingTestProvider.providerId),
            "Import credentials"
        )

        await viewModel.importCredentials(for: ImportingTestProvider.providerId)

        XCTAssertTrue(provider.importCalled)
    }

    func testUnsupportedProviderDoesNotExposeImportAction() {
        let registry = ProviderRegistry()
        registry.register(UnsupportedTestProvider())
        let viewModel = QuotaViewModel(registry: registry)

        XCTAssertNil(viewModel.credentialImportActionTitle(for: UnsupportedTestProvider.providerId))
    }
}

private final class ImportingTestProvider: AIProvider, @unchecked Sendable {
    static let providerId = "importing-test"
    static let providerName = "Importing Test"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let credentialImportActionTitle: String? = "Import credentials"

    var importCalled = false
    private var configured = false

    func isConfigured() -> Bool {
        configured
    }

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "Ready",
            lines: [],
            lastUpdated: Date()
        )
    }

    func importCredentials() async throws {
        configured = true
        importCalled = true
    }
}

private struct UnsupportedTestProvider: AIProvider {
    static let providerId = "unsupported-test"
    static let providerName = "Unsupported Test"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "Unavailable",
            lines: [],
            lastUpdated: Date()
        )
    }
}

import Core
import XCTest

@MainActor
final class ProviderRegistryProactiveRefreshTests: XCTestCase {
    // MARK: - routes to a conforming provider

    func testProactiveRefresh_routesToConformingProvider() async throws {
        let registry = ProviderRegistry()
        let provider = FakeProactiveRefreshProvider()
        registry.register(provider)

        try await registry.proactiveRefresh(for: FakeProactiveRefreshProvider.providerId)

        XCTAssertTrue(provider.refreshCalled, "proactiveRefresh(for:) must delegate to the conforming provider")
    }

    // MARK: - non-conforming providers throw `.notSupported`

    func testProactiveRefresh_throwsNotSupported_forNonConformingProvider() async {
        let registry = ProviderRegistry()
        registry.register(FakeNonRefreshableProvider())

        do {
            try await registry.proactiveRefresh(for: FakeNonRefreshableProvider.providerId)
            XCTFail("Expected .notSupported")
        } catch ProviderSetupError.notSupported {
            // Expected.
        } catch {
            XCTFail("Expected .notSupported, got \(error)")
        }
    }

    func testProactiveRefresh_throwsNotSupported_forUnknownProvider() async {
        let registry = ProviderRegistry()

        do {
            try await registry.proactiveRefresh(for: "does-not-exist")
            XCTFail("Expected .notSupported")
        } catch ProviderSetupError.notSupported {
            // Expected.
        } catch {
            XCTFail("Expected .notSupported, got \(error)")
        }
    }

    func testCredentialImport_routesToProviderWithoutInspectingItsID() async throws {
        let registry = ProviderRegistry()
        let provider = FakeCredentialImportProvider()
        registry.register(provider)

        XCTAssertEqual(
            registry.credentialImportActionTitle(for: FakeCredentialImportProvider.providerId),
            "Import credentials"
        )
        try await registry.importCredentials(for: FakeCredentialImportProvider.providerId)

        XCTAssertTrue(provider.importCalled)
    }

    func testCredentialImport_isUnavailableForDefaultProvider() async {
        let registry = ProviderRegistry()
        registry.register(FakeNonRefreshableProvider())

        XCTAssertNil(registry.credentialImportActionTitle(for: FakeNonRefreshableProvider.providerId))
        do {
            try await registry.importCredentials(for: FakeNonRefreshableProvider.providerId)
            XCTFail("Expected .notSupported")
        } catch ProviderSetupError.notSupported {
            // Expected.
        } catch {
            XCTFail("Expected .notSupported, got \(error)")
        }
    }
}

// MARK: - Test fixtures

/// `class` so the `refreshCalled` flag can mutate through the registry's
/// stored reference.
private final class FakeProactiveRefreshProvider: AIProvider, ProactiveRefreshable, @unchecked Sendable {
    static let providerId = "fake-refreshable"
    static let providerName = "Fake Refreshable"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    var refreshCalled = false

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "fake",
            lines: [],
            lastUpdated: Date()
        )
    }

    func proactiveRefresh() async throws {
        refreshCalled = true
    }
}

private struct FakeNonRefreshableProvider: AIProvider {
    static let providerId = "fake-non-refreshable"
    static let providerName = "Fake Non-Refreshable"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKey

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "fake",
            lines: [],
            lastUpdated: Date()
        )
    }
}

private final class FakeCredentialImportProvider: AIProvider, @unchecked Sendable {
    static let providerId = "fake-importing-provider"
    static let providerName = "Fake Importing"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let credentialImportActionTitle: String? = "Import credentials"

    var importCalled = false

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "fake",
            lines: [],
            lastUpdated: Date()
        )
    }

    func importCredentials() async throws {
        importCalled = true
    }
}

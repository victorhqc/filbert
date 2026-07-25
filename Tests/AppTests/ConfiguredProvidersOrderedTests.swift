@testable import App
import Core
import XCTest

@MainActor
final class ConfiguredProvidersOrderedTests: XCTestCase {
    func testConfiguredProvidersOrderedExcludesUnconfiguredProviders() {
        let registry = ProviderRegistry()
        registry.register(UnconfiguredAPIKeyProvider())
        registry.register(UnconfiguredAPIKeyFreeProvider())
        registry.register(ConfiguredAPIKeyFreeProvider())

        let viewModel = QuotaViewModel(registry: registry)

        let configuredIds = viewModel.configuredProviderIds
        let configuredOrderedIds = viewModel.configuredProvidersOrdered.map(\.id)

        XCTAssertEqual(configuredOrderedIds, [ConfiguredAPIKeyFreeProvider.providerId])
        XCTAssertEqual(
            configuredOrderedIds,
            configuredIds,
            "configuredProvidersOrdered must match configuredProviderIds"
        )
    }

    func testRegisteredOrderStillContainsUnconfiguredProviders() {
        let registry = ProviderRegistry()
        registry.register(UnconfiguredAPIKeyProvider())
        registry.register(ConfiguredAPIKeyFreeProvider())

        let viewModel = QuotaViewModel(registry: registry)

        let registeredIds = viewModel.registeredProvidersOrdered.map(\.id)
        XCTAssertTrue(registeredIds.contains(UnconfiguredAPIKeyProvider.providerId))
        XCTAssertTrue(registeredIds.contains(ConfiguredAPIKeyFreeProvider.providerId))
    }

    func testConfiguredProvidersOrderedEmptyWhenNothingConfigured() {
        let registry = ProviderRegistry()
        registry.register(UnconfiguredAPIKeyProvider())
        registry.register(UnconfiguredAPIKeyFreeProvider())

        let viewModel = QuotaViewModel(registry: registry)

        XCTAssertTrue(viewModel.configuredProvidersOrdered.isEmpty)
        XCTAssertFalse(viewModel.hasAnyConfiguredProvider)
    }
}

// MARK: - Test fixtures

private struct UnconfiguredAPIKeyProvider: AIProvider {
    static let providerId = "unconfigured-apikey"
    static let providerName = "Unconfigured API Key"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKey

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

private struct UnconfiguredAPIKeyFreeProvider: AIProvider {
    static let providerId = "unconfigured-free"
    static let providerName = "Unconfigured Free"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    func isConfigured() -> Bool {
        false
    }

    func currentSetupState() async -> ProviderState? {
        .setup("Not installed")
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
}

private final class ConfiguredAPIKeyFreeProvider: AIProvider, @unchecked Sendable {
    static let providerId = "configured-free"
    static let providerName = "Configured Free"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    func isConfigured() -> Bool {
        true
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
}

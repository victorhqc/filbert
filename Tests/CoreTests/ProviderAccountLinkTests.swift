import Core
import XCTest

final class ProviderAccountLinkTests: XCTestCase {
    @MainActor
    func testRegistryPreservesProviderOwnedAccountLink() throws {
        let registry = ProviderRegistry()
        registry.register(LinkedProvider())
        registry.register(UnlinkedProvider())

        let linked = try XCTUnwrap(registry.registeredProviders.first { $0.id == "linked" })
        let unlinked = try XCTUnwrap(registry.registeredProviders.first { $0.id == "unlinked" })
        XCTAssertEqual(linked.accountLink, LinkedProvider.accountLink)
        XCTAssertEqual(linked.accountLink?.destination, .account)
        XCTAssertNil(unlinked.accountLink)
    }

    func testProviderInfoDefaultsToNoAccountLink() {
        let info = ProviderInfo(
            id: "test",
            displayName: "Test",
            description: "Test",
            defaultBaseURL: UnlinkedProvider.baseURL,
            authShape: .apiKey
        )
        XCTAssertNil(info.accountLink)
    }
}

private struct LinkedProvider: AIProvider {
    static let providerId = "linked"
    static let providerName = "Linked"
    static let providerDescription = "Linked provider"
    static let baseURL = URL(string: "https://example.com")!
    static let accountLink: ProviderAccountLink? = ProviderAccountLink(
        url: URL(string: "https://example.com/account")!,
        destination: .account
    )

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        throw URLError(.unsupportedURL)
    }
}

private struct UnlinkedProvider: AIProvider {
    static let providerId = "unlinked"
    static let providerName = "Unlinked"
    static let providerDescription = "Unlinked provider"
    static let baseURL = URL(string: "https://example.com")!

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        throw URLError(.unsupportedURL)
    }
}

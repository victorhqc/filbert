import Core
import XCTest

final class ProviderProtocolTests: XCTestCase {
    func testProviderQuota_initializesAllFields() {
        let now = Date()
        let detail = UsageDetail(label: "RPM", value: "42 / 500")
        let line = UsageLine(
            label: "5-hour window",
            used: 420,
            total: 1000,
            percentage: 42,
            unit: "requests",
            resetDate: now.addingTimeInterval(3600),
            details: [detail]
        )
        let quota = ProviderQuota(
            providerId: "test",
            providerName: "Test Provider",
            headline: "42% · resets in 1h",
            lines: [line],
            lastUpdated: now
        )

        XCTAssertEqual(quota.providerId, "test")
        XCTAssertEqual(quota.providerName, "Test Provider")
        XCTAssertEqual(quota.headline, "42% · resets in 1h")
        XCTAssertEqual(quota.lines.count, 1)
        XCTAssertEqual(quota.lines[0].percentage, 42)
        XCTAssertEqual(quota.lines[0].details?.first?.label, "RPM")
        XCTAssertEqual(quota.lastUpdated, now)
        XCTAssertNil(quota.error)
    }

    func testUsageLine_defaultsToNilForOptionalFields() {
        let line = UsageLine(label: "requests")

        XCTAssertEqual(line.label, "requests")
        XCTAssertNil(line.used)
        XCTAssertNil(line.total)
        XCTAssertNil(line.percentage)
        XCTAssertNil(line.unit)
        XCTAssertNil(line.resetDate)
        XCTAssertNil(line.details)
    }

    func testProviderQuota_errorStoresMessage() {
        let quota = ProviderQuota(
            providerId: "test",
            providerName: "Test",
            headline: "Error",
            lines: [],
            lastUpdated: Date(),
            error: "401 Unauthorized"
        )

        XCTAssertEqual(quota.error, "401 Unauthorized")
    }

    func testUsageDetail_roundtripsLabelAndValue() {
        let detail = UsageDetail(label: "RPM", value: "42 / 500")

        XCTAssertEqual(detail.label, "RPM")
        XCTAssertEqual(detail.value, "42 / 500")
    }

    // MARK: - ProviderInfo (ui 05 AC1)

    func testProviderInfo_includesAuthShape() throws {
        let info = try ProviderInfo(
            id: "test",
            displayName: "Test",
            description: "Desc",
            defaultBaseURL: XCTUnwrap(URL(string: "https://example.com")),
            authShape: .apiKeyFree
        )
        XCTAssertEqual(info.id, "test")
        XCTAssertEqual(info.authShape, .apiKeyFree)
        XCTAssertNil(info.disclaimer)
        XCTAssertNil(info.setupHelp)
        XCTAssertNil(info.credentialImportActionTitle)
    }

    func testProviderInfo_authShapeDefaultsToApiKey_whenSetExplicitly() throws {
        let info = try ProviderInfo(
            id: "test",
            displayName: "Test",
            description: "Desc",
            defaultBaseURL: XCTUnwrap(URL(string: "https://example.com")),
            authShape: .apiKey
        )
        XCTAssertEqual(info.authShape, .apiKey)
    }

    func testProviderInfo_storesOptionalSetupHelp() throws {
        let documentationURL = try XCTUnwrap(URL(string: "https://example.com/docs"))
        let setupHelp = ProviderSetupHelp(linkLabel: "Install CLI", url: documentationURL)
        let info = try ProviderInfo(
            id: "test",
            displayName: "Test",
            description: "Desc",
            defaultBaseURL: XCTUnwrap(URL(string: "https://example.com")),
            authShape: .apiKeyFree,
            setupHelp: setupHelp
        )

        XCTAssertEqual(info.setupHelp, setupHelp)
    }

    @MainActor
    func testRegistry_transportsProviderSetupHelp() throws {
        let registry = ProviderRegistry()
        registry.register(SetupHelpProvider())

        let info = try XCTUnwrap(registry.registeredProviders.first)

        XCTAssertEqual(info.setupHelp, SetupHelpProvider.setupHelp)
    }

    @MainActor
    func testRegistry_transportsProviderDisclaimer() throws {
        let registry = ProviderRegistry()
        registry.register(DisclaimerProvider())

        let info = try XCTUnwrap(registry.registeredProviders.first)

        XCTAssertEqual(info.disclaimer, DisclaimerProvider.providerDisclaimer)
    }

    @MainActor
    func testRegistry_transportsCredentialImportActionTitle() throws {
        let registry = ProviderRegistry()
        registry.register(CredentialImportProvider())

        let info = try XCTUnwrap(registry.registeredProviders.first)

        XCTAssertEqual(info.credentialImportActionTitle, CredentialImportProvider.credentialImportActionTitle)
    }

    @MainActor
    func testRegistry_transportsProviderGlyph() throws {
        let registry = ProviderRegistry()
        registry.register(GlyphProvider())

        let info = try XCTUnwrap(registry.registeredProviders.first)
        guard case let .sfSymbol(name) = info.glyph else {
            return XCTFail("Expected an SF Symbol glyph")
        }
        XCTAssertEqual(name, "sparkles")
    }

    func testProviderGlyph_defaultsToNeutralPlaceholder() {
        guard case let .sfSymbol(name) = SetupHelpProvider.providerGlyph else {
            return XCTFail("Expected the default SF Symbol glyph")
        }
        XCTAssertEqual(name, "cpu")
    }

    // MARK: - ProviderSetupError (ui 05)

    func testProviderSetupError_notSupported_isEquatable() {
        XCTAssertEqual(
            ProviderSetupError.notSupported,
            ProviderSetupError.notSupported
        )
    }

    func testProviderSetupError_notSupported_hasLocalizedDescription() {
        let error = ProviderSetupError.notSupported
        XCTAssertFalse(error.localizedDescription.isEmpty)
    }
}

private struct GlyphProvider: AIProvider {
    static let providerId = "glyph-test"
    static let providerName = "Glyph Test"
    static let providerGlyph = ProviderGlyph.sfSymbol("sparkles")
    static let providerDescription = "Test provider"
    static let baseURL = URL(string: "https://example.com")!

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fatalError("The metadata transport test does not fetch quota data.")
    }
}

private struct SetupHelpProvider: AIProvider {
    static let providerId = "setup-help-test"
    static let providerName = "Setup Help Test"
    static let providerDescription = "Test provider"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let setupHelp: ProviderSetupHelp? = ProviderSetupHelp(
        linkLabel: "Install CLI",
        url: URL(string: "https://example.com/docs")!
    )

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        fatalError("The metadata transport test does not fetch quota data.")
    }
}

private struct DisclaimerProvider: AIProvider {
    static let providerId = "disclaimer"
    static let providerName = "Disclaimer"
    static let providerDescription = "Description"
    static let providerDisclaimer: String? = "Undocumented integration"
    static let baseURL = URL(string: "https://example.com")!

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "No data",
            lines: [],
            lastUpdated: Date()
        )
    }
}

private struct CredentialImportProvider: AIProvider {
    static let providerId = "credential-import"
    static let providerName = "Credential Import"
    static let providerDescription = "Description"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree
    static let credentialImportActionTitle: String? = "Import credentials"

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: "No data",
            lines: [],
            lastUpdated: Date()
        )
    }

    func importCredentials() async throws {}
}

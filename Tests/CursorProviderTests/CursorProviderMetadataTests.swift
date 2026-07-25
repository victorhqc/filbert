import Core
@testable import CursorProvider
import Foundation
import XCTest

final class CursorProviderMetadataTests: XCTestCase {
    // MARK: - provider-owned glyph

    func testProviderGlyphLoadsFromModuleResources() {
        guard case let .asset(name, bundle) = CursorProvider.providerGlyph else {
            return XCTFail("Expected an asset-backed provider glyph")
        }

        XCTAssertEqual(name, "ProviderGlyph")
        XCTAssertNotNil(bundle.url(forResource: name, withExtension: "png"))
        XCTAssertNotNil(bundle.url(forResource: "\(name)@2x", withExtension: "png"))
    }

    // MARK: - external login prerequisite

    @MainActor
    func testSetupHelpPointsToCursorCLIAuthenticationDocs() throws {
        let setupHelp = try XCTUnwrap(CursorProvider.setupHelp)
        let registry = ProviderRegistry()
        registry.register(CursorProvider())
        let expectedURL = URL(string: "https://cursor.com/docs/cli/reference/authentication")

        XCTAssertEqual(setupHelp.linkLabel, "Sign in to Cursor")
        XCTAssertEqual(setupHelp.url, expectedURL)
        XCTAssertEqual(registry.registeredProviders.first?.setupHelp, setupHelp)
    }

    func testProviderDescriptionIncludesUndocumentedEndpointDisclaimer() {
        XCTAssertEqual(
            CursorProvider.providerDisclaimer,
            "This provider uses undocumented Cursor endpoints and may stop working if Cursor changes them."
        )
    }

    func testProviderExposesCredentialReimportAction() {
        XCTAssertEqual(CursorProvider.credentialImportActionTitle, "Re-import Cursor credentials")
    }

    // MARK: - setup state

    func testSetupState_missingBinaryAndToken_showsInstallMessage() async {
        let provider = makeProvider(token: nil, binaryExists: false)

        XCTAssertEqual(CursorProvider.authShape, .apiKeyFree)
        XCTAssertFalse(provider.isConfigured())
        guard case let .setup(message) = await provider.currentSetupState() else {
            return XCTFail("Expected setup state")
        }
        XCTAssertEqual(
            message,
            "Cursor CLI not installed — run `agent login`, or sign in to the Cursor app."
        )
    }

    func testSetupState_binaryPresentNoToken_showsSignInMessage() async {
        let provider = makeProvider(token: nil, binaryExists: true)

        XCTAssertFalse(provider.isConfigured())
        guard case let .setup(message) = await provider.currentSetupState() else {
            return XCTFail("Expected setup state")
        }
        XCTAssertEqual(message, "Sign in to Cursor")
    }

    func testSetupState_tokenPresent_isConfiguredWithNoSetupState() async {
        let provider = makeProvider(
            token: CursorTestFixtures.tokenPair(valid: true),
            binaryExists: false
        )

        XCTAssertTrue(provider.isConfigured())
        let state = await provider.currentSetupState()
        XCTAssertNil(state)
    }

    // MARK: - credential removal

    func testRemoveHelper_clearsStoredCredentialsAndReportsUnconfigured() async throws {
        let vault = TestCursorCredentialVault(fields: [
            "accessToken": CursorTestFixtures.tokenPair(valid: true).accessToken,
            "refreshToken": CursorTestFixtures.tokenPair(valid: true).refreshToken,
        ])
        let provider = CursorProvider(
            locator: CursorLocator(
                environment: ["PATH": "/bin", "HOME": "/test"],
                isExecutable: { _ in true }
            ),
            tokenStore: CursorTokenStore(
                vault: vault,
                homeDirectory: "/test",
                externalStorage: ClosureKeychainStorage(),
                readSQLiteValue: { _, _ in nil }
            ),
            session: .shared
        )

        XCTAssertTrue(provider.isConfigured())

        try await provider.removeHelper()

        XCTAssertNil(vault.storedFields())
        XCTAssertEqual(vault.counts().clears, 1)
        XCTAssertFalse(provider.isConfigured())
    }

    // MARK: - idempotent removal

    func testRemoveHelper_isIdempotentWhenVaultEmpty() async throws {
        let vault = TestCursorCredentialVault()
        let provider = CursorProvider(
            locator: CursorLocator(
                environment: ["PATH": "/bin", "HOME": "/test"],
                isExecutable: { _ in true }
            ),
            tokenStore: CursorTokenStore(
                vault: vault,
                homeDirectory: "/test",
                externalStorage: ClosureKeychainStorage(),
                readSQLiteValue: { _, _ in nil }
            ),
            session: .shared
        )

        XCTAssertFalse(provider.isConfigured())

        try await provider.removeHelper()
        try await provider.removeHelper()

        XCTAssertEqual(vault.counts().clears, 2)
        XCTAssertFalse(provider.isConfigured())
    }

    func testSetupState_failedSharedVaultSaveSurfacesKeychainError() async {
        let vault = TestCursorCredentialVault()
        vault.setSaveFailure(true)
        let tokenStore = CursorTokenStore(
            vault: vault,
            homeDirectory: "/test",
            externalStorage: ClosureKeychainStorage(read: { service, _ in
                service == "cursor-access-token" ? "access" : "refresh"
            }),
            readSQLiteValue: { _, _ in nil }
        )
        let provider = CursorProvider(
            locator: CursorLocator(
                environment: ["PATH": "/bin", "HOME": "/test"],
                isExecutable: { _ in true }
            ),
            tokenStore: tokenStore,
            session: .shared
        )

        XCTAssertFalse(provider.isConfigured())
        guard case let .error(message) = await provider.currentSetupState() else {
            return XCTFail("Expected Keychain error state")
        }
        XCTAssertEqual(message, "Unable to access saved Cursor credentials. Check Keychain access and try again.")
    }

    private func makeProvider(token: CursorTokenPair?, binaryExists: Bool) -> CursorProvider {
        let locator = CursorLocator(
            environment: ["PATH": "/bin", "HOME": "/test"],
            isExecutable: { _ in binaryExists }
        )
        let vault = TestCursorCredentialVault(fields: token.map {
            ["accessToken": $0.accessToken, "refreshToken": $0.refreshToken]
        })
        let tokenStore = CursorTokenStore(
            vault: vault,
            homeDirectory: "/test",
            externalStorage: ClosureKeychainStorage(),
            readSQLiteValue: { _, _ in nil }
        )
        return CursorProvider(locator: locator, tokenStore: tokenStore, session: .shared)
    }
}

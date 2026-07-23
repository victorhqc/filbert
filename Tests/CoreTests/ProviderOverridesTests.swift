import Core
import XCTest

final class ProviderOverridesTests: XCTestCase {
    /// Isolated `UserDefaults` so tests don't touch the user's real defaults.
    private let suiteName = "filbert.tests.provider-overrides"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        ProviderOverrides.setUserDefaults(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        ProviderOverrides.setUserDefaults(.standard)
        defaults = nil
        super.tearDown()
    }

    // MARK: - AC4/AC5: round-trip and clearing

    func testBaseURL_returnsNilWhenUnset() {
        XCTAssertNil(ProviderOverrides.baseURL(for: "zai"))
    }

    func testSetBaseURL_persistsAndReadsBack() throws {
        let url = try XCTUnwrap(URL(string: "https://proxy.example.com"))
        try ProviderOverrides.setBaseURL(url, for: "zai")

        XCTAssertEqual(ProviderOverrides.baseURL(for: "zai"), url)
    }

    func testSetBaseURL_nilClearsExistingEntry() throws {
        let url = try XCTUnwrap(URL(string: "https://proxy.example.com"))
        try ProviderOverrides.setBaseURL(url, for: "zai")

        try ProviderOverrides.setBaseURL(nil, for: "zai")

        XCTAssertNil(ProviderOverrides.baseURL(for: "zai"))
    }

    func testSetBaseURL_isIsolatedPerProvider() throws {
        let zai = try XCTUnwrap(URL(string: "https://proxy.zai.example.com"))
        let claude = try XCTUnwrap(URL(string: "https://proxy.claude.example.com"))
        try ProviderOverrides.setBaseURL(zai, for: "zai")
        try ProviderOverrides.setBaseURL(claude, for: "claude")

        XCTAssertEqual(ProviderOverrides.baseURL(for: "zai"), zai)
        XCTAssertEqual(ProviderOverrides.baseURL(for: "claude"), claude)
    }

    // MARK: - AC5: only https is accepted on write

    func testSetBaseURL_rejectsHttp() throws {
        let http = try XCTUnwrap(URL(string: "http://proxy.example.com"))

        XCTAssertThrowsError(try ProviderOverrides.setBaseURL(http, for: "zai")) { error in
            XCTAssertEqual(error as? ProviderOverrideError, .invalidURL)
        }
        XCTAssertNil(ProviderOverrides.baseURL(for: "zai"))
    }

    func testSetBaseURL_rejectsNonHttpSchemes() throws {
        let ftp = try XCTUnwrap(URL(string: "ftp://proxy.example.com"))

        XCTAssertThrowsError(try ProviderOverrides.setBaseURL(ftp, for: "zai")) { error in
            XCTAssertEqual(error as? ProviderOverrideError, .invalidURL)
        }
        XCTAssertNil(ProviderOverrides.baseURL(for: "zai"))
    }

    // MARK: - AC6: invalid stored values fall back to nil (defense in depth)

    func testBaseURL_treatsStoredHttpAsUnsetAndCleansUp() {
        defaults.set("http://proxy.example.com", forKey: "provider-zai-base-url")

        XCTAssertNil(ProviderOverrides.baseURL(for: "zai"))
        // The bad entry is removed so future reads don't keep hitting it.
        XCTAssertNil(defaults.string(forKey: "provider-zai-base-url"))
    }

    func testBaseURL_treatsUnparseableStoredValueAsUnset() {
        defaults.set("not a url", forKey: "provider-zai-base-url")

        XCTAssertNil(ProviderOverrides.baseURL(for: "zai"))
    }

    func testBaseURL_treatsEmptyHostAsUnset() {
        // Scheme but no host: `URL(string:)` accepts this, but it's not a
        // usable proxy address.
        defaults.set("https://", forKey: "provider-zai-base-url")

        XCTAssertNil(ProviderOverrides.baseURL(for: "zai"))
    }
}

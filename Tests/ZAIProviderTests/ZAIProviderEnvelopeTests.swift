import Core
import XCTest
@testable import ZAIProvider

final class ZAIProviderEnvelopeTests: XCTestCase {
    private var errorLog: ErrorLog!
    private var provider: ZAIProvider!

    override func setUp() {
        super.setUp()
        DisplayLanguage.selectedLanguageCode = "en"
        DisplayLanguage.setCurrentLocale { Locale(identifier: "en_US") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        errorLog = ZAIProviderTests.makeErrorLog()
        provider = ZAIProvider(session: URLSession(configuration: configuration), errorLog: errorLog)
    }

    override func tearDown() {
        DisplayLanguage.selectedLanguageCode = nil
        DisplayLanguage.setCurrentLocale { Locale.current }
        MockURLProtocol.handler = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.capturedRequests = []
        provider = nil
        errorLog = nil
        super.tearDown()
    }

    // MARK: - No Coding Plan

    func testNoPlanBodySkipsTheSubscriptionCall() async throws {
        try serve(fixture("quota-no-plan"))

        await assertFetch(throws: .noCodingPlan)
        XCTAssertEqual(MockURLProtocol.capturedRequests.map { $0.url?.path }, ["/api/monitor/usage/quota/limit"])
        XCTAssertNil(errorLog.availableFileURL)
        XCTAssertEqual(
            ZAIError.noCodingPlan.errorDescription,
            "This key has no active GLM Coding Plan. "
                + "For pay-as-you-go balance, use the z.ai API provider with a Standard key."
        )
    }

    func testNoPlanMatchesTheMessageIgnoringCase() async {
        serve(json: #"{"code":500,"msg":"No active Coding Plan for this user","success":false}"#)

        await assertFetch(throws: .noCodingPlan)
    }

    func testCode500WithoutThePhraseIsABusinessFailure() async {
        serve(json: #"{"code":500,"msg":"系统繁忙","success":false}"#)

        await assertFetch(throws: .business(500))
    }

    // MARK: - Authentication

    func testAuthenticationEnvelopesReadAsHTTP401() async throws {
        for (name, code) in [("quota-auth-1000", 1000), ("quota-auth-1001", 1001), ("quota-auth-401", 401)] {
            try serve(fixture(name))

            await assertFetch(throws: .business(code))
        }
        for code in [401, 1000, 1001, 1002] {
            XCTAssertEqual(ZAIError.business(code).errorDescription, "Authentication failed. Check your API key.")
        }
        XCTAssertEqual(ZAIError.http(401).errorDescription, "Authentication failed. Check your API key.")
        XCTAssertNil(errorLog.availableFileURL)
    }

    // MARK: - Other business failures

    func testUnknownBusinessCodeLogsOnlyTheCode() async throws {
        serve(json: #"{"code":1302,"msg":"server-secret-text","success":false}"#)

        await assertFetch(throws: .business(1302))
        XCTAssertEqual(ZAIError.business(1302).errorDescription, "Unexpected response from server.")
        let records = try String(contentsOf: XCTUnwrap(errorLog.availableFileURL), encoding: .utf8)
        XCTAssertEqual(records.split(whereSeparator: \.isNewline).count, 1)
        XCTAssertTrue(records.contains("quota_business_code_1302"))
        XCTAssertFalse(records.contains("server-secret-text"))
    }

    func testSuccessNeedsDataAndNoFalseFlag() async {
        serve(json: #"{"code":200,"msg":"","data":{"limits":[]},"success":false}"#)
        await assertFetch(throws: .business(200))

        serve(json: #"{"code":200,"msg":"","data":null,"success":true}"#)
        await assertFetch(throws: .business(200))
    }

    func testBodyWithoutDataOrCodeIsADecodingError() async {
        serve(json: #"{"msg":"no code","success":false}"#)

        do {
            _ = try await fetch()
            XCTFail("Expected a decoding error")
        } catch let error as ZAIError {
            guard case .decoding = error else {
                return XCTFail("Expected a decoding error, got \(error)")
            }
            XCTAssertEqual(error.errorDescription, "Unexpected response from server.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Success

    func testEmptyLimitsReadAsNoUsageWindows() async throws {
        try serve(fixture("quota-empty-limits"))

        let quota = try await fetch()

        XCTAssertEqual(quota.headline.resolved, "No usage windows reported")
        XCTAssertTrue(quota.lines.isEmpty)
        XCTAssertNil(quota.headlineUsageLineId)
    }

    func testEnvelopeWithoutTheSuccessFlagStillMaps() async throws {
        serve(json: #"{"data":{"limits":[{"type":"TOKENS_LIMIT","unit":3,"percentage":12}]}}"#)

        let quota = try await fetch()

        XCTAssertEqual(quota.lines.map(\.id), ["five-hour-usage"])
        XCTAssertEqual(quota.headline.resolved, "12%")
    }

    // MARK: - Name

    func testProviderIsNamedCodingPlanAndKeepsItsID() async throws {
        try serve(fixture("quota-empty-limits"))

        let quota = try await fetch()

        XCTAssertEqual(ZAIProvider.providerId, "zai")
        XCTAssertEqual(ZAIProvider.providerName, "z.ai Coding Plan")
        XCTAssertEqual(quota.providerName, "z.ai Coding Plan")
        XCTAssertEqual(ZAIProvider.providerDescription, "Monitor GLM Coding Plan quota")
    }

    // MARK: - Helpers

    private func fetch() async throws -> ProviderQuota {
        try await provider.fetchQuota(auth: .apiKey("test-key"), baseURL: ZAIProvider.baseURL)
    }

    private func assertFetch(throws expected: ZAIError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await fetch()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as ZAIError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    private func serve(json: String) {
        serve(Data(json.utf8))
    }

    private func serve(_ quota: Data) {
        MockURLProtocol.handler = { request in
            request.url?.path.hasSuffix("/quota/limit") == true
                ? (200, quota)
                : (200, Data(#"{"code":200,"success":true,"data":[]}"#.utf8))
        }
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json")))
    }
}

import Core
import Foundation
import XCTest

@MainActor
final class ProviderRegistryActivitySignalTests: XCTestCase {
    private let suiteName = "filbert.tests.provider-registry-activity-signals"
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

    func testRoutesSignalsStatusAndSetupToAConformingProvider() async throws {
        let registry = ProviderRegistry()
        let provider = FakeActivitySignalingProvider()
        registry.register(provider)
        ProviderEnablement.setEnabled(true, for: FakeActivitySignalingProvider.providerId)

        let signals = try XCTUnwrap(registry.activitySignals(for: FakeActivitySignalingProvider.providerId))
        let signalTime = Date(timeIntervalSinceReferenceDate: 1000)
        provider.send(signalTime)
        provider.finish()
        var received: [Date] = []
        for await time in signals {
            received.append(time)
        }
        XCTAssertEqual(received, [signalTime])

        let status = await registry.activitySignalStatus(for: FakeActivitySignalingProvider.providerId)
        guard case .awaitingFirstSignal = status else {
            return XCTFail("Expected the provider's status, got \(String(describing: status))")
        }

        try await registry.installActivitySignal(for: FakeActivitySignalingProvider.providerId)
        try await registry.removeActivitySignal(for: FakeActivitySignalingProvider.providerId)
        XCTAssertEqual(provider.installCallCount, 1)
        XCTAssertEqual(provider.removeCallCount, 1)
    }

    func testNonConformingProviderHasNoSignals() async {
        let registry = ProviderRegistry()
        registry.register(FakeQuietProvider())
        ProviderEnablement.setEnabled(true, for: FakeQuietProvider.providerId)

        XCTAssertNil(registry.activitySignals(for: FakeQuietProvider.providerId))
        let status = await registry.activitySignalStatus(for: FakeQuietProvider.providerId)
        XCTAssertNil(status)
        await assertNotSupported { try await registry.installActivitySignal(for: FakeQuietProvider.providerId) }
        await assertNotSupported { try await registry.removeActivitySignal(for: FakeQuietProvider.providerId) }
    }

    func testDisabledProviderHasNoSignals() async {
        let registry = ProviderRegistry()
        let provider = FakeActivitySignalingProvider()
        registry.register(provider)
        ProviderEnablement.setEnabled(false, for: FakeActivitySignalingProvider.providerId)

        XCTAssertNil(registry.activitySignals(for: FakeActivitySignalingProvider.providerId))
        let status = await registry.activitySignalStatus(for: FakeActivitySignalingProvider.providerId)
        XCTAssertNil(status)
        await assertNotSupported {
            try await registry.installActivitySignal(for: FakeActivitySignalingProvider.providerId)
        }
        XCTAssertEqual(provider.installCallCount, 0)
    }

    func testUnknownProviderHasNoSignals() async {
        let registry = ProviderRegistry()

        XCTAssertNil(registry.activitySignals(for: "does-not-exist"))
        await assertNotSupported { try await registry.installActivitySignal(for: "does-not-exist") }
    }

    private func assertNotSupported(
        _ action: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await action()
            XCTFail("Expected .notSupported", file: file, line: line)
        } catch ProviderSetupError.notSupported {
            return
        } catch {
            XCTFail("Expected .notSupported, got \(error)", file: file, line: line)
        }
    }
}

private final class FakeActivitySignalingProvider: AIProvider, ActivitySignaling, @unchecked Sendable {
    static let providerId = "fake-activity-signaling"
    static let providerName = "Fake Activity Signaling"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    private var continuation: AsyncStream<Date>.Continuation?
    var installCallCount = 0
    var removeCallCount = 0

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: DisplayText(verbatim: "fake"),
            lines: [],
            lastUpdated: Date()
        )
    }

    func activitySignals() -> AsyncStream<Date> {
        let (stream, continuation) = AsyncStream<Date>.makeStream()
        self.continuation = continuation
        return stream
    }

    func activitySignalStatus() async -> ActivitySignalStatus {
        .awaitingFirstSignal(nil)
    }

    func installActivitySignal() async throws {
        installCallCount += 1
    }

    func removeActivitySignal() async throws {
        removeCallCount += 1
    }

    func send(_ time: Date) {
        continuation?.yield(time)
    }

    func finish() {
        continuation?.finish()
    }
}

private final class FakeQuietProvider: AIProvider, @unchecked Sendable {
    static let providerId = "fake-quiet"
    static let providerName = "Fake Quiet"
    static let providerDescription = "Test fixture"
    static let baseURL = URL(string: "https://example.com")!
    static let authShape: ProviderAuth.Shape = .apiKeyFree

    func fetchQuota(auth _: ProviderAuth, baseURL _: URL) async throws -> ProviderQuota {
        ProviderQuota(
            providerId: Self.providerId,
            providerName: Self.providerName,
            headline: DisplayText(verbatim: "quiet"),
            lines: [],
            lastUpdated: Date()
        )
    }
}

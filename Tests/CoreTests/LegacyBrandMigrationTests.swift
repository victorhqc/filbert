@testable import Core
import XCTest

final class LegacyBrandMigrationTests: XCTestCase {
    private var destinationDomain: String!
    private var sourceDomain: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        destinationDomain = "filbert.tests.brand-migration.\(UUID().uuidString)"
        sourceDomain = "legacy.tests.brand-migration.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: destinationDomain))
        defaults.removePersistentDomain(forName: destinationDomain)
        defaults.removePersistentDomain(forName: sourceDomain)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: destinationDomain)
        defaults.removePersistentDomain(forName: sourceDomain)
        defaults = nil
        sourceDomain = nil
        destinationDomain = nil
        super.tearDown()
    }

    func testMigratePreferencesCopiesOnlyKnownValuesAndRemovesSourceDomain() throws {
        defaults.setPersistentDomain(
            [
                "provider-order": ["zai", "deepseek"],
                "provider-zai-base-url": "https://proxy.example.com",
                "balance-thresholds-low": 7.0,
                "provider-collapse-state": ["zai": true],
                "vintage-mac-icon-enabled": true,
                "unrelated-value": "leave behind",
            ],
            forName: sourceDomain
        )

        try LegacyBrandMigration.migratePreferences(
            sourceDomainName: sourceDomain,
            destination: defaults,
            providerIds: ["zai"]
        )

        XCTAssertEqual(defaults.array(forKey: "provider-order") as? [String], ["zai", "deepseek"])
        XCTAssertEqual(
            defaults.string(forKey: "provider-zai-base-url"),
            "https://proxy.example.com"
        )
        XCTAssertEqual(defaults.double(forKey: "balance-thresholds-low"), 7)
        XCTAssertEqual(
            defaults.dictionary(forKey: "provider-collapse-state") as? [String: Bool],
            ["zai": true]
        )
        XCTAssertTrue(defaults.bool(forKey: "vintage-mac-icon-enabled"))
        XCTAssertNil(defaults.object(forKey: "unrelated-value"))
        XCTAssertNil(defaults.persistentDomain(forName: sourceDomain))
    }

    func testMigratePreferencesKeepsExistingFilbertValues() throws {
        defaults.set(["deepseek", "zai"], forKey: "provider-order")
        defaults.setPersistentDomain(
            ["provider-order": ["zai", "deepseek"]],
            forName: sourceDomain
        )

        try LegacyBrandMigration.migratePreferences(
            sourceDomainName: sourceDomain,
            destination: defaults,
            providerIds: ["zai", "deepseek"]
        )

        XCTAssertEqual(defaults.array(forKey: "provider-order") as? [String], ["deepseek", "zai"])
        XCTAssertNil(defaults.persistentDomain(forName: sourceDomain))
    }

    func testMigratePreferencesIsIdempotent() throws {
        defaults.setPersistentDomain(
            ["balance-thresholds-ok": 25.0],
            forName: sourceDomain
        )

        try LegacyBrandMigration.migratePreferences(
            sourceDomainName: sourceDomain,
            destination: defaults,
            providerIds: []
        )
        try LegacyBrandMigration.migratePreferences(
            sourceDomainName: sourceDomain,
            destination: defaults,
            providerIds: []
        )

        XCTAssertEqual(defaults.double(forKey: "balance-thresholds-ok"), 25)
    }
}

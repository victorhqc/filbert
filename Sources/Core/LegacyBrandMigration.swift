import Foundation

public enum LegacyBrandMigration {
    public static func migratePreferences(providerIds: [String]) throws {
        try migratePreferences(
            sourceDomainName: LegacyBrandIdentifiers.bundleIdentifier,
            destination: .standard,
            providerIds: providerIds
        )
    }

    static func migratePreferences(
        sourceDomainName: String,
        destination: UserDefaults,
        providerIds: [String]
    ) throws {
        guard let source = destination.persistentDomain(forName: sourceDomainName) else {
            return
        }

        let keys = preferenceKeys(providerIds: providerIds)
        var copiedKeys = Set<String>()
        for key in keys where destination.object(forKey: key) == nil {
            guard let value = source[key] else { continue }
            destination.set(value, forKey: key)
            copiedKeys.insert(key)
        }

        for key in copiedKeys {
            guard let destinationValue = destination.object(forKey: key),
                  let sourceValue = source[key],
                  valuesMatch(sourceValue, destinationValue)
            else {
                throw LegacyBrandMigrationError.preferenceVerificationFailed(key)
            }
        }

        destination.removePersistentDomain(forName: sourceDomainName)
    }

    private static func preferenceKeys(providerIds: [String]) -> [String] {
        [
            "provider-order",
            "balance-thresholds-low",
            "balance-thresholds-ok",
            "provider-collapse-state",
            "vintage-mac-icon-enabled",
        ] + providerIds.map { "provider-\($0)-base-url" }
    }

    private static func valuesMatch(_ lhs: Any, _ rhs: Any) -> Bool {
        NSDictionary(dictionary: ["value": lhs]).isEqual(to: ["value": rhs])
    }
}

enum LegacyBrandIdentifiers {
    static let bundleIdentifier = "com.victorhqc.ai-usage"
    static let keychainService = "ai-usage"
}

public enum LegacyBrandMigrationError: Error, Equatable {
    case preferenceVerificationFailed(String)
}

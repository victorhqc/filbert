## Objective

Retire the one-time Keychain consolidation migration and the Core preferences
branding migration now that they have served their purpose.

## Context

- `Sources/Core/Keychain.swift` — `migrateStore`, `mergeMigrationItems`,
  `legacyConsolidatedStore`, `migrationItems`, the `previousService` /
  `legacyAccountPrefix` properties, the `[String: String]` fallback +
  `isLegacy` in `decodeStore`, and `KeychainError.migrationFailed` are all
  migration-only; they exist to land (core 04 AC2, AC3) and are dead weight
  afterwards.
- `Sources/Core/KeychainStorage.swift` — `StoredKeychainItem` and
  `KeychainStorage.readLegacyItems` (protocol requirement +
  `SecurityKeychainStorage` impl) exist only to feed the per-provider item
  scan inside `migrateStore`.
- `Sources/Core/LegacyBrandMigration.swift` — the whole file
  (`LegacyBrandMigration`, `LegacyBrandIdentifiers`,
  `LegacyBrandMigrationError`) is the one-time `com.victorhqc.ai-usage` →
  current bundle-id preferences rename.
- `Sources/App/AppMain.swift` (L22–30) — the `do/catch` block that calls
  `LegacyBrandMigration.migratePreferences(providerIds:)` in `init()`; it is
  the only call site and goes away with the migration.
- `Tests/CoreTests/LegacyBrandKeychainMigrationTests.swift` and
  `Tests/CoreTests/LegacyBrandMigrationTests.swift` — migration coverage to
  delete; `Tests/CoreTests/KeychainTests.swift` references
  `.migrationFailed` and needs trimming.
- Non-migration behavior of (core 04) is unchanged: the consolidated
  field-map API (AC1), in-place update-or-create with read-back verify and
  restore-on-failure (AC3), and Cursor's shared-vault read / bootstrap /
  re-import (AC4, AC7) all stay.
- Out of scope: the ClaudeCode provider's own brand migration
  (`Sources/Providers/ClaudeCode/LegacyBrandMigration.swift`,
  `StatuslineHelperInstaller`'s `migrateLegacy*` / `hasLegacy*` /
  `removeLegacyArtifacts`). It is provider-local, still reachable through
  (providers 02) setup paths, and mixing it into a Core cleanup would
  violate provider orthogonality (AGENTS.md §1). Track it under its own
  provider-scoped spec if desired.

## Acceptance Criteria

### AC1: Keychain loads the consolidated item directly, with no migration path

- **Given** the `filbert` / `providers` item holds a
  `[String: [String: String]]` payload (or no item exists yet)
- **When** any provider calls `Keychain.load` / `loadFields` / `save` /
  `delete`
- **Then** the store is decoded from the current service and account only,
  with no read of any other service, no per-provider item scan, and no
  payload rewrite on first load
- **And** an absent item yields an empty in-memory store (as today), and
  the first `save` creates it

### AC2: Legacy Keychain payloads surface as a typed error, not a migration or crash

- **Given** the `filbert` / `providers` item still holds a pre-(core 04)
  `[String: String]` payload, or a stale `ai-usage` service item, or a
  `provider-<id>` item exists
- **When** the Keychain is loaded
- **Then** the current item either decodes or throws
  `KeychainError.loadFailed(...)`; the app never prompts for a legacy
  service, never scans for per-provider items, and never deletes anything
- **And** the user recovers through the normal setup flow — re-entering an
  API key or triggering Cursor's re-import (core 04 AC7) — without data
  loss beyond the already-stale pre-migration secret

### AC3: Migration code is gone from Core's Keychain layer

- **Given** the change lands
- **When** inspecting `Sources/Core/Keychain.swift` and
  `Sources/Core/KeychainStorage.swift`
- **Then** none of `migrateStore`, `mergeMigrationItems`,
  `legacyConsolidatedStore`, `migrationItems`, `previousService`,
  `legacyAccountPrefix`, `ConsolidatedStore.isLegacy`,
  `KeychainError.migrationFailed`, `KeychainStorage.readLegacyItems`,
  `SecurityKeychainStorage.readLegacyItems`, or `StoredKeychainItem` exist
- **And** `decodeStore` decodes only `[String: [String: String]]`
- **And** `Keychain` no longer references `LegacyBrandIdentifiers`

### AC4: The preferences branding migration is fully removed

- **Given** the change lands
- **When** inspecting `Sources/Core/LegacyBrandMigration.swift` and
  `Sources/App/AppMain.swift`
- **Then** the file `Sources/Core/LegacyBrandMigration.swift` is deleted
  (including `LegacyBrandMigration`, `LegacyBrandIdentifiers`, and
  `LegacyBrandMigrationError`)
- **And** the `do/catch` block calling
  `migratePreferences(providerIds:)` in `AppMain.init()` is gone, so
  startup proceeds straight from provider registration to
  `QuotaViewModel` construction
- **And** no remaining production code references any of the removed
  symbols

### AC5: Non-migration Keychain behavior is unchanged

- **Given** the change lands
- **When** providers save / load / delete API keys, save / load Cursor
  field maps, Cursor refresh updates only its access-token field, or a
  save fails mid-write
- **Then** behavior matches (core 04 AC1, AC3, AC6, AC8): field-map round
  trips preserve every other provider's fields, in-place update-or-create
  with read-back verification still runs, a failed save restores the prior
  item and leaves the in-memory cache intact, and Cursor's shared-vault
  read / bootstrap / re-import path is untouched

### AC6: Tests reflect the removal and keep non-migration coverage

- **Given** the completed implementation
- **When** `swift test` runs
- **Then** `Tests/CoreTests/LegacyBrandKeychainMigrationTests.swift` and
  `Tests/CoreTests/LegacyBrandMigrationTests.swift` are deleted
- **And** `Tests/CoreTests/KeychainTests.swift` no longer references
  `.migrationFailed` (the case no longer exists)
- **And** the non-migration assertions that lived in
  `LegacyBrandKeychainMigrationTests` (field-map round trip preserving
  other providers, failed-update preservation, create-failure and
  verify-failure restoration) survive — relocated into
  `KeychainTests.swift` if not already covered elsewhere — so AC5 keeps
  coverage
- **And** `swift build` and the full `swift test` suite pass with no
  warnings

## Plan

1. **Simplify `Keychain.readStore`.** Return the current payload directly
   (or an empty store when the item is absent). Delete `migrateStore`,
   `mergeMigrationItems`, `legacyConsolidatedStore`, `migrationItems`,
   the `previousService` and `legacyAccountPrefix` properties, and the
   `previousService` init parameter. In `decodeStore`, keep only the
   `[String: [String: String]]` branch and drop `isLegacy` from
   `ConsolidatedStore`. Remove `KeychainError.migrationFailed`.
2. **Drop the migration seam from `KeychainStorage`.** Remove
   `readLegacyItems` from the protocol and the
   `SecurityKeychainStorage` implementation, and delete
   `StoredKeychainItem`. `InMemoryKeychainStorage` in the tests loses the
   same method.
3. **Remove the branding migration.** Delete
   `Sources/Core/LegacyBrandMigration.swift` and the `migratePreferences`
   `do/catch` block in `AppMain.init()`.
4. **Update tests.** Delete the two migration test files; trim
   `KeychainTests.testKeychainError_casesExist` to the remaining cases;
   move any non-migration safety assertions (AC5 behavior) into
   `KeychainTests.swift` where they are not already covered.

No production code is written until this spec is reviewed.

## Risks

- **Stragglers lose silent migration.** A user who has not launched Filbert
  since before (core 04) still carries a `[String: String]` payload or an
  `ai-usage` item. After this change they see a load error / empty store
  and must re-enter keys or re-import Cursor credentials (AC2). That is
  the explicit cost of retiring the migration; confirm it is acceptable
  before implementing, and call it out in release notes. Mitigation: the
  failure is typed and non-destructive, and Cursor recovers via its
  existing re-import action (core 04 AC7).
- **The consolidated item is the only supported payload.** Removing the
  schema fallback means a corrupt or hand-edited item is no longer papered
  over by a re-migration; it surfaces as `loadFailed`. Acceptable, but
  worth a release-note line.
- **Provider orthogonality.** The ClaudeCode provider's brand migration
  (helper/cache rename) is deliberately out of scope. Bundling it would
  mix a provider change into a Core cleanup (AGENTS.md §1); track it
  separately.
- **Test relocation.** Several assertions in
  `LegacyBrandKeychainMigrationTests` cover non-migration safety netted by
  AC5. They must survive the file deletion, or AC5 loses coverage.

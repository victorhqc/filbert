## Objective

Store Cursor OAuth tokens in Filbert's single consolidated Keychain item so, after its one-time import, normal Cursor use shares the other providers' authorization path instead of prompting on every refresh.

## Context

- `Sources/Core/Keychain.swift` — already caches the single `filbert` / `providers` item, but its `[String: String]` payload can represent only one secret per provider.
- `Sources/Core/KeychainStorage.swift` — must update an existing Keychain item without deleting its old value first, so schema migration cannot lose every provider secret.
- `Sources/Providers/Cursor/CursorTokenStore.swift` — currently reads Cursor-owned Keychain entries each time configuration or quota fetching needs a token, which repeats macOS authorization prompts.
- `Sources/Providers/Cursor/CursorProvider.swift` — owns Cursor setup, importing, session refresh, and reporting an expired session.
- `Sources/Core/ProviderProtocol.swift` and `Sources/Core/ProviderRegistry.swift` — need a provider-ID-neutral, optional credential-import capability for user-requested Cursor re-imports; the registry must not branch on `"cursor"` (core 03 AC8).
- `Sources/App/QuotaViewModel.swift` and `Sources/App/SettingsView.swift` — surface an optional re-import action through the existing API-key-free settings presentation without changing other providers' controls.
- `Tests/CoreTests/LegacyBrandKeychainMigrationTests.swift` — covers the existing service and per-provider migration and must be extended for the new payload schema.
- `Tests/CursorProviderTests/CursorTokenStoreTests.swift` — covers Cursor token lookup and refresh behavior specified by (providers 07 AC4, AC5).
- This supersedes the external-Keychain read and write portions of (providers 07 AC4, AC5) while retaining Cursor's Keychain-then-SQLite source order for the one-time import.

## Acceptance Criteria

### AC1: One consolidated, extensible secret payload

- **Given** Filbert has one or more stored provider secrets
- **When** `Keychain` serializes its `filbert` service / `providers` account
- **Then** the payload is one JSON object keyed by provider ID whose value is a string-field map, such as `{"zai":{"value":"…"},"cursor":{"accessToken":"…","refreshToken":"…"}}`
- **And** Core treats the field names and values as opaque provider-owned data; it contains no Cursor-specific type, field name, or branch
- **And** the existing `save(_:for:)` and `load(for:)` APIs remain available and map an API key to the `value` field, so API-key providers and the registry behave unchanged (core 03 AC4)
- **And** Core exposes field-map save/load operations for providers that need multiple related secrets, and they preserve fields belonging to every other provider

### AC2: Existing provider secrets migrate without loss

- **Given** a user has an existing `filbert` or legacy-brand consolidated JSON payload encoded as `[String: String]`, legacy `provider-<id>` items, or a combination of those forms
- **When** `Keychain` first loads the store after this change
- **Then** every existing string secret is represented as `{"value":"<original secret>"}` in the new consolidated payload
- **And** the precedence and cleanup rules for legacy-brand and current-service per-provider items remain unchanged (core 01)
- **And** `Keychain.load(for:)` returns the same API-key strings before and after migration
- **And** an unreadable payload, failed write, or failed post-write verification returns a typed `KeychainError` and leaves every pre-migration item intact

### AC3: Updating the consolidated Keychain item cannot erase secrets

- **Given** the `filbert` / `providers` Keychain item already exists
- **When** Core saves a migrated store, an API key, or Cursor credential fields
- **Then** the Keychain storage updates that item in place and only creates it when it is absent
- **And** it does not delete the existing item before a successful update or successful creation has been confirmed
- **And** a failed save neither changes the in-memory cache nor removes unrelated provider fields

### AC4: Cursor imports external credentials once into the shared vault

- **Given** the shared `cursor` field map is absent
- **When** Cursor performs its initial credential bootstrap or the user explicitly requests a re-import
- **Then** it reads the first complete pair from Cursor Agent Keychain layouts, falling back to Cursor Desktop SQLite exactly as in (providers 07 AC4)
- **And** it writes the access token and refresh token together into the shared `cursor` field map before reporting Cursor as configured
- **And** a successful import makes no modification to Cursor-owned Keychain entries or `state.vscdb`
- **And** an incomplete pair, unavailable external source, malformed shared record, or a failed shared-vault save leaves Cursor unconfigured and surfaces a short actionable setup or Keychain error without logging either token

### AC5: Normal Cursor operation never re-reads Cursor-owned stores

- **Given** the shared vault contains a complete Cursor token pair
- **When** Cursor runs `isConfigured()`, resolves setup state, fetches usage, performs its five-minute automatic refresh, or the user manually refreshes
- **Then** it reads only Filbert's cached consolidated Keychain item and never calls `SecItemCopyMatching` for a Cursor-owned service or opens Cursor's SQLite database
- **And** all concurrent callers share one import attempt, so a missing shared record cannot create multiple simultaneous Cursor Keychain prompts
- **And** a successful shared-vault read is cached by the existing `Keychain` lock for the app session, yielding at most one macOS prompt for Filbert's own item per launch

### AC6: Refresh updates only the shared Cursor fields

- **Given** Cursor refreshes an expired or near-expiry access token using its stored refresh token
- **When** `/oauth/token` returns a new valid access token
- **Then** Cursor updates `cursor.accessToken` in Filbert's consolidated item and retains `cursor.refreshToken`
- **And** it never writes the refreshed token to any Cursor-owned Keychain service or SQLite database
- **And** all other providers' secret fields remain byte-for-byte unchanged in the decoded store
- **And** existing session-expired, client-ID-rejected, rate-limit, and network error behavior remains intact (providers 07 AC5, AC10, AC11)

### AC7: Re-import is deliberate and provider-neutral

- **Given** an API-key-free provider supports importing credentials from an external local source
- **When** the Settings UI presents its setup or error state
- **Then** Core offers an optional provider capability for a user-requested credential import, with a default unsupported implementation for every existing provider
- **And** the registry, view model, and settings row route that capability generically rather than checking a provider ID (core 03 AC8)
- **And** Cursor exposes a localized re-import action that is the only way to re-read external Cursor stores after a failed bootstrap or an expired shared session
- **And** while the explicit action runs, the Settings row shows its existing working state; a successful import starts the normal refresh flow and a failure restores an actionable setup or error state

### AC8: No regression for other providers or secret handling

- **Given** the feature lands
- **When** non-Cursor providers save, load, delete, configure, and fetch
- **Then** their public Keychain calls, authentication routing, network requests, and settings behavior are unchanged (core 03)
- **And** the Cursor provider still depends only on `Core`, with no cross-provider dependency (providers 07)
- **And** plaintext tokens never enter `UserDefaults`, logs, error descriptions, SQLite files written by Filbert, or memory caches beyond the time needed for a request or Keychain mutation

### AC9: The behavior is covered by focused tests

- **Given** the completed implementation
- **When** the Core and Cursor test suites run
- **Then** Core tests cover new-payload round trips, legacy `[String: String]` conversion, mixed legacy-service migration, update failure, create failure, verification failure, and preservation of unrelated provider fields
- **And** Cursor tests prove a shared pair bypasses both external stores, each external source is imported only once, concurrent initial loads cause one external read and one shared save, SQLite fallback imports correctly, and refresh updates only the shared access-token field
- **And** Settings and registry tests prove only an importing provider exposes the re-import action, invoking it reaches that provider without an ID branch, and unsupported providers retain their current UI
- **And** `swift build` and the full `swift test` suite pass with no warnings

## Plan

1. [x] **Generalize Core's secret value.** Replace the internal `[String: String]` payload with a provider-ID → string-field-map store. Preserve `save(_:for:)`, `load(for:)`, and `delete(for:)` as API-key conveniences, and add a generic field-map API that does not encode provider semantics.
2. [x] **Make storage migration safe.** Decode the structured payload first, then fall back to the old consolidated string map and the existing legacy-item migration. Change the Security storage replacement to update-or-create, verify the written payload, and retain the old item and cache on failure.
3. [x] **Consolidate Cursor credentials.** Give `CursorTokenStore` an injected shared-vault adapter plus a lock-protected import state. It loads a valid shared pair first; only an absent pair triggers a single Keychain-first/SQLite-second bootstrap, and a successful bootstrap persists the complete pair before use. Remove the direct external-Keychain write path.
4. [x] **Persist refreshes centrally.** Have the token refresh path replace only the access-token field in the shared pair and preserve the refresh token and all non-Cursor records.
5. [x] **Add the generic re-import seam.** Define an optional credential-import protocol or equivalent capability in Core, route it through `ProviderRegistry` and `QuotaViewModel`, and render its action in `APIKeyFreeSettingsRow`. Cursor implements it; all other providers use the default unsupported behavior.
6. [x] **Test migration, prompt avoidance, and recovery.** Extend the Core in-memory Keychain storage tests and Cursor dependency-injection tests with read/write counters, concurrent callers, and failure fixtures. Add registry/view-model/UI coverage for the generic re-import route.

No production code is written until this spec is reviewed.

## Risks

- **Schema migration protects every provider at once.** The consolidated item contains all saved secrets, so a faulty update could affect more than Cursor. In-place update, decode/verify-before-cleanup, and migration failure tests are mandatory.
- **Initial import may still require authorization.** macOS may ask once when Filbert first reads Cursor's existing Keychain item. That is unavoidable, but it happens only during bootstrap or an explicit re-import, never every refresh or setup check.
- **Imported session can expire.** Filbert must not silently fall back to repeated external reads after an OAuth failure. The explicit re-import action gives the user a controlled recovery path after signing in to Cursor again.
- **External token layouts may change.** Cursor Agent's Keychain services/accounts and the Desktop SQLite schema remain undocumented. Import failure must remain a setup error, not crash the app or erase an already imported pair.
- **API-key-free UI is shared.** The optional action must not make Claude Code or Codex appear to support credential import; the capability is queried generically and defaults to unavailable.

## Objective

Make Keychain migration, Cursor credential import, and API-key saves use one recoverable authentication path without repeated prompts or hidden failures.

## Context

- `Sources/Core/KeychainStorage.swift` — its all-items lookup combines `kSecReturnData` with `kSecMatchLimitAll`, which Security does not permit for generic-password items.
- `Sources/Core/Keychain.swift` — migration currently enumerates both services even after a valid current structured store has loaded, creating unnecessary authenticated reads.
- `Sources/Providers/Cursor/CursorTokenStore.swift` — bootstrap probes two token layouts as four independent Keychain reads and treats every Security status as an absent record.
- `Sources/Providers/Cursor/CursorCredentialVault.swift` — converts Core Keychain failures into Cursor setup errors and must preserve their actionable distinction.
- `Sources/App/SettingsView.swift` and `Sources/App/QuotaViewModel.swift` — API-key save and clear actions currently discard errors with `try?`, leaving the user with an apparent no-op.
- Corrects the runtime behavior required by (core 04) while retaining Cursor's source order and ownership rules from (providers 07).

## Acceptance Criteria

### AC1: Valid current stores never trigger a migration scan

- **Given** `filbert` / `providers` contains a valid structured provider-field-map payload written by (core 04)
- **When** any provider loads, saves, deletes, or refreshes credentials after the app's first Keychain access
- **Then** Core reads only that exact consolidated item before serving its in-memory cache
- **And** it does not enumerate either the current or legacy-brand service, inspect a `provider-*` item, or access a Cursor-owned item
- **And** an authentication failure from an unrelated legacy item cannot prevent an API-key provider from loading or saving its own value

### AC2: Legacy migration uses legal, minimal Keychain queries

- **Given** the current consolidated item is missing or is the legacy `[String: String]` payload, and legacy per-provider items may exist
- **When** Core performs its one-time migration
- **Then** it first lists item metadata without requesting secret data for all matches
- **And** it reads secret data only for identified `provider-*` accounts needed by the migration
- **And** it preserves the precedence, decode, in-place update, verification, and cleanup guarantees from (core 04 AC2, AC3)
- **And** an unavailable or denied legacy secret produces a typed, actionable migration error without changing the current consolidated item

### AC3: One authentication context covers a single credential operation

- **Given** a Keychain operation needs local authentication
- **When** Core migrates, verifies a write, or Cursor performs a deliberate import
- **Then** all Security queries in that one operation share a reusable local authentication context
- **And** one successful authentication is reused for the operation's subsequent permitted reads
- **And** a user cancellation, denial, or Keychain error ends that operation without additional layout probes or retries
- **And** no password, API key, OAuth token, or authentication-context diagnostic is written to logs, preferences, or app-managed files

### AC4: Cursor import distinguishes absence from access failure

- **Given** Cursor's shared record is absent and the user starts initial bootstrap or presses re-import
- **When** Cursor checks its Agent Keychain layouts and SQLite fallback in the established order (providers 07 AC4)
- **Then** a missing item advances to the next supported source, while an authentication failure is reported as a short Keychain-access error and stops the attempt
- **And** a complete pair from either supported Keychain layout requires at most one user authentication prompt for that import attempt
- **And** an initial or explicit import that succeeds saves the complete pair to Filbert's shared vault and leaves Cursor-owned stores unchanged
- **And** normal Cursor configuration, fetch, manual refresh, and automatic refresh still never re-read Cursor-owned stores (core 04 AC5)

### AC5: API-key saves report failures and preserve user input

- **Given** a user enters a Z.ai, DeepSeek, or other API-provider key in Settings
- **When** a consolidated Keychain save or delete fails
- **Then** Settings shows a concise localized Keychain error on that provider row instead of silently discarding the failure
- **And** a failed save leaves the entered key in the secure field, does not mark the provider configured, and does not start a fetch or refresh loop
- **And** a successful retry clears the input and error, records the new key, and starts the existing fetch flow

### AC6: Tests exercise the real failure boundaries

- **Given** this correction is complete
- **When** Core, Cursor, and App tests run
- **Then** Core tests prove structured stores bypass every migration enumeration, legacy discovery never combines all-items matching with secret-data return, failed legacy reads preserve all items, and unrelated legacy failures cannot block a current structured store
- **And** Cursor tests prove absent and denied external items differ, an authentication failure stops later layout probes, and all reads in one import receive the same reusable authentication context
- **And** Settings and view-model tests prove a failed API-key save retains input and surfaces an error, while a successful retry follows the existing configured flow
- **And** a manual macOS Keychain smoke test records one prompt for a successful Cursor import and a successful save for both Z.ai and DeepSeek
- **And** `swift build` and the full `swift test` suite pass with no warnings

## Plan

1. [x] Replace the illegal all-items secret-data query with metadata discovery followed by exact reads of only legacy provider accounts.
2. [x] Treat a valid structured consolidated store as migration-complete, so normal reads and saves never scan legacy services.
3. [x] Introduce an operation-scoped local authentication context in the Keychain adapter and pass it through Cursor's explicit external import reads.
4. [x] Preserve typed Security statuses through Cursor's external reader so absence, cancellation, denial, malformed data, and shared-vault write failures have distinct recovery behavior.
5. [x] Make API-key row actions report Keychain errors and retain input on failed saves without logging a secret.
6. [x] Add focused mocks that assert query shape, legacy-read isolation, shared authentication context, and Settings retry behavior.
7. [ ] Perform the macOS Keychain smoke test before release.

## Risks

- A current structured store must not be mistaken for an unfinished migration, or legacy scans and their prompts will continue after the upgrade.
- The local authentication context must be short-lived and confined to the operation; it must not become a token cache or suppress a later, legitimate macOS authorization decision.
- Cursor's Keychain layouts are undocumented; the fallback ordering must remain intact while refusing to hide an access-denied status as a missing credential.
- The Settings row must never render, log, or retain a plaintext API key outside SwiftUI's secure-field state needed for the retry.

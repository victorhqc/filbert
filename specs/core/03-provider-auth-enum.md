## Objective

Generalize the `AIProvider.fetchQuota` signature so a provider can be backed
by either an API key in the Keychain or some other authentication shape,
replacing the implicit "every provider has a stored secret" assumption with
an explicit `ProviderAuth` enum.

## Context

- `Sources/Core/ProviderProtocol.swift` — gains the `ProviderAuth` enum and
  updates `fetchQuota` from `(apiKey: String, baseURL: URL)` to
  `(auth: ProviderAuth, baseURL: URL)`. Today (core 01 AC2) + (core 02 AC2)
  bake in a `String` API key; that breaks the moment a provider has no key
  at all (providers 02).
- `Sources/Core/ProviderRegistry.swift` — `fetchAll()` and
  `isConfigured(_:)` currently assume `Keychain.load(for:)` is meaningful
  for every provider. They must stop, and route on the auth shape.
- `Sources/Core/Keychain.swift` — unchanged. Still the storage for
  `.apiKey(String)` providers (AGENTS.md §3); `.apiKeyFree` providers never
  touch it.
- `Sources/Providers/ZAI/ZAIProvider.swift` — updates its method signature
  to the new shape. Behavior is identical: it extracts the string from
  `.apiKey` and proceeds as in (providers 01). `baseURL` handling (core 02)
  is unchanged.
- `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift` — the first
  `.apiKeyFree` consumer; specified in (providers 02).
- This is the protocol contract change that unblocks (providers 02). The
  contract change and the new provider land together in one commit to keep
  `swift build` green.
- Orthogonality (AGENTS.md §1, core 01) is preserved: the registry may
  branch on the auth shape, but never on a provider ID.

## Acceptance Criteria

### AC1: `ProviderAuth` enum with two cases
- **Given** the change lands
- **When** a consumer inspects `ProviderAuth`
- **Then** it is a `Sendable` enum with `case apiKey(String)` and
  `case apiKeyFree`
- **And** it carries no other cases — future auth shapes (e.g. OAuth tokens
  in our own Keychain entry) get their own case under a separate spec, not
  bolted on as a Stringly-typed field

### AC2: `fetchQuota` takes `ProviderAuth`, not a raw `String`
- **Given** a provider type conforming to `AIProvider`
- **When** it declares `fetchQuota`
- **Then** the signature is
  `func fetchQuota(auth: ProviderAuth, baseURL: URL) async throws -> ProviderQuota`
- **And** the old `fetchQuota(apiKey:baseURL:)` signature is gone — there is
  no transitional overload, no default value for `apiKey`

### AC3: ZAI receives `.apiKey`, behavior unchanged
- **Given** `ZAIProvider` after the change
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it pattern-matches `case .apiKey(let key)` and uses `key`
  identically to today — same header value, same URL, same response mapping
  as (providers 01) and (core 02 AC8)
- **And** if `auth` is `.apiKeyFree` it throws a typed internal-consistency
  error, since the registry never routes that shape to ZAI

### AC4: Registry loads the Keychain only for `.apiKey` providers
- **Given** a registered provider
- **When** `fetchAll()` dispatches a fetch
- **Then** the registry inspects the provider's auth shape via a new
  `static var authShape: ProviderAuth.Shape` (a non-payload discriminator —
  `.apiKey` or `.apiKeyFree`)
- **And** when the shape is `.apiKey`, it loads the key from `Keychain` and
  passes `.apiKey(key)` into `fetchQuota`, exactly as today
- **And** when the shape is `.apiKeyFree`, it skips `Keychain.load`
  entirely and passes `.apiKeyFree` — no Keychain read, no Keychain entry,
  no failure path when no key exists

### AC5: `isConfigured` no longer keys off the Keychain alone
- **Given** a provider ID
- **When** the registry checks `isConfigured(_:)`
- **Then** for `.apiKey` providers it returns whether a Keychain entry
  exists, exactly as today (ui 02 AC3)
- **And** for `.apiKeyFree` providers it delegates to the provider's own
  `isConfigured()` method — the provider owns what "configured" means for
  its auth shape (e.g. for Claude Code: binary locatable + helper
  installed, per (providers 02 AC3))

### AC6: `.apiKeyFree` providers expose their setup state via an async method
- **Given** a `.apiKeyFree` provider whose configuration state depends on
  filesystem or environment checks (binary present, helper installed, cache
  file written)
- **When** the view model needs the current setup state — at app launch,
  after install/uninstall, or before deciding whether to fetch
- **Then** it calls `func currentSetupState() async -> ProviderState?` on
  the provider, never reading the provider's storage locations itself
- **And** the method is `async` so providers can do filesystem checks
  (`FileManager.fileExists`, parsing `~/.claude/settings.json`, PATH
  lookups) off the main actor — synchronous checks would block the UI at
  launch and after every install/uninstall action
- **And** the default extension returns `nil`, so `.apiKey` providers are
  never asked for setup state — they have no setup beyond the Keychain
  key, which `isConfigured` already handles synchronously
- **And** the returned `ProviderState` may use a new `setup(String)` case
  carrying a human-readable reason ("Claude Code not found", "Helper not
  installed") — distinct from `.unconfigured` (which today implies "enter
  an API key") and from `.error` (which implies "something broke")
- **And** the registry fans these calls out via `withTaskGroup` at launch
  (same pattern as `fetchAll`), so multiple `.apiKeyFree` providers resolve
  concurrently without serializing on the main actor

### AC7: The auth shape discriminator never carries a payload
- **Given** `ProviderAuth.Shape` (or equivalent) used by the registry
- **When** the registry branches on it
- **Then** it is a plain case discriminator — `.apiKey` vs `.apiKeyFree` —
  not the `ProviderAuth` enum itself (which carries a `String` payload)
- **And** this keeps the registry's routing decision payload-free, so
  there is no way for the registry to inspect a key it should not see

### AC8: Orthogonality holds
- **Given** the change lands with both `ZAIProvider` and `ClaudeCodeProvider`
  registered
- **When** the registry dispatches fetches
- **Then** no code path branches on a provider ID string — every branch is
  on `authShape`, preserving (ui 02 AC9)
- **And** adding a third `.apiKey` provider in the future requires only
  `static var authShape = .apiKey` plus the existing `Keychain` plumbing —
  no further registry edits

### AC9: Swift package compiles with the new contract
- **Given** a fresh checkout after the change
- **When** running `swift build`
- **Then** the project compiles with zero errors and zero warnings,
  including `ZAIProvider` updated to the new `fetchQuota(auth:baseURL:)`
  signature and `ClaudeCodeProvider` adopting it as the first
  `.apiKeyFree` consumer

## Plan

1. **Core: `ProviderAuth` + `ProviderAuth.Shape`.** Define the enum and a
   nested non-payload discriminator. `Shape` exists so the registry can
   route without ever materializing a key. [ ]
2. **Core: protocol change.** Update `AIProvider.fetchQuota` to take
   `auth: ProviderAuth`. Add `static var authShape: ProviderAuth.Shape` with
   a default `.apiKey`. Add `func isConfigured() -> Bool` with a default
   `true`. Both defaults mean existing `.apiKey` providers need zero
   changes beyond the method signature. [ ]
3. **Core: protocol methods + `ProviderState.setup`.** Add `static var
   authShape: ProviderAuth.Shape` with a default `.apiKey`. Add `func
   currentSetupState() async -> ProviderState?` with a default `nil`
   (per AC6 — `.apiKey` providers opt out by returning `nil`). Add `func
   isConfigured() -> Bool` with a default `true`. Extend `ProviderState`
   with a `setup(String)` case for `.apiKeyFree` providers to report
   human-readable setup reasons ("Claude Code not found", "Helper not
   installed") — this lives in Core because `currentSetupState()` is a
   Core protocol method and must return a value Core can construct. All
   defaults mean existing `.apiKey` providers need zero changes beyond
   the `fetchQuota` signature. [ ]
4. **Core: registry routing.** In `isConfigured(_:)` and `fetchAll()`,
   read `authShape` and branch: `.apiKey` → Keychain path (unchanged),
   `.apiKeyFree` → provider's own `isConfigured()` + pass `.apiKeyFree`
   into `fetchQuota`. The branches live in Core; no provider ID is read.
   Add a `refreshSetupStates() async -> [String: ProviderState]` entry
   point that fans `currentSetupState()` out via `withTaskGroup` for every
   registered `.apiKeyFree` provider, so the view model can call it at
   launch and after install/uninstall without blocking. [ ]
4. **Provider: ZAI.** Update `fetchQuota` to the new signature. Extract the
   string from `.apiKey` and proceed identically to today. Assert the
   internal-consistency case where `.apiKeyFree` is routed to ZAI (it
   never happens, but the switch must be exhaustive). [ ]
5. **Provider: Claude Code.** Implemented in (providers 02). It overrides
   `authShape` to `.apiKeyFree` and `isConfigured()` to its binary + helper
   check. [ ]
6. **Tests.**
   - `ProviderRegistryTests` — for a registered `.apiKey` provider,
     `fetchAll` reads the Keychain exactly once and passes `.apiKey(...)`.
     For a registered `.apiKeyFree` provider, `Keychain.load` is never
     called (verified by a Keychain stub that fails on any call), and
     `provider.isConfigured()` is consulted instead.
   - `ProviderRegistryTests` — `refreshSetupStates()` invokes
     `currentSetupState()` on every registered `.apiKeyFree` provider
     concurrently, returns `nil` for every `.apiKey` provider, and never
     blocks the calling actor when at least one provider does filesystem
     work (verified by injecting a provider stub that sleeps before
     returning).
   - `ZAIProviderTests` — the existing suite still passes against the new
     signature; the new internal-consistency assertion for `.apiKeyFree`
     throws as expected; `currentSetupState()` returns `nil`.
   - The Claude Code tests live under (providers 02) and exercise the
     `.apiKeyFree` end of the contract, including `currentSetupState()`'s
     three states (binary missing, helper missing, helper installed).
7. **`Package.swift`.** No structural changes for this spec — the new
   provider module arrives with (providers 02). This spec only changes
   existing files. [ ]

No code is written until this spec is reviewed.

## Risks

- **Source-breaking protocol change.** Every existing provider must adopt
  the new `fetchQuota(auth:baseURL:)` signature at once. Today that's only
  ZAI, so the blast radius is one file, but the change must land together
  with (providers 02) — a half-applied state where the protocol changed but
  ZAI didn't would break `swift build`. This is the explicit cost of doing
  the cleanup now instead of layering capability flags; the alternative was
  deferred debt that would only compound as more auth shapes arrived.
- **Two types in the protocol where there used to be one.** `ProviderAuth`
  + `ProviderAuth.Shape` is a small type graph, and the registry branches
  on `Shape` rather than `ProviderAuth` itself. This is deliberate — it
  keeps the registry's routing decision payload-free — but it means a
  future contributor has to read both types to understand the contract.
  The trade-off is documented in AC7.
- **`isConfigured()` for `.apiKey` providers is dead code.** The default
  extension returns `true` but is never called for those providers because
  the registry routes them through the Keychain path. Same caveat applies
  to `currentSetupState()` returning `nil` for `.apiKey` providers — the
  registry never calls it. A contributor might wrongly assume either is
  authoritative. Mitigation: doc comments on both default extensions
  pointing at AC5/AC6/AC7.
- **Future auth shapes will require more cases.** When a real OAuth provider
  arrives (not Claude Code, which sidesteps OAuth entirely), `ProviderAuth`
  gains a `case oauthTokens(OAuthTokens)` and `Shape` gains `.oauth`. That
  is the intended growth path — each new auth shape is an additive case,
  not a new side flag — but it does mean every existing provider's
  `fetchQuota` switch needs an exhaustive case for the new shape (almost
  always an internal-consistency throw). Accepted as the cost of
  exhaustiveness over Stringly-typed discrimination.
- **ZAI behavior must stay byte-identical.** The change is "what type
  carries the key", nothing else. (providers 01 AC1) request shape,
  header value, and response mapping are untouched; the ZAI test suite
  must pass unchanged against the new signature.

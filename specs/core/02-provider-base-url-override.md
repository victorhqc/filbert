## Objective

Give every provider a default base URL while letting the user override it
per provider with a custom domain (proxy), so requests can be routed through
a self-hosted or corporate proxy without changing provider code.

## Context

- `Sources/Core/ProviderProtocol.swift` — the `AIProvider` protocol gains a
  default `baseURL` requirement and the instance fetch signature gains a
  `baseURL` parameter (core 01 AC2). This is the contract change every
  provider compiles against.
- `Sources/Core/ProviderRegistry.swift` — `fetchAll()` already loads the API
  key per provider before calling `fetchQuota` (core 01 AC4, ui 02 Plan 1).
  It now also loads the per-provider override URL (if any) and passes it
  through.
- `Sources/Core/Keychain.swift` — unchanged. Custom URLs are **not** secrets;
  they are stored in `UserDefaults`, not the Keychain (section 3 of
  `AGENTS.md` — only API keys live in the Keychain).
- `Sources/Providers/ZAI/ZAIProvider.swift` — today hard-codes
  `https://api.z.ai/api/monitor/usage/quota/limit` (providers 01). It must
  move its known default behind `static var baseURL` and resolve the request
  URL from the override when one is supplied.
- Builds on the orthogonal provider architecture in (core 01): adding the
  override must not let one provider's URL logic leak into another, and the
  App layer must not branch on provider ID (ui 02 AC9).
- The Settings UI for editing the override is specced separately under `ui/`;
  this spec covers the Core contract and storage only.

## Acceptance Criteria

### AC1: `AIProvider` declares a default base URL
- **Given** a provider type conforming to `AIProvider`
- **When** it is registered
- **Then** it supplies a `static var baseURL: URL` pointing at its official
  production host (e.g. `URL(string: "https://api.z.ai")!`), and the value
  is the **host root**, not a full endpoint path — path segments stay inside
  the provider's `fetchQuota` implementation

### AC2: `fetchQuota` receives the effective base URL
- **Given** a registered provider with or without a user override
- **When** the registry calls fetch
- **Then** it calls `fetchQuota(apiKey:baseURL:)` where `baseURL` is the
  override URL when one is set, otherwise the provider's `static var baseURL`
- **And** the provider never reads the override itself — it just uses the URL
  it was handed, keeping override resolution in Core

### AC3: Override is optional and defaults to off
- **Given** a freshly installed app
- **When** the user configures a provider key without touching advanced
  options
- **Then** no override URL exists for that provider and every request goes to
  the provider's `static var baseURL` — behavior is identical to today

### AC4: Override is stored per provider in `UserDefaults`
- **Given** a provider ID (e.g. `"zai"`)
- **When** the user saves a custom URL for it
- **Then** it is persisted under a namespaced key (e.g.
  `provider-zai-base-url`) in `UserDefaults` on the app group, **not** in the
  Keychain
- **And** saving is a pure overwrite; clearing means removing the key entirely
  (no empty-string sentinel)

### AC5: Core exposes typed accessors for the override
- **Given** a need to read or write the override from App code
- **When** the App layer touches it
- **Then** it goes through a Core API (e.g. `ProviderOverrides.baseURL(for:)`
  / `.setBaseURL(_:for:)`), never through raw `UserDefaults` string keys — so
  the storage shape can change without breaking the App layer
- **And** `setBaseURL` rejects any URL whose scheme is not `https` (throws
  on write); proxies are expected to be TLS, full stop

### AC6: Invalid stored override falls back to the default, never crashes
- **Given** a stored override that fails to parse, has an empty host, or is
  not `https` (e.g. left over from a manual edit or a future schema change)
- **When** a fetch is attempted for that provider
- **Then** the override is treated as unset and the provider's
  `static var baseURL` is used, with a diagnostic log line — the fetch must
  not crash and must not surface a confusing "invalid URL" error to the UI
  when a working default exists

### AC7: Adding a new provider requires no override-specific code
- **Given** a new provider module conforming to `AIProvider`
- **When** it is registered
- **Then** it inherits override support for free — it only declares
  `static var baseURL` and uses the `baseURL` parameter in `fetchQuota`; no
  App-layer branches, no per-provider storage code, preserving the
  orthogonality rule in section 0 of `AGENTS.md` and (ui 02 AC9)

### AC8: ZAIProvider uses the effective base URL
- **Given** `ZAIProvider` after the change
- **When** `fetchQuota(apiKey:baseURL:)` runs
- **Then** the request URL is `<baseURL>/api/monitor/usage/quota/limit`,
  where `<baseURL>` is the parameter value (default
  `https://api.z.ai` when unset, custom proxy when overridden)
- **And** no other behavior of `ZAIProvider` (auth header shape, response
  mapping, headline computation in (providers 01)) changes

### AC9: Swift package compiles with the new contract
- **Given** a fresh checkout after the change
- **When** running `swift build`
- **Then** the project compiles with zero errors and zero warnings, including
  every existing provider module updating to the new `fetchQuota` signature

## Plan

1. **Core: protocol change.** Add `static var baseURL: URL { get }` to
   `AIProvider` and change the instance method to
   `func fetchQuota(apiKey: String, baseURL: URL) async throws -> ProviderQuota`.
   This is a source-breaking change to provider modules — accepted because
   every provider must take a position on its default host anyway. [x]
2. **Core: `ProviderOverrides` helper.** A small `enum` (no instances) backed
   by `UserDefaults` exposing `baseURL(for providerId: String) -> URL?` and
   `setBaseURL(_ url: URL?, for providerId: String)`. Empty host / non-`https`
   URLs are rejected on write and on read (defense in depth). [x]
3. **Core: registry threading.** In `fetchAll()`, before calling
   `provider.fetchQuota`, load the override via `ProviderOverrides.baseURL(for:)`
   and fall back to `type(of: provider).baseURL`. Pass the resolved URL into
   `fetchQuota(apiKey:baseURL:)`. [x]
4. **Provider: `ZAIProvider`.** Add `static let baseURL = URL(string: "https://api.z.ai")!`
   and update `fetchQuota` to take `baseURL`, building the request URL from it.
   The hardcoded string in (providers 01) disappears. [x]
5. **Tests.** Add Core unit tests covering: a valid `https` override reaches
   `fetchQuota`; `setBaseURL` rejects `http`/non-`https` schemes on write;
   an invalid/empty/non-`https` stored override falls back to the default
   without throwing. A ZAIProvider test asserts the request URL is built from
   the `baseURL` argument. [x]
6. No `Package.swift` changes (no new module, no new dependency). [x]

No code is written until this spec is reviewed.

## Risks

- **Source-breaking protocol change.** Every provider must adopt the new
  `fetchQuota` signature at once. Today only `ZAIProvider` exists, so the
  blast radius is small, but the contract change should land in one commit
  to keep `swift build` green.
- **Override URL validity vs. reachability.** AC6 only guarantees a valid
  URL is used; it does **not** guarantee the proxy is up or that it speaks
  the upstream's wire format. A proxy that returns 200 with a different body
  shape will surface as a decode error in the provider's existing error
  path — that's the provider's responsibility to report, not Core's.
- **`UserDefaults` is not encrypted.** This is intentional — the base URL is
  not a secret. If a future proxy setup expects a path that embeds a token,
  that token must **not** live in the URL override; it would need its own
  Keychain-backed field under a separate spec.
- **Existing z.ai behavior.** `ZAIProvider`'s request shape, auth header, and
  response mapping (providers 01) must stay byte-identical when no override
  is set. The change is "where does the host come from", nothing else.

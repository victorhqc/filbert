## Objective

Add a `CursorProvider` that reads Cursor subscription + on-demand spend from
the user's locally stored Cursor auth token and displays the current billing
cycle usage as `ProviderQuota` lines.

## Context

- `Sources/Providers/Cursor/CursorProvider.swift` — new module; the HTTP +
  decoding + mapping implementation. Mirrors the `.apiKeyFree` shape of
  `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` (providers 05) and
  the token-fetch ergonomics of `Sources/Providers/DeepSeek/DeepSeekProvider.swift`
  (providers 04).
- `Sources/Providers/Cursor/CursorLocator.swift` — new; locates the user's
  Cursor CLI binary (`cursor` / `cursor-agent` / `agent`) without invoking a
  shell, mirroring Codex's `CodexLocator` (providers 05 AC1).
- `Sources/Providers/Cursor/CursorTokenStore.swift` — new; reads the Cursor
  access/refresh token pair from the two supported local sources, refreshes a
  short-lived JWT when needed, and persists the refreshed access token back to
  the same source. See Plan step 4.
- `Sources/Providers/Cursor/Resources/Localizable.xcstrings` — new; provider
  labels ("Included usage", "On-demand spend", "Bonus credits", …) following
  the String Catalog pattern from (providers 01 AC7). Locales seeded: `en`,
  `de-DE`, `es-ES`, `es-MX` — the four languages the rest of the app ships.
- `Sources/Providers/Cursor/Resources/ProviderGlyph.png` +
  `ProviderGlyph@2x.png` — new; monochrome, license-safe glyph drawn rather
  than pasted, following (ui 12)'s precedent and (ui 14 AC1)'s asset contract.
- `Sources/Core/ProviderProtocol.swift` — unchanged. The existing
  `ProviderQuota` / `UsageLine` / `UsageDetail` model already covers both the
  percentage-with-reset (plan usage) and cents-amount (on-demand spend)
  shapes Cursor reports (core 01 AC1). No protocol change required.
- `Sources/Core/ProviderOverrides.swift` — unchanged. Per-provider base-URL
  override (proxy) is inherited for free (core 02 AC7).
- `Package.swift` — gains a `CursorProvider` target depending on `Core`, a
  matching `CursorProviderTests` target, and is added to the `App`
  executable's dependency list.
- `Sources/App/AppMain.swift` — gains one line:
  `registry.register(CursorProvider())`. No other App-layer change
  (core 02 AC7, ui 02 AC9).
- **Cursor's auth and data model (as of 2026-07):**
  - Cursor has **no public, documented usage API and no developer platform.**
    There is no OAuth app registration a third-party app can go through.
    This provider therefore uses the **undocumented, reverse-engineered**
    surface that Cursor's own dashboard and CLI use. It can change without
    notice; the provider treats it defensively.
  - Two parallel auth surfaces exist; this provider uses the **Bearer token**
    surface (not the `cursor.com` web session cookie):
    - **`api2.cursor.sh`** — Connect-RPC-style endpoints, bearer auth:
      `POST /aiserver.v1.DashboardService/GetCurrentPeriodUsage` returns
      plan usage + on-demand spend + billing window; `…/GetPlanInfo` returns
      plan name, price, and included amount.
    - **`cursor.com/api/usage-summary`** — cookie-session-only (returns 401
      without `WorkosCursorSessionToken`). **Out of scope** for this spec;
      the web session cookie is not available without scraping the browser.
  - The access token is a **short-lived JWT**. It is refreshed via
    `POST https://api2.cursor.sh/oauth/token` with
    `grant_type=refresh_token`, the stored refresh token, and the
    **first-party `client_id`** `KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB`.
  - **`client_id` provenance (important).** This id is **Cursor's own
    first-party CLI/desktop client id**, hardcoded in the Cursor binary and
    extracted by reverse-engineering — it is **not** a client id filbert
    registered, because Cursor offers no developer program to register one.
    Filbert is therefore impersonating Cursor's official client on the
    refresh path. Two consequences:
    - **Rotation risk.** If Cursor rotates this id, filbert's refresh stops
      working (HTTP error on `/oauth/token`) and the provider must be
      updated. The `client_id` is isolated in one constant
      (`Sources/Providers/Cursor/CursorAuth.swift`) so a rotation is a
      one-line change + release. AC11 covers surfacing a clear
      "Session expired — provider needs an update" error when this happens.
    - **ToS / opt-in.** This is a hack, not a blessed integration. AC12 adds
      a one-line disclaimer in Settings → Cursor so the user opts in
      knowingly.
  - Tokens live locally in two places (read in this order):
    1. **Cursor CLI Keychain** — service `cursor-agent`, accounts
       `cursor-access-token` / `cursor-refresh-token`. Populated by
       `agent login` (the Cursor CLI).
    2. **Cursor Desktop SQLite** —
       `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
       `ItemTable` keys `cursorAuth/accessToken` /
       `cursorAuth/refreshToken`. Populated by the Cursor desktop app.
  - Amounts are **cents** (divide by 100 for dollars). Timestamps are
    **unix milliseconds as strings**.
  - This is a **credit/percentage hybrid**, not a CLI-statusline shape:
    `individualUsage.plan` carries `used`/`limit`/`remaining` (request-style
    counters) plus `totalPercentUsed`, while `individualUsage.onDemand` and
    the new `planUsage.totalSpend`/`includedSpend`/`bonusSpend` carry dollar
    cents. The provider surfaces both.

## Phases

This spec is delivered in two phases. Phase 1 is **icon + translations** (no
runtime behaviour — the provider is not registered). Phase 2 is the **code
implementation** that wires the assets from Phase 1 into a live provider.

- **Phase 1 — Image generation + translations (AC1–AC3).** Ships the glyph
  PNGs and the String Catalog so a designer/translator pass can land
  independently of the Swift work. Ends with a compiling package that adds the
  `CursorProvider` target shell but does not register it in `AppMain`.
- **Phase 2 — Code implementation (AC4–AC10).** Implements token loading,
  refresh, the `GetCurrentPeriodUsage` call, decoding, mapping to
  `ProviderQuota`, and registration in `AppMain`.

## Acceptance Criteria

### Phase 1 — Image generation + translations

### AC1: License-safe provider glyph ships as a resource
- **Given** the `CursorProvider` target exists
- **When** the package is built
- **Then** `Sources/Providers/Cursor/Resources/ProviderGlyph.png` and
  `ProviderGlyph@2x.png` are present, monochrome, and drawn (not a pasted
  official brand raster) per (ui 12)'s license-safety precedent
- **And** `providerGlyph` returns
  `ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)` so (ui 14 AC1)
  renders it without an App-layer ID branch

### AC2: String Catalog is seeded with all user-facing keys
- **Given** the new `Localizable.xcstrings`
- **When** the keys are enumerated
- **Then** it contains, at minimum, English entries for: provider description
  ("Monitor subscription and on-demand spend"), "Included usage", "Bonus
  credits", "On-demand spend", "Plan", "Pooled spend", "Billing cycle",
  "%@ left", "%@ used of %@", the `%@ / %@` ratio, "No usage reported",
  "No data", "Rate limited", "Authentication failed", "Session expired",
  "Session expired — this provider needs an update",
  "This provider uses undocumented Cursor endpoints and may stop working if
  Cursor changes them.",
  "Sign in to Cursor",
  "Cursor CLI not installed — run `agent login`, or sign in to the Cursor app."

### AC2b: Setup-help link points at the `agent login` prerequisite
- **Given** `CursorProvider.setupHelp` is read by the Settings UI
- **When** the user is in Settings → Cursor and no local token exists
- **Then** the row shows a `ProviderSetupHelp` link whose label is the
  localized "Sign in to Cursor" and whose URL is the Cursor CLI login docs
  (the `agent login` instructions), so the user has a clear path to create
  the session filbert reads — mirroring how Codex points at its CLI docs
  (ui 13)
- **And** because filbert cannot perform the login itself (there is no
  Cursor developer platform to register an OAuth app with), the link is the
  only setup affordance — there is no in-app browser flow

### AC3: All non-English locales are present and translated
- **Given** the app ships locales `en`, `de-DE`, `es-ES`, `es-MX`
- **When** the String Catalog is checked
- **Then** every key from AC2 has a `translated` unit in `de-DE`, `es-ES`, and
  `es-MX` (no stale `new` state), matching the coverage the other providers
  ship (providers 01 AC7; App/Core/ZAI catalogs are the reference)

### Phase 2 — Code implementation

### AC4: Token is read from Cursor's local stores, Keychain first
- **Given** `CursorTokenStore.load()` runs
- **When** both stores are inspected
- **Then** it prefers the `cursor-agent` Keychain entries
  (`cursor-access-token` / `cursor-refresh-token`) when present
- **And** it falls back to the Cursor Desktop SQLite `state.vscdb` keys
  `cursorAuth/accessToken` / `cursorAuth/refreshToken` when the Keychain has
  no entries
- **And** when neither source has a token it returns `nil` without throwing
- **And** the app never reads browser cookies, the web `WorkosCursorSessionToken`,
  or any other user's Keychain entries (core 03 AC4)

### AC4b: Cursor CLI binary is located without a shell
- **Given** the provider is initialized
- **When** `CursorLocator.resolve()` runs
- **Then** it returns the absolute path to the first executable `cursor` /
  `cursor-agent` / `agent` binary found through the process environment's
  `PATH`, followed by known macOS install locations (Homebrew, `/usr/local/bin`,
  the Cursor desktop app's bundled CLI)
- **And** when no executable is found it returns `nil` without throwing, mirroring
  Codex's `CodexLocator` (providers 05 AC1)
- **And** a present-but-not-logged-in binary is reported separately from a
  missing binary so the Settings link can target install vs. sign-in

### AC5: Short-lived JWT is refreshed transparently before fetch
- **Given** a token pair was loaded and the access token's `exp` claim is in
  the past (or within a 60-second skew window)
- **When** `CursorTokenStore.ensureValidAccessToken()` runs
- **Then** it POSTs to `https://api2.cursor.sh/oauth/token` with
  `grant_type=refresh_token`, the stored refresh token, and the first-party
  `client_id` constant from `CursorAuth.swift`
  (`KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB`)
- **And** it persists the new access token back to the same source it was read
  from (Keychain entry or SQLite row)
- **And** when the refresh response sets `shouldLogout: true` (or returns an
  empty access token) the provider throws a typed `.sessionExpired` error that
  surfaces the localized "Session expired" message instructing the user to run
  `agent login`

### AC6: Authenticated Connect-RPC call to the usage endpoint
- **Given** a valid access token
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it issues `POST <baseURL>/aiserver.v1.DashboardService/GetCurrentPeriodUsage`
  with `Authorization: Bearer <accessToken>`, `Content-Type: application/json`,
  and `Connect-Protocol-Version: 1`
- **And** the request body is `{}`
- **And** `<baseURL>` is the resolved parameter value (default
  `https://api2.cursor.sh`, custom proxy when overridden) — the provider never
  reads the override itself (core 02 AC2)

### AC7: Plan usage maps to percentage + reset `UsageLine`s
- **Given** a `200` response with `planUsage` (or the legacy
  `individualUsage.plan` shape)
- **When** the provider decodes it
- **Then** it produces an "Included usage" `UsageLine` with `percentage` from
  `totalPercentUsed`, `used`/`total` from `includedSpend`/`limit` (cents →
  dollars), `unit` set to `"USD"`, and `resetDate` from `billingCycleEnd`
- **And** when `bonusSpend` is present and positive, a "Bonus credits"
  `UsageLine` is added with `used`/`total` from `bonusSpend` and the same
  `resetDate`
- **And** optional `autoPercentUsed` / `apiPercentUsed` become `UsageDetail`
  rows on the "Included usage" line
- **And** tolerant decoding ignores unknown enum values and missing optional
  fields rather than throwing

### AC8: On-demand and pooled spend map to currency `UsageLine`s
- **Given** `spendLimitUsage` is present (individual or team)
- **When** the provider maps it
- **Then** an "On-demand spend" `UsageLine` is added with `used`/`total` from
  `individualUsed`/`individualLimit` (cents → dollars), `unit` `"USD"`
- **And** when `pooledLimit` is present (team plans), a "Pooled spend"
  `UsageLine` is added from `pooledUsed`/`pooledRemaining`
- **And** absent or `limit == 0` on-demand data produces no line (not an
  error and not a zero-row)

### AC9: Headline summarizes the plan cycle, currency-aware
- **Given** decoded usage data with a finite plan `limit`
- **When** the headline is built
- **Then** it reads `"<symbol><remaining> left"` (e.g. `"$42.50 left"`),
  formatted via `NumberFormatter(currencyCode:)` so the symbol and decimals
  follow the user's locale
- **And** `resetDate` is rendered with `QuotaFormatting.countdown(to:)` so the
  user sees the window reset (providers 01 AC5)
- **And** when the plan is unlimited (`isUnlimited == true`) the headline reads
  the localized "Unlimited"
- **And** when the payload carries no usable plan data the headline falls back
  to the localized "No data" (mirrors providers 01 AC5 fallback pattern)

### AC10: Failures surface as typed errors, never fake data
- **Given** no local token, a non-`200` status (401/403/429/5xx), a network
  failure, or an undecodable body
- **When** `fetchQuota` runs
- **Then** it throws a typed `CursorError` (`.missingToken`, `.sessionExpired`,
  `.http(Int)`, `.network`, `.decoding`) so the registry records `.failure`
  (core 01 AC4) and no placeholder quota is returned
- **And** `429` maps to the localized "Rate limited"; `401`/`.sessionExpired`
  to "Authentication failed" / "Session expired" (mirrors providers 01 AC6)
- **And** `isConfigured()` returns `true` when either a Cursor token pair is
  locatable in either store **or** the Cursor CLI binary is present on the
  machine (core 03 AC5); a missing token + missing binary yields a `.setup`
  state with the actionable message from AC2
  ("Cursor CLI not installed — run `agent login`, or sign in to the Cursor app.")
  and the Settings row surfaces the install link (core 03 AC6)
- **And** the setup check distinguishes the two unconfigured cases so the link
  matches the user's situation: binary missing → install link; binary present
  but no token → "Sign in to Cursor" link (the `agent login` prerequisite)

### AC11: A rotated `client_id` produces a clear, actionable error
- **Given** Cursor rotates its first-party `client_id` (so the constant in
  `CursorAuth.swift` is now stale)
- **When** the refresh path runs
- **Then** a failed refresh (HTTP 4xx on `/oauth/token`, or
  `shouldLogout: true`, or an empty access token) is mapped to a distinct
  `CursorError.clientIdRejected` case — not a generic network error
- **And** the surfaced message reads the localized
  "Session expired — this provider needs an update" so the user knows the
  failure is app-side and expected, not a bad password
- **And** the constant lives in one place
  (`Sources/Providers/Cursor/CursorAuth.swift`) so a Cursor rotation is a
  one-line fix + release; there is no other place the id appears

### AC12: Settings shows an opt-in disclaimer for this provider
- **Given** the Settings UI renders the Cursor row
- **When** the user opens the Cursor section
- **Then** a short, localized disclaimer is shown stating that this provider
  uses undocumented, reverse-engineered endpoints (not an official Cursor
  API) and may stop working if Cursor changes them
- **And** the disclaimer copy is part of AC2's localized keys so it ships in
  all four locales (en, de-DE, es-ES, es-MX)

## Plan

1. **Package.swift (Phase 1).** Add a `CursorProvider` library target rooted at
   `Sources/Providers/Cursor` with `dependencies: ["Core"]` and a processed
   `Resources` folder (String Catalog + glyphs). Add a `CursorProviderTests`
   target rooted at `Tests/CursorProviderTests`. **Do not** add
   `"CursorProvider"` to the `App` executable's `dependencies` array in
   Phase 1 — it is added in Phase 2 step 8.

2. **Glyph asset (Phase 1).** Draw a monochrome Cursor mark (the cursor arrow
   is Cursor's primary visual; a simple geometric arrow avoids trademarked
   logo rasters). Export `ProviderGlyph.png` (1×) and `ProviderGlyph@2x.png`
   (2×) into the Resources folder. Confirm it loads via
   `ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)`.

3. **String Catalog (Phase 1).** Seed
   `Sources/Providers/Cursor/Resources/Localizable.xcstrings` with the AC2
   keys in all four locales (en, de-DE, es-ES, es-MX). Verify no key is left
   in `new`/`stale` state.

4. **`CursorLocator` (Phase 2).** Implement with injected environment and
   filesystem dependencies so lookup order and missing installations are
   unit-testable, mirroring Codex's `CodexLocator` (providers 05 Plan 2).
   Lookup order: process `PATH`, Homebrew prefixes, `/usr/local/bin`, the
   Cursor desktop app's bundled CLI.

5. **`CursorTokenStore` (Phase 2).** Read tokens in order:
   Keychain (`cursor-agent` service) → SQLite
   (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`).
   Use the existing `Keychain` helper in `Sources/Core/Keychain.swift` for the
   Keychain path and a read-only `SQLite3` open for the SQLite path. Decode the
   JWT `exp` without a third-party JWT library (base64url-decode the payload,
   read `exp`). `ensureValidAccessToken()` POSTs to `/oauth/token` and writes
   the refreshed access token back to the source it came from.

6. **`CursorAuth` + `CursorError`.** `CursorAuth` is a tiny file holding the
   first-party `client_id` constant
   (`KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB`) and the OAuth endpoint — the **only**
   place the id appears, so a Cursor rotation is a one-line change. `CursorError`
   mirrors `ZAIError`'s shape plus the two Cursor-specific cases:
   `.missingToken`, `.sessionExpired`, `.clientIdRejected`, `.http(Int)`,
   `.network(Error)`, `.decoding(Error)`. `LocalizedError` mappings for
   401/429/network/decoding/sessionExpired/clientIdRejected.

7. **Wire types (Phase 2).** `CursorUsageResponse` decodes the envelope
   (`billingCycleStart`/`billingCycleEnd` as ms-strings → `Date`,
   `isUnlimited`, `planUsage`, `spendLimitUsage`, and the legacy
   `individualUsage` shape for tolerance). All amount fields decode as `Int`
   (cents) and are converted to `Double` dollars in the mapping step.

8. **`CursorProvider` (Phase 2).** `providerId = "cursor"`,
   `providerName = "Cursor"`, `authShape = .apiKeyFree` — the user never pastes
   a key; filbert reads the session Cursor's own apps created locally. This is
   the Codex shape (providers 05 AC2): `isConfigured()` is overridden to return
   `true` only when a Cursor token pair is locatable OR the Cursor CLI binary is
   present, and `currentSetupState()` reports the actionable setup reason when
   not. `baseURL = URL(string: "https://api2.cursor.sh")!`. Populate
   `setupHelp` with a `ProviderSetupHelp(linkLabel: "Sign in to Cursor",
   url: <Cursor CLI install/login docs>)` so the Settings row surfaces the
   `agent login` prerequisite (AC2b, ui 13). `fetchQuota` loads the token via
   `CursorTokenStore`, refreshes if needed, POSTs to
   `GetCurrentPeriodUsage`, decodes, and maps to `ProviderQuota`. On
   `isUnlimited == true` the headline reads "Unlimited".

9. **App registration (Phase 2).** Add `"CursorProvider"` to the `App`
   executable's dependency list in `Package.swift` and add one line in
   `Sources/App/AppMain.swift`: `registry.register(CursorProvider())` plus the
   module import. No other App change.

10. **Tests.** `Tests/CursorProviderTests/`:
   - Locator: lookup order (PATH → Homebrew → `/usr/local/bin` → desktop app
     CLI); missing binary → `nil`.
   - Setup state: missing binary → install-link `.setup`; binary present, no
     token → "Sign in to Cursor" `.setup`; token present → `isConfigured()`
     `true`.
   - Token loading: Keychain-first ordering; SQLite fallback; neither → `nil`.
   - Refresh: expired `exp` triggers the refresh POST; `shouldLogout: true`
     throws `.sessionExpired`.
   - `client_id` rotation: a 4xx refresh response throws `.clientIdRejected`
     with the "needs an update" message.
   - Decoding: a representative `GetCurrentPeriodUsage` payload produces the
     expected `ProviderQuota` lines, headline, percentage, and `resetDate`.
   - Unlimited plan produces the "Unlimited" headline.
   - Team/pooled payload produces the "Pooled spend" line.
   - Error mapping: 401/429/non-200/undecodable body each throw the right
     `CursorError`. The request URL is the `GetCurrentPeriodUsage` path and
     carries `Authorization: Bearer <token>` and
     `Connect-Protocol-Version: 1`.

No production code is written until this spec is reviewed.

## Risks

- **Undocumented endpoints.** `api2.cursor.sh` is not a public API and can
  change shape, field names, or auth without notice. Tolerant decoding,
  typed compatibility errors, and fixture coverage reduce but do not remove
  this risk. A breaking change would surface as `.decoding` / `.http(5xx)`,
  never a crash (core 01 AC4).
- **`.apiKeyFree` without an installable helper.** Cursor is `.apiKeyFree`
  like Codex (providers 05), but unlike Codex it has **no helper filbert
  installs** — the "helper" is the user's own Cursor CLI login. So the
  `installHelper()`/`removeHelper()`/`canInstallHelper()` defaults (which throw
  `ProviderSetupError.notSupported`) are correct here, and the Settings row
  must lean on `setupHelp` + `.setup` state rather than the `ui 05` install
  button. The `ui 05` API-key-free presentation must already render gracefully
  when `canInstallHelper()` is `false`; verify during review and file a `ui/`
  follow-up if it doesn't.
- **Short-lived JWT + background refresh.** A refresh failure during an
  automatic refresh must surface as `.sessionExpired` with a recovery hint,
  not silently show stale data forever. `isStale` should be set when the last
  successful fetch is older than the refresh window.
- **Token persistence back to SQLite.** Writing the refreshed access token
  back to Cursor's `state.vscdb` while the desktop app may have it open risks
  a write conflict. Preferred approach: only write back to the Keychain
  source; if the token was loaded from SQLite, refresh in-memory and do not
  persist (the next `agent login` or app restart re-syncs). Flag for review.
- **Rate limits unknown.** Cursor does not document rate limits for
  `api2.cursor.sh`. The default 5-minute refresh interval (AGENTS.md §3) is
  conservative enough, but a 429 must back off exponentially per
  AGENTS.md §3.
- **String-Catalog bundling in SPM.** Same finicky area called out in
  (providers 01 Risks): the new target's `.xcstrings` must be listed under
  `resources` or `String(localized:)` silently returns the key.
- **macOS Keychain access for another app's entries.** Reading the
  `cursor-agent` Keychain entry may prompt for Keychain access the first
  time, or be denied if the entry is scoped to Cursor's code-signing
  identity. The SQLite fallback exists precisely for this case, but it too
  may be unreadable if the desktop app locks the file.

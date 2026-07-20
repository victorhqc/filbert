## Objective

Add a `DeepSeekProvider` that queries DeepSeek's `/user/balance` endpoint and
surfaces the current prepaid balance (total, granted, topped-up) as
`ProviderQuota` lines.

## Context

- `Sources/Providers/DeepSeek/DeepSeekProvider.swift` — new module; the HTTP +
  decoding + mapping implementation. Mirrors the structure of
  `Sources/Providers/ZAI/ZAIProvider.swift` (providers 01).
- `Sources/Providers/DeepSeek/Resources/Localizable.xcstrings` — new; provider
  labels ("Total balance", "Granted credits", "Topped up", …) following the
  String Catalog pattern from (providers 01 AC7).
- `Sources/Core/ProviderProtocol.swift` — unchanged. The existing
  `ProviderQuota` / `UsageLine` / `UsageDetail` model already covers the
  continuous-consumption case (core 01 AC1): balance becomes a `UsageLine`
  with `used`/`total`/`unit`, no protocol change required.
- `Sources/Core/ProviderOverrides.swift` — unchanged. Per-provider base-URL
  override (proxy) is inherited for free (core 02 AC7); the Settings UI in
  `Sources/App/SettingsView.swift` already renders the field generically.
- `Package.swift` — gains a `DeepSeekProvider` target depending on `Core`, a
  matching `DeepSeekProviderTests` target, and is added to the `App`
  executable's dependency list.
- `Sources/App/AppMain.swift` — gains one line: `registry.register(DeepSeekProvider())`.
  No other App-layer change (core 02 AC7, ui 02 AC9).
- DeepSeek's public API surface, as of 2026-07:
  - **`GET https://api.deepseek.com/user/balance`** — the only relevant
    endpoint. Auth: `Authorization: Bearer <apiKey>`.
  - Response shape:
    ```json
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "CNY",          // "CNY" | "USD"
          "total_balance": "110.00",   // string, decimals
          "granted_balance": "10.00",  // string, free credits
          "topped_up_balance": "100.00" // string, paid credits
        }
      ]
    }
    ```
  - **No usage endpoint exists.** DeepSeek does not expose spend history,
    token totals, or a "used today" figure. The deduction rule (per the
    pricing page) is "expense = tokens × price, deducted from granted balance
    first, then topped-up balance" — observable only as `total_balance`
    decreasing between calls. Per-snapshot spend tracking is out of scope for
    this spec; if added later it would live in its own `providers/` spec.
  - Pricing reference (per 1M tokens, USD): `deepseek-v4-flash` $0.14 input
    cache miss / $0.28 output; `deepseek-v4-pro` $0.435 / $0.87. Surfaced only
    so reviewers can sanity-check that this provider is a prepaid-balance
    shape, not a coding-plan shape.

## Acceptance Criteria

### AC1: Authenticated request to the balance endpoint
- **Given** a non-empty API key
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it issues `GET <baseURL>/user/balance` with
  `Authorization: Bearer <apiKey>`, `Accept: application/json`
- **And** `<baseURL>` is the parameter value (default
  `https://api.deepseek.com`, custom proxy when overridden) — the provider
  never reads the override itself (core 02 AC2)

### AC2: Balance maps to a currency-tagged `UsageLine`
- **Given** a `200` response with `balance_infos[]`
- **When** the provider decodes it
- **Then** the first `balance_infos` entry produces a `UsageLine` labelled
  "Total balance" with `total` set from `total_balance` and `unit` set to the
  raw currency code (`"CNY"` or `"USD"`)
- **And** `granted_balance` and `topped_up_balance` each become their own
  `UsageLine` ("Granted credits", "Topped up") with the same `unit`
- **And** all amounts are parsed from their string form into `Double` for the
  model; currency formatting (symbol, decimals) is the UI's job, not the
  provider's

### AC3: `is_available: false` is surfaced, not swallowed
- **Given** a `200` response whose top-level `is_available` is `false`
- **When** the provider maps it
- **Then** the `ProviderQuota.headline` calls this out explicitly (e.g.
  "No balance available") instead of showing a bare number
- **And** the balance lines are still returned so the user can see what's left

### AC4: Headline shows the total balance, currency-aware
- **Given** decoded balance data with `is_available == true`
- **When** the headline is built
- **Then** it reads `"<symbol><amount> left"` (e.g. `"$18.50 left"`,
  `"¥110.00 left"`), formatted via `NumberFormatter(currencyCode:)` so the
  symbol and decimals follow the user's locale
- **And** when `balance_infos` is empty or all entries fail to parse, the
  headline falls back to the localized "No data" string (mirrors providers 01
  AC5 fallback pattern)

### AC5: Failures surface as errors, never fake data
- **Given** a missing/empty key, a non-`200` status (401/403/429/5xx), a
  network failure, or an undecodable body
- **When** `fetchQuota` runs
- **Then** it throws a typed `DeepSeekError` (`.missingKey`, `.http(Int)`,
  `.network`, `.decoding`, `.internalInconsistency`) so the registry records
  `.failure` (core 01 AC4) and no placeholder quota is returned
- **And** `429` is mapped to a localized "Rate limited" message; `401` to
  "Authentication failed" (mirrors providers 01 AC6)

### AC6: Labels are localized via String Catalog
- **Given** the app running under a non-English locale
- **When** labels ("Total balance", "Granted credits", "Topped up") and the
  headline are produced
- **Then** they resolve through `String(localized:)` to the active language —
  no user-facing English string literals reach `ProviderQuota`

### AC7: Settings UI inherits proxy override for free
- **Given** the user opens Settings → DeepSeek
- **When** they enter a custom base URL (e.g. `https://deepseek-proxy.corp.example.com`)
- **Then** the field is persisted via `ProviderOverrides.setBaseURL(_:for:)`
  under provider ID `"deepseek"` and subsequent fetches hit the proxy
- **And** no App-layer code branches on the provider ID — the existing
  `SettingsView` rendering loop handles it (core 02 AC7, ui 02 AC9)

### AC8: Package compiles with the new module
- **Given** a fresh checkout after the change
- **When** running `swift build`
- **Then** the project compiles with zero errors and zero warnings, and
  `DeepSeekProvider` appears as a target depending only on `Core`

## Plan

1. **Package.swift.** Add a `DeepSeekProvider` library target rooted at
   `Sources/Providers/DeepSeek` with `dependencies: ["Core"]` and a processed
   `Resources` folder (String Catalog). Add a `DeepSeekProviderTests` target
   rooted at `Tests/DeepSeekProviderTests`. Add `"DeepSeekProvider"` to the
   `App` executable's `dependencies` array.

2. **Wire types (private).** `DeepSeekBalanceResponse` decodes the envelope
   (`is_available: Bool`, `balance_infos: [DeepSeekBalanceInfo]`).
   `DeepSeekBalanceInfo` decodes `currency`, `total_balance`,
   `granted_balance`, `topped_up_balance` — all strings, parsed to `Double`
   in the mapping step (the wire shape is strings; the model wants numbers).

3. **`DeepSeekError`.** Mirror `ZAIError`'s shape: `.missingKey`, `.http(Int)`,
   `.network(Error)`, `.decoding(Error)`, `.internalInconsistency`. Provide
   `LocalizedError` mappings for 401/429/network/decoding.

4. **`DeepSeekProvider`.** `providerId = "deepseek"`, `providerName = "DeepSeek"`,
   `providerDescription = String(localized: "Monitor prepaid balance")`,
   `baseURL = URL(string: "https://api.deepseek.com")!`, `authShape = .apiKey`
   (default). `fetchQuota` mirrors `ZAIProvider.fetchQuota`'s structure:
   pattern-match auth, build `<baseURL>/user/balance`, set
   `Authorization: Bearer <key>`, decode, map to `ProviderQuota`. On
   `is_available == false`, headline reads "No balance available" but lines
   are still returned (AC3).

5. **App registration.** One line in `Sources/App/AppMain.swift`:
   `registry.register(DeepSeekProvider())` plus the module import. No other
   App change.

6. **String Catalog.** Seed
   `Sources/Providers/DeepSeek/Resources/Localizable.xcstrings` with the
   user-facing keys: "Total balance", "Granted credits", "Topped up",
   "No balance available", "No data", "%@ left", the error phrases. English
   source; other locales added later.

7. **Tests.** `Tests/DeepSeekProviderTests/`:
   - Decoding: a representative JSON payload produces the expected
     `ProviderQuota` lines, headline, and `unit` values.
   - `is_available == false` produces the "No balance available" headline.
   - Error mapping: 401/429/non-200/undecodable body each throw the right
     `DeepSeekError`. The request URL is `<baseURL>/user/balance` and carries
     `Authorization: Bearer <key>`.

No code is written until this spec is reviewed.

## Risks

- **`NumberFormatter(currencyCode:)` relies on the locale knowing the
  symbol.** CNY in an en-US locale may render as "CN¥110.00" rather than
  "¥110.00". Accepted for v1 per review; if it looks wrong we can pass the
  currency code through to the UI and format there.
- **String-Catalog bundling in SPM.** Same finicky area called out in
  (providers 01 Risks): `defaultLocalization` is already set at the package
  level, but the new target's `.xcstrings` must be listed under `resources`
  or `String(localized:)` silently returns the key.
- **Provider-description string is the only UI-visible change beyond a new
  row.** No `SettingsView` or `QuotaView` edits are expected; if those files
  need edits to render balance-style lines correctly, that's a separate
  `ui/` spec — call it out during review rather than expanding this one.
- **No "spent today" / usage history.** Acknowledged limitation: DeepSeek's
  public API has no usage endpoint, and this spec deliberately does not
  approximate spend from balance deltas. A future `providers/` spec can add
  snapshot-based delta tracking if the user wants it later.

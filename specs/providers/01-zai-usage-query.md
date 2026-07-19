## Objective

Replace the `ZAIProvider` stub with a real implementation that queries z.ai's
quota endpoint and maps the response into `ProviderQuota` (core 01).

## Context

- `Sources/Providers/ZAI/ZAIProvider.swift` — currently a stub returning
  hardcoded data; becomes the real HTTP + decoding implementation.
- `Sources/Core/ProviderProtocol.swift` — the target model (core 01). This spec
  maps the z.ai response into `ProviderQuota` / `UsageLine` / `UsageDetail`
  without adding provider-specific fields (core 01 AC1).
- Reference: zai-bar. Same endpoint and bearer-token scheme, generalized to our
  model.
- Consumed by the settings/display surface (ui 01) via `ProviderRegistry`
  (core 01 AC4).
- Adds a shared `QuotaFormatting` helper in Core (localized countdown + label
  strings) so the headline here and the per-line countdowns in ui 01 use one
  identical, localized format. Time phrases build on `Date.RelativeFormatStyle`,
  which the OS localizes automatically.
- i18n mechanism: user-facing labels use `String(localized:)` backed by a String
  Catalog (`.xcstrings`). `Package.swift` gains `defaultLocalization: "en"` and
  bundles the catalog as a module resource.
- Endpoint: `GET https://api.z.ai/api/monitor/usage/quota/limit`, header
  `Authorization: Bearer <apiKey>`, `Accept: application/json`. Plain bearer
  token — no JWT, no session cookie.
- Response shape: `data.limits[]`, each entry keyed by a `(type, unit)` pair:
  - `TOKENS_LIMIT` / unit `3` — 5-hour token window
  - `TOKENS_LIMIT` / unit `6` — weekly token window
  - `TIME_LIMIT` / unit `5` — monthly web-tool calls
  - Each entry: `percentage` (0–100), optional `usage`/`currentValue`,
    `nextResetTime` (epoch **milliseconds**), optional `usageDetails[]`
    (per-model breakdown).

## Acceptance Criteria

### AC1: Authenticated request to the quota endpoint
- **Given** a non-empty API key
- **When** `fetchQuota(apiKey:)` runs
- **Then** it issues `GET https://api.z.ai/api/monitor/usage/quota/limit` with
  `Authorization: Bearer <apiKey>` and `Accept: application/json`

### AC2: Each known `(type, unit)` maps to a labelled `UsageLine`
- **Given** a `200` response with `data.limits[]`
- **When** the provider decodes it
- **Then** each recognized pair produces one `UsageLine` with a human label
  ("5-hour window", "Weekly", "Monthly web-tool calls"), `percentage` set from
  `percentage`, and `used` set from `usage`/`currentValue` when present
- **And** unrecognized `(type, unit)` pairs are ignored, not dropped as errors

### AC3: `nextResetTime` becomes a `resetDate`
- **Given** a limit entry with `nextResetTime` in epoch milliseconds
- **When** it is mapped to a `UsageLine`
- **Then** `resetDate` is that instant (ms ÷ 1000 → `Date`)

### AC4: `usageDetails[]` becomes `UsageDetail` rows
- **Given** a limit entry carrying a per-model `usageDetails[]`
- **When** it is mapped
- **Then** each model appears as a `UsageDetail(label:value:)` on that line's
  `details`; absent details leave `details` nil

### AC5: Headline follows 5-hour → weekly priority
- **Given** decoded lines
- **When** the headline string is built
- **Then** it reflects the 5-hour window percentage, falling back to the weekly
  percentage when the 5-hour window is absent, formatted like
  `"42% · resets in 3h"` using the shared `QuotaFormatting` countdown helper —
  never a hand-rolled duration string

### AC6: Failures surface as errors, never fake data
- **Given** a missing/empty key, a non-`200` status (401/403/5xx), a network
  failure, or an undecodable body
- **When** `fetchQuota` runs
- **Then** it throws a typed error (auth vs network vs decode) — the registry
  records it as a `.failure` (core 01 AC4) and no placeholder quota is returned

### AC7: Labels and time phrases are localized
- **Given** the app running under a non-English locale
- **When** labels ("5-hour window", "Weekly", …) and the headline countdown are
  produced
- **Then** they resolve through `String(localized:)` / `QuotaFormatting` to the
  active language — no user-facing English string literals reach `ProviderQuota`

## Plan

Add a private `Codable` layer (`ZAIQuotaResponse` → `data.limits[]`) that mirrors
the wire format, then a mapping step into `ProviderQuota`. Keep the `(type,
unit)` → localized-label table in one place so new windows are a one-line
addition. Use `URLSession` with `async/await`. Define a `ZAIError` enum
(`.missingKey`, `.http(Int)`, `.decoding`) so the UI can distinguish an
unconfigured provider (ui 01) from a transient failure. The wire types stay
`private` to the module — only `ProviderQuota` crosses the boundary. Introduce
`QuotaFormatting` in Core (`countdown(to: Date) -> String` over
`Date.RelativeFormatStyle`) and add the String Catalog + `defaultLocalization`
to `Package.swift`.

## Risks

- z.ai's response field names/units are inferred from the reference app and may
  drift; isolating the `Codable` layer keeps a schema change to one file.
- Percentage-only lines (no `usage`) render with `used == nil` — the display
  (ui 01) must tolerate that.
- SPM localized-resource bundling is finicky: `defaultLocalization` must be set
  and the `.xcstrings` catalog listed under the target's `resources`, or
  `String(localized:)` silently returns the key.

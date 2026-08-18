## Objective

Keep z.ai quota tracking and peak-rate guidance accurate across legacy and credits-based GLM Coding Plans without guessing a subscriber's pricing rules.

## Context

- `Sources/Providers/ZAI/ZAIProvider.swift` — currently recognizes only
  `TOKENS_LIMIT` windows and publishes one hard-coded 3×/1×/2× promotional
  schedule for every z.ai account (providers 01, ui 04).
- `Sources/Core/ProviderProtocol.swift` — `PeakHoursConfig` supports daily
  schedules and integer multipliers, but not weekday-only windows, fractional
  rates, or plan-specific rate wording (providers 08).
- `Sources/App/PeakHoursBlock.swift` — renders every active value as an integer
  “multiplier” and therefore cannot accurately describe the new plan's 50%
  off-peak credit rate.
- `Tests/ZAIProviderTests/ZAIProviderQuotaMappingTests.swift` — covers the
  legacy response and promotional cutoff; it needs sanitized legacy and new-plan
  fixtures plus plan-selection coverage.
- `Tests/CoreTests/PeakHoursConfigTests.swift` and
  `Tests/DeepSeekProviderTests/DeepSeekProviderPeakHoursTests.swift` — protect
  generalized schedule behavior and DeepSeek's existing daily 2×/1× rules
  while Core evolves (providers 08).
- Z.AI's July 30, 2026
  [plan update announcement](https://docs.z.ai/devpack/notice/usage-revision)
  keeps active legacy plans on their existing calculation method and moves new
  subscriptions to token-weighted credits.
- Wire evidence captured 2026-08-18: a first-party legacy V2 pair from the
  user's GLM Coding Pro account (quota + subscription) and a second-party real
  credits quota capture from CodexBar issue #2724 (GLM Coding Lite, global
  host, 2026-08-06) — basing the credits mapping on the latter was approved by
  the user instead of purchasing a credits subscription. Confirmed semantics
  are recorded below.
- The current
  [individual-plan](https://docs.z.ai/devpack/overview) and
  [team-plan](https://docs.z.ai/devpack/teamplan) documentation defines peak as
  Monday through Friday, 14:00–18:00 Singapore time, and charges new plans 50%
  of the standard credit rate outside that window.
- For new plans, credit consumption depends on separate input, cached-input,
  and output multipliers for each model. Filbert displays server-reported quota
  consumption and does not reproduce that calculation locally.

## Confirmed wire semantics

Recorded 2026-08-18 before implementation (AC1). Evidence: first-party legacy
V2 captures (quota + subscription) and the second-party credits quota capture
from CodexBar issue #2724, corroborated independently by ClaudeBar, cc-switch,
token-monitor, and CodexBar's shipped parser.

- Envelope (both families): `{code, msg, data, success}`. Successful quota
  responses carry `data.limits[]` and a plan-tier label at `data.level`
  (display-only — never a calculation discriminator, AC3).
- `unit` × `number` window semantics: `unit` 3 = hours, 4 = days, 5 = months,
  6 = weekly; `number` is the count. Observed windows: 3×5 (5-hour), 6×1
  (weekly), 5×1 (monthly MCP).
- Legacy V2 family: `TOKENS_LIMIT` windows carry `percentage` and
  `nextResetTime` (epoch ms) only. The monthly `TIME_LIMIT` MCP lane carries
  `usage` (allowance), `currentValue` (used), `remaining`, and per-model
  `usageDetails` (search-prime, web-reader, zread).
- Credits family: `CREDIT_LIMIT` windows use the same `unit` semantics but
  additionally carry absolute values — `usage` (credit allowance),
  `currentValue` (credits used), `remaining`. The Lite capture has no
  `TIME_LIMIT` lane. The subscription `version` string for credits accounts
  remains unverified.
- Subscription endpoint `GET api/biz/subscription/list` (verified
  first-party): `data[]` entries carry `version` (`"V2"` observed on legacy),
  `status`, `productName`, renewal dates, and billing metadata.
- Pricing-mode discriminator (user-approved "Option B"):
  - `CREDIT_LIMIT` windows present with no `TOKENS_LIMIT` → credits mode.
  - `TOKENS_LIMIT`-only windows plus subscription `version == "V2"` → legacy
    V2 mode.
  - Anything else — mixed `CREDIT_LIMIT` + `TOKENS_LIMIT` (reported on the
    China host), an unknown version, or a failed subscription fetch — attaches
    no pricing metadata (AC4).
- Peak-rate metadata: credits mode uses Mon–Fri 14:00–18:00 Asia/Singapore
  with standard vs 50%-of-standard credit rates; legacy V2 keeps the daily
  14:00–18:00 Asia/Shanghai window at 3×/1× with the promotional cutoff
  removed (AC6).

## Acceptance Criteria

### AC1: Base the new mapping on captured responses

- **Given** sanitized successful responses from a legacy V2 account and a new
  credits-based individual or team account
- **When** implementation begins
- **Then** both payloads are committed as test fixtures with secrets, account
  identifiers, and unrelated personal data removed
- **And** the spec records any newly confirmed type names, window fields, plan
  discriminator, and field semantics before production mapping is changed

### AC2: Preserve legacy and credits-based quota windows

- **Given** either captured quota response
- **When** `ZAIProvider` maps its limits
- **Then** the 5-hour and weekly windows produce the same normalized
  `UsageLine` labels, percentages, consumption values, totals, and reset dates
  where those values are supplied
- **And** the existing monthly MCP or web-tool limit continues to map when it
  is present
- **And** a credits-based limit is not discarded solely because its type is
  not `TOKENS_LIMIT`

### AC3: Use response semantics instead of one plan-wide assumption

- **Given** the captured responses expose an authoritative way to distinguish
  the credits-based calculation from legacy V2
- **When** the provider creates peak-rate metadata
- **Then** a credits-based plan receives standard-rate versus 50%-rate metadata
- **And** legacy V2 receives 3× peak versus 1× off-peak metadata
- **And** plan tier names such as Lite, Pro, Max, Standard, or Premium are not
  treated by themselves as proof of a calculation method

### AC4: Do not guess when the plan calculation is unknown

- **Given** a valid quota response whose calculation method cannot be
  established from verified response data
- **When** the provider maps the response
- **Then** its quota lines and headline still render
- **And** no multiplier, discount, promotional cutoff, or model-rate claim is
  attached to the quota
- **And** this uncertainty is not treated as a refresh failure

### AC5: Apply the documented weekday peak window

- **Given** a plan with verified current peak-rate metadata
- **When** the time in Singapore is Monday through Friday from 14:00 inclusive
  until 18:00 exclusive
- **Then** the schedule reports peak
- **And** before 14:00, at or after 18:00, and throughout Saturday and Sunday it
  reports off peak
- **And** converting the window for display uses the user's current time zone

### AC6: Remove the obsolete promotional cutoff

- **Given** any date before, at, or after October 1, 2026
- **When** current z.ai pricing metadata is selected
- **Then** the date alone never changes an off-peak rate from 1× to 2×
- **And** `ZAIPeakHours.promoEndDate` and the related promotional branch are no
  longer part of z.ai behavior

### AC7: Describe rates without conflating credit factors

- **Given** a credits-based plan during peak hours
- **When** `PeakHoursBlock` renders
- **Then** it describes the standard credit rate rather than one model
  multiplier
- **And** during off-peak hours it describes the 50% credit rate
- **And** it does not collapse the documented input, cached-input, and output
  factors into a single value or calculate consumed credits locally

### AC8: Preserve multiplier presentation for legacy schedules

- **Given** a verified legacy V2 z.ai plan or the existing DeepSeek schedule
- **When** `PeakHoursBlock` renders its active rate
- **Then** whole-number values continue to appear as localized 3×/1× or 2×/1×
  multipliers as applicable
- **And** all new standard-rate, percentage-rate, and schedule strings are
  localized and accessible

### AC9: Keep schedule metadata provider-neutral

- **Given** Core needs weekday constraints and more than one rate presentation
- **When** `PeakHoursConfig` is extended
- **Then** the model describes generic active days, windows, and rate display
  semantics without z.ai model names, plan names, or provider IDs
- **And** providers continue to construct only their own metadata
- **And** DeepSeek retains its existing daily windows, effective date, and
  2×/1× results unchanged (providers 08 AC3, providers 08 AC4, providers 08 AC5)

### AC10: Cover boundaries and forward compatibility

- **Given** fixture-driven provider tests and deterministic dates around every
  weekday, weekend, 14:00, and 18:00 Singapore boundary
- **When** the test suite runs
- **Then** it verifies both quota response families, plan-aware rate selection,
  unknown-plan suppression, local schedule conversion, and removal of the
  October cutoff
- **And** unknown limit types and additional response fields remain nonfatal
- **And** existing Core, z.ai, DeepSeek, and app peak-hours tests pass

## Plan

1. [x] Capture responses and record confirmed wire semantics (above). Fixtures:
   the sanitized first-party legacy pair plus the #2724-derived credits
   payload, with provenance noted in the tests.
2. [x] Replace z.ai's fixed `(type, unit)` label assumptions with `unit` × `number`
   window mapping that recognizes both response families while keeping all
   z.ai wire types private to its provider module.
3. [x] Fetch `api/biz/subscription/list` alongside each refresh (best-effort and
   non-fatal) and derive the pricing mode per the discriminator above; attach
   mode-specific peak-rate metadata or none.
4. [x] Generalize `PeakHoursConfig` with provider-neutral active-day and rate
   presentation data. Preserve existing defaults so daily integer-multiplier
   providers do not change behavior.
5. [x] Update `PeakHoursBlock` to render either a multiplier or a credit-rate label,
   then add the required localized strings and accessibility coverage.
6. [x] Replace obsolete z.ai promotional tests with fixture, plan-selection,
   weekday, weekend, and boundary tests. Run the full validation gate before
   handoff.

## Risks

- Z.AI does not document the monitoring or subscription response schemas. A
  production response can drift independently of the public policy pages, so
  decoding must tolerate unknown fields and suppress unverified pricing claims.
- The credits wire evidence is a second-party capture (CodexBar #2724), not a
  first-party account, accepted by user decision. Decoding stays tolerant of
  unknown fields and pricing claims are suppressed whenever the mode cannot be
  positively established.
- Legacy attribution now depends on the subscription endpoint returning
  `version "V2"`. If that call fails or drifts, legacy users lose the peak-rate
  block while quota lines keep rendering — AC4 degradation, not a refresh
  failure.
- Adding weekday and rate-presentation concepts to Core can regress DeepSeek or
  future providers. Provider-neutral defaults and cross-provider tests are
  required.
- Legacy V1 calculation rules are not stated in the current usage reference.
  Treating all legacy-looking payloads as V2 would display false guidance.
- Public model multipliers can change without changing quota response fields.
  Avoiding local credit calculations limits the stale-data surface to the
  informational rate label.

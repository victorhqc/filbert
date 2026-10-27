## Objective

Add a `KimiCodeProvider` that reports a Kimi membership's Kimi Code usage windows with a Kimi Code API key.

## Context

- Status: implemented 2026-10-23, uncommitted, without live data. The user approved the revision on 2026-10-23. No Kimi membership is available for a live capture. On 2026-10-23 the user chose public payloads from other apps and issue reports instead, as with (providers 20). Pay-as-you-go Open Platform balances are a separate product with separate keys (providers 23).
- `Sources/Providers/KimiCode/` — new provider module: request, lenient decoding, window merging, mapping, and errors. Mirrors the z.ai provider (providers 01), the closest existing shape.
- `Sources/Providers/KimiCode/Resources/Localizable.xcstrings` — provider labels, setup text, and errors in every locale the app ships. The window labels reuse the existing "5-hour window", "Weekly", and "Monthly" terms.
- `Sources/Providers/KimiCode/Resources/ProviderGlyph.png` and `ProviderGlyph@2x.png` — the Kimi glyph from (providers 23), generated from the same `scripts/provider-glyphs/kimi.svg` (ui 14 AC1).
- `Sources/Core/` — unchanged. `UsageLine` with `percentage`, `resetDate`, `windowDuration`, and `limitGroup` covers every window (core 01).
- `Package.swift` and `Sources/App/AppMain.swift` — gain a `KimiCodeProvider` target, a test target, and one registration line (core 02 AC7, ui 02 AC9).
- `Tests/AppTests/StringCatalogCoverageTests.swift` — gains the new module.
- `README.md`, `SETUP.md`, and `site/index.html` — list the provider, as (providers 23) did for Kimi API.
- `ProviderSettingsRow` does not render `setupHelp` for API-key providers (providers 23 AC6 finding). This provider sets none.

### Evidence, as of 2026-10-23

The endpoint is not publicly documented. The facts below come from Moonshot's source, user captures in issues, and other usage trackers.

**Endpoint and hosts.**
- The official CLI builds `${base}/usages` with base `https://api.kimi.com/coding/v1` (China) or `https://api.kimi.ai/coding/v1` (global). Source: `MoonshotAI/kimi-code` at `087db850`, `packages/oauth/src/managed-usage.ts` and `region.ts`.
- Kimi's docs give the same two bases, labelled "China" and "Overseas" (`kimi.com/code/docs/en/`). Keys are created in the Kimi Code Console, `https://www.kimi.com/code/console`.
- The FAQ says Kimi Code and the Open Platform use different base URLs and keys, and they must match.

**API keys work on `/usages`.**
- CodexBar #4306 (2026-10-06): an international account with a Kimi Code API key got `200` from `api.kimi.ai`.
- The archived `MoonshotAI/kimi-cli` (`src/kimi_cli/ui/shell/usage.py`) sends the pasted API key as `Bearer` to `/usages`.
- The current CLI sends only its OAuth token. Moonshot has not answered whether API keys are supported (kimi-code #2937), so this is observed behaviour, not a contract.

**Hosts and regions.**
- One report (kimi-code #3908, 2026-09-30) found the response byte-identical on both hosts, but the account region is not stated.
- openchamber documents that a global key gets `401` on `api.kimi.com`. Treat keys as region-bound.

**The response mixes three blocks.** Every live capture from 2026-09 onward has more than one:
- `usage` — the legacy weekly window: `limit`, `used`, `remaining`, and `resetTime`. Counts are decimal strings.
- `limits[]` — legacy windows. Each has `window: {duration, timeUnit}`, and `detail` with `limit`, `used`, `remaining`, and `resetTime`. The 5-hour window is `300` / `TIME_UNIT_MINUTE`. Either `used` or `remaining` may be missing.
- `usages` — the ratio map. `limit_5h`, `limit_7d`, `limit_month_total`, and `limit_month_code` each hold `used_ratio` (0–1) and `reset_time`. Entries may be empty (`{}`).
- Plus `goods_version` (1 for legacy plans, 2 for new plans) and a booster wallet, which arrives as `booster_wallet` in live bodies.
- Every observed legacy `limit` is `"100"`, so legacy counts are already percentages. ai-usagebar's "verbatim redacted capture" for its issue #199 has `limit: "0"`, but the issue omits the values, so those zeros are likely redaction, not live data.

**The ratio block is unreliable.** In at least three live captures, a ratio reads `0` while the legacy counter for the same window, with the same reset, is exhausted. The exhausted reading was the true one.
- kimi-code #3951 (global, 2026-09-20): `usage` 100/100 and a `403` on chat, while `limit_7d.used_ratio` is 0.
- CodexBar #4306: `limits[]` 5-hour 100/100, while `limit_5h.used_ratio` is 0.
- kimi-code #3908 (Max plan, 2026-09-18): the same pattern for 5 hours.

When both blocks are populated, they agree to rounding. pi-extensions #1390 (2026-09-23) has `limit_5h` 0.4372 against `limits[]` 44/100. CodexBar, akproxy, and ai-usagebar all fall back to the legacy counts. CodexBar takes the more-exhausted reading.

**Plans.**
- New plans (Plus, Pro, Max, Ultra) have a rolling 5-hour limit and a monthly pool.
- Legacy plans (Andante, Moderato, Allegretto, Allegro, Vivace) keep a 5-hour and a weekly limit.
- The Go tier has no Kimi Code quota.
- When the monthly pool runs out, "Kimi Code quota is frozen until the monthly quota resets" (`kimi.com/code/docs/en/kimi-code/membership.html`).

**Monthly keys.**
- `limit_month_total` is the whole monthly pool, shared with Kimi chat.
- `limit_month_code` is the share of that pool used by Kimi Code, not a second allowance. The official CLI shows one "Monthly limit" row with a "kimi X% · code Y%" breakdown (`apps/kimi-code/src/utils/usage/usage-format.ts`, `monthlyBreakdown`).
- In live captures, code is 0 against a total of 0.5531 (CodexBar #4306), and equal to the total at 0.7877 (pi-extensions #1390).

**Errors.**
- Kimi's error reference documents `401` "Invalid Authentication" and "The API Key appears to be invalid or may have expired".
- `403` covers quota limits on chat requests.
- `429` reads "too many requests" or "engine overloaded".
- No `401`, `403`, or `429` body from `/usages` itself has been published. tingly-box notes that a `403` from `/usages` means the plan has no entitlement.

**Headers.** Bearer and `Accept: application/json` are enough (CodexBar API-key path, tingly-box). One tracker claims a `KimiCLI` User-Agent is required. Nothing else confirms that claim, and Filbert does not impersonate other clients.

**Captures to use as fixtures.** Each is copied verbatim from its source in Plan step 6. The `//` comment line in the #3908 paste is the reporter's note, not part of the body.

| Fixture | Source | Shows |
|---|---|---|
| `usages-api-key-contradiction.json` | CodexBar #4306 | API key on `api.kimi.ai`; 5-hour ratio 0 vs legacy 100/100; `detail` without `remaining`; monthly keys |
| `usages-monthly-plan.json` | pi-extensions #1390 | Agreeing 5-hour readings; monthly code equals total; `booster_wallet` |
| `usages-weekly-exhausted.json` | kimi-code #3951 | Weekly ratio 0 vs `usage` 100/100; `detail` without `used` |
| `usages-legacy-plan.json` | kimi-code #3908 (maxh213) | All three blocks; ratios 0 while legacy counts are real |
| `usages-empty-ratios.json` | kimi-code #3836 | Empty `usages` entries; wallet only |

The Lumen capture is not used, because it contains a user ID. A legacy `limit` of `0` is covered by a synthetic test instead of the ai-usagebar capture.

### Not reusing the CLI login

Filbert does not reuse the CLI's login in `~/.kimi-code/credentials/`. Access tokens live about 15 minutes, and Kimi rotates refresh tokens, so a refresh by Filbert would sign the CLI out. An API key has no such conflict.

## Acceptance Criteria

### AC1: Authenticated request to the usage endpoint

- **Given** a non-empty Kimi Code API key
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it sends `GET <baseURL>/coding/v1/usages` with `Authorization: Bearer <apiKey>` and `Accept: application/json`, and no other identifying headers
- **And** `<baseURL>` defaults to `https://api.kimi.ai` and follows the user's override (core 02 AC2). China accounts set `https://api.kimi.com`
- **And** `authShape` is `.apiKey`
- **And** the provider never reads `~/.kimi-code/`, `~/.kimi/`, or Kimi's Keychain items.

### AC2: Lenient decoding

- **Given** a `200` body
- **When** the provider decodes it
- **Then** counts and ratios decode from JSON numbers or numeric strings
- **And** reset dates decode from `resetTime`, `resetAt`, `reset_time`, or `reset_at`, as RFC 3339 with or without fractional seconds
- **And** a ratio entry without a valid `used_ratio`, or a legacy entry with no positive `limit` or with neither `used` nor `remaining`, is dropped without failing the response
- **And** `goods_version`, the booster wallet, `limit_month_code`, and unknown keys are ignored
- **And** a body that is not a JSON object fails with a decoding error.

### AC3: One reading per window

- **Given** the decoded blocks
- **When** the provider builds the windows
- **Then** each window takes its readings from these sources:
  - 5-hour: the `limits[]` entry of 300 minutes or 5 hours, and `usages.limit_5h`
  - weekly: `usage`, and `usages.limit_7d`
  - monthly: `usages.limit_month_total`
- **And** a legacy reading's percentage is `used / limit × 100`, where `used` is `limit − remaining` when missing. A ratio reading's percentage is `used_ratio × 100`. Both are clamped to 0…100
- **And** when a window has two readings, the higher percentage wins. Its reset date is used, or the other reading's when it has none. Superseded for readings under 1 point apart by (providers 27 AC3)
- **And** other `limits[]` windows are ignored.

### AC4: Windows map to lines

- **Given** the merged windows
- **When** the provider maps them
- **Then** each window present becomes one percentage line, in this order:
  - "5-hour window", ID `five-hour-usage`, `windowDuration` 5 hours
  - "Weekly", ID `weekly-usage`, `windowDuration` 7 days
  - "Monthly", ID `monthly-usage`, `windowDuration` one month
- **And** every line has `resetDate` and the same `limitGroup`, because each window blocks Kimi Code once it is full
- **And** no line carries `used` or `total`.

### AC5: Headline follows the tightest window

- **Given** mapped lines
- **When** the headline is built
- **Then** it shows the 5-hour line, or else the weekly line, or else the monthly line, as `"<percentage> · <countdown>"` through `QuotaFormatting`, or the percentage alone without a reset date
- **And** `headlineUsageLineId` names that line
- **And** a `200` with no window reads "No data" and has no lines.

### AC6: Failures surface as errors, never fake data

- **Given** an empty key, a non-`200` status, a network failure, or an undecodable body
- **When** `fetchQuota` runs
- **Then** it throws a typed `KimiCodeError` and returns no placeholder quota
- **And** `401` reads "Authentication failed. Check your Kimi Code API key. Accounts in mainland China need the base URL https://api.kimi.com."
- **And** `403` reads "No Kimi Code access. Check your Kimi membership."
- **And** `429` reads "Rate limited. Try again later." and records any `Retry-After` in the provider's retry gate
- **And** other statuses read "Unexpected response from server."
- **And** no error message includes the response body.

### AC7: Setup names the right key

- **Given** the provider has no key
- **When** Settings or the README shows it
- **Then** the description reads "Monitor Kimi Code usage limits"
- **And** `README.md` and `SETUP.md` link the Kimi Code Console, give the China base URL, and say Open Platform keys belong to the Kimi API provider (providers 23).

### AC8: Strings are localized

- **Given** any shipped display language
- **When** labels, the headline, setup text, or errors are produced
- **Then** they resolve through the module's String Catalog. No English literal reaches `ProviderQuota`.

### AC9: Activity detection without forecasting

- **Given** a mapped response
- **When** the provider builds its activity observation
- **Then** each line's percentage is a `.usage` metric under the line's ID, and the observation is `.fresh`
- **And** no metric carries a forecast descriptor (Out of scope).

### AC10: The package builds clean

- **Given** a fresh checkout after the change
- **When** the validation gate runs
- **Then** format, lint, both builds, and `swift test` pass with zero warnings, and `KimiCodeProvider` depends only on `Core`.

## Plan

1. [x] Collect evidence. No subscription is available, so the user chose public evidence on 2026-10-23. Findings are in Context, under Evidence:
   - The account gets all three blocks.
   - An API key works on `api.kimi.ai`, and the default follows it.
   - `/usages` accepts an API key.
   - `limit_month_code` is a share of `limit_month_total`, so it gets no line.
2. [x] Add the `KimiCodeProvider` target, the test target, the App dependency, the registration line, and the catalog coverage entry.
3. [x] Add the private wire types with lenient number, ratio, and reset-key decoding, and `KimiCodeError`.
4. [x] Implement `fetchQuota`, the window merge, the mapping, the headline, the activity observation, and the retry gate. Finding: the app's status follows the first percentage line, as it does for z.ai, Codex, and Claude. So a full weekly window under a 5-hour window at 0% (kimi-code #3951) still shows the 5-hour percentage in the menu bar. The weekly line shows 100% in the popover.
5. [x] Seed the String Catalog in every shipped locale, and add the glyph and its generator entry. The window labels, "No data", and the shared errors reuse existing translations. The glossary gains "membership (Kimi Code)" and "mainland China". zh-Hans uses 会员 and 国内 from the Kimi Code docs. The other new terms keep ⚠︎ until a native review. The glyph is byte-identical to the Kimi API glyph.
6. [x] Tests. Copy the five fixtures verbatim from their sources, removing nothing but identifiers. Cover:
   - the request shape and the base-URL override;
   - each fixture;
   - the higher-percentage merge both ways, and the reset-date fallback;
   - clamping, string and numeric values, and every reset key;
   - dropped entries, and an empty object;
   - `401`, `403`, `429`, `500`, network failure, and a non-object body.

   A script extracted the JSON blocks from the issue bodies, so the fixtures are byte-for-byte copies. The only line removed is the `//` request note in #3908. None of the five bodies contains an identifier. 33 tests.
7. [x] Update `README.md`, `SETUP.md`, and `site/index.html`. On 2026-10-23 the user asked for one site tile for both Kimi providers: "Kimi", reading "Prepaid balance & Membership usage", with the existing `kimiapi.png`. The app keeps two providers.

## Out of scope

- Allowance forecasting. A follow-up spec decides which windows are fixed periods (core 12 AC2). The 5-hour window is rolling and stays unsupported. The weekly and monthly windows have subscription-anchored resets.
- The Kimi/code split of the monthly pool. The `limit_month_code` share has no place in `UsageLine` without a breakdown concept.
- The booster wallet and monthly charge limit. Its key is `booster_wallet` in live bodies, `boosterWallet` in fixtures, and its fixed-point units come from source code only.
- The plan name from `GET /coding/v1/me`.
- The web billing endpoints on `www.kimi.com` that need a browser cookie.
- Reusing the CLI's OAuth login (Context).

## Risks

- **Undocumented endpoint.** Kimi can change or remove it without notice, and its shape has changed twice in 2026. Unknown keys are ignored, and a body with no known window reads "No data" instead of guessing.
- **API-key support is not a contract.** It is observed in one live capture and in archived code. If Kimi stops accepting keys, the provider shows the `401` or `403` error.
- **Region default.** Keys appear to be region-bound. A China key gets `401` until the user sets the base URL, and the `401` message says so.
- **Ratio bug.** The merge relies on the legacy counters staying correct. If Kimi drops the legacy blocks before fixing the ratios, the provider reports `0%` the way the official CLI does.
- **Untested error bodies.** The `403` message is inferred from one tracker's notes and the plan docs. A capture may show it means something else.
- **Ratio precision.** Ratios have 4 decimal places in every capture, so small usage still reads above 0%.

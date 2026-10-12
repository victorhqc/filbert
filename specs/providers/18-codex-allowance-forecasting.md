## Objective

Opt Codex usage windows and finite credits into allowance forecasting (core 12), with credits on their own allowance row.

## Context

- Status: draft for review. The upstream source review is recorded (Evidence below). The capture in Plan step 1 is pending. Depends on (core 12). (core 12) merges only together with this spec and (providers 17, providers 19, providers 20). (ui 28) adds the fallback-pool declaration for the credits row after this spec lands.
- `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` — maps the `primary-window-usage`, `secondary-window-usage`, and `credits` metrics with `.unknown` freshness. Sets `lastUpdated` to `Date()` on each mapping. Attaches credits as a detail of the first window row (providers 05 AC7).
- `Sources/Providers/OpenAICodex/CodexAppServerClient.swift` — starts a new `codex app-server` for each read (providers 05 AC3). Decodes `usedPercent`, `resetsAt`, `windowDurationMins`, and `credits { balance, unlimited }`. It does not decode `hasCredits`.
- `account/rateLimits/read` sends a live backend request on each call. The response has no measurement timestamp. `usedPercent` is a whole number. `resetsAt` is the absolute reset time from the server (Evidence).
- `balance` is the backend string with no fixed number of decimals, e.g. "80", "12.5", or "1159.5692275000".
- The Codex CLI hides window-limit warnings when the account has credits. This suggests that credits are used after a window runs out. It is not verified (ui 28).
- `Sources/App/QuotaStatusResolver.swift` — `amountText(for:)` formats the `total` of a line as currency, and `resolve(for:)` reads a line with a `total` as a balance status. No `UsageLine` shape shows a plain number today.
- `Tests/OpenAICodexProviderTests/` — mapping and fixture tests.

## Acceptance Criteria

### AC1: Observations are fresh with receipt timing

- **Given** a successful `account/rateLimits/read` response
- **When** the provider maps it
- **Then** the observation is `.fresh`, because each read is a live backend request
- **And** each descriptor uses receipt timing, marked approximate (core 12 AC4)
- **And** the provider takes the receipt time once per read; fetches that share one read (providers 05 AC9) share its receipt time, and `lastUpdated` uses the same time
- **And** if the capture in Plan step 1 shows values that do not change after usage from another machine, no metric carries a descriptor and no forecast UI shows, and this spec records why.

### AC2: Window semantics are verified before opting in

- **Given** a primary or secondary window
- **When** the provider declares it a fixed period
- **Then** recorded evidence shows that `resetsAt` stays within the reset tolerance of (core 12) during one period, and that `usedPercent` only rises until reset
- **And** a window whose `resetsAt` slides with usage stays unsupported and carries no descriptor
- **And** neither `windowDurationMins` nor the upstream "rolling window" comment decides the semantics on its own (core 12 AC2)
- **And** the evidence is stored in provider fixtures and summarized in this spec.

### AC3: Windows map to typed descriptors

- **Given** a verified window with `usedPercent` and `resetsAt`
- **When** the provider maps the snapshot
- **Then** the metric carries a fixed-period descriptor with limit 100, the window's reset timestamp, a period length from `windowDurationMins`, unit percentage points, and resolution 1
- **And** the provider uses `windowDurationMins` as the period length only after the capture shows that consecutive resets are that far apart
- **And** a window longer than one day, e.g. the weekly window, is a long period, so it uses the average pace since its period started (core 12 AC13)
- **And** the `UsageLine` ID equals the metric ID
- **And** the headline line is the shortest window, matching today's headline
- **And** without a window, the provider names no headline line; the credits row is never the headline line
- **And** both windows share one limit group, because either one blocks usage when it runs out (core 12 AC8)
- **And** a window without `resetsAt` carries no descriptor.

### AC4: Credits are their own allowance row

- **Given** the snapshot reports credits
- **When** the provider maps it
- **Then** credits become a separate `UsageLine` with ID `credits` after the window rows, no longer a detail of the first window row
- **And** finite credits carry a balance descriptor in the credits unit, with one fixed resolution from the evidence (core 12 AC1)
- **And** the provider never derives the resolution from the decimals of each string; the backend trims them, and a changed resolution re-baselines (core 12 AC3)
- **And** the row shows the balance with two localized decimals and no currency symbol, e.g. "1,159.57", not the raw string "1159.5692275000"; the metric keeps the unrounded value
- **And** the credits row does not change compact status, the collapsed card header, or menu-bar selection; only (ui 28) promotion can change them
- **And** unlimited credits show "Unlimited credits" and carry no descriptor
- **And** absent credits, or `hasCredits` false with `unlimited` not true, produce no credits row, as the Codex CLI does (providers 05 AC7)
- **And** a balance that does not parse as a number carries no metric; the row shows the raw string
- **And** the credits row shows the same forecast states as every other row (core 12 AC9): learning after a baseline, an estimate when credits decrease, and no forecast text when credits stay flat after the learning limit
- **And** the credit forecast reflects only observed credit depletion
- **And** the credits row has no limit group, because credits are a separate pool (core 12 AC8)
- **And** no text predicts when consumption will switch from windows to credits (core 12 AC8)
- **And** a credit purchase is a balance increase and re-baselines (core 12 AC3).

### AC5: No new provider work

- **Given** forecasting is enabled for Codex
- **When** refreshes run
- **Then** each refresh still performs one `account/rateLimits/read` session (providers 05 AC9)
- **And** the provider changes no refresh scheduling and reads no credentials (core 12 AC10).

### AC6: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover:
  - `.fresh` observations with receipt timing, and coalesced fetches that share one receipt time
  - stable resets, a five-hour rollover, and a weekly rollover
  - a window without `resetsAt`
  - the headline line ID with two windows, one window, and no window
  - finite, unlimited, and absent credits, `hasCredits` false, and a response without `hasCredits`
  - a credits row without windows
  - a credit purchase, balances with different numbers of decimals, and an unparseable balance
  - unchanged compact status with the credits row present
  - a replay of the capture in Evidence, which produces no correction and no re-baseline inside a period.

## Plan

1. [ ] Capture `account/rateLimits/read` responses with the installed Codex CLI. Use the same exchange as the provider, no more often than every 30 seconds, because each read sends one or two backend requests. Cover an active session across one five-hour reset and one weekly reset, idle time, and usage from another machine or Codex cloud. Record the CLI version. Also record `ordinaryUsageAllowed` and `rateLimitReachedType` for (ui 28).
2. [ ] From the capture, record whether `resetsAt` stays within the tolerance, whether `usedPercent` only rises, whether consecutive resets are `windowDurationMins` apart, when `resetsAt` is absent, and the most decimals in `balance`. If credits do not move during the capture, record that credit depletion is not observed.
3. [ ] Decide how the credits row shows a plain number. Today `UsageLine` shows an amount only as currency through `total`, and a `total` changes `resolve(for:)` when no window has a percentage. Any App change stays generic, with no provider ID (core 12 AC1).
4. [ ] Move credits to their own row. Add `.fresh`, receipt timing, descriptors, line IDs, the limit group, and the headline line ID. Keep all Codex interpretation inside the module.
5. [ ] Convert the capture into fixture traces with only receipt times, percentages, reset times, durations, and credit fields. Drop `accountId`, plan names, and limit names (providers 05 AC4). Add the fixtures and tests from (AC6).
6. [ ] Manually inspect the popover and VoiceOver for the states in (core 12) Plan step 9 with real Codex data.

### Evidence

**Upstream source, openai/codex `main` at `10da5692`, read on 2026-10-09:**

- `account/rateLimits/read` calls the backend on every request: `GET /wham/usage`, and also `GET /wham/rate-limit-reset-credits` unless the request sets `excludeResetCreditDetails`. Nothing reads from a cache (`codex-rs/app-server/src/request_processors/account_processor.rs`).
- The `x-codex-*` headers of model turns feed only the `account/rateLimits/updated` notification, never the read.
- `RateLimitWindow.usedPercent` is `i32`. The backend also sends an integer, so the conversion loses nothing.
- `resetsAt` is copied from the server's `reset_at`, in Unix seconds. `reset_after_seconds` is ignored (`codex-rs/backend-client/src/client.rs`).
- A doc comment calls `windowDurationMins` the "Rolling window duration". Nothing in the source says when a window starts.
- `CreditsSnapshot` is `{ hasCredits, unlimited, balance }`. `balance` passes through from the backend unchanged.
- The response also carries `accountId` and `planType`, but no measurement timestamp.

**Capture:** pending. This machine has Codex CLI 0.145.0. The capture confirms these fields for the installed version.

## Risks

- Moving credits to their own row is a visible UI change for Codex users.
- If the backend returns an older value after a newer one, each drop is a correction (core 12 AC3), and the history restarts. The capture must show that this does not occur. If it occurs, this spec needs a rule like (providers 17 AC3).
- `codex login` can switch accounts. The response carries `accountId`, but Core has no field for an account change (core 12 AC11). The forecast can span two accounts until a reset re-baselines.
- A plan change can change how much one percentage point is worth. A rate can span the change until the next reset.
- Until (ui 28) lands, a window at 100% shows "Limit reached" in the headline (core 12 AC9), even when work continues on credits.
- Credits can stay flat for days. After each launch, wake, or gap, the credits row shows "Learning your usage rate…" for two hours, and then no forecast text. An estimate appears only after the windows run out and credits start to move.
- `codex app-server` is experimental (providers 05). Field names can change between CLI releases.

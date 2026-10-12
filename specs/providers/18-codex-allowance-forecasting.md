## Objective

Opt Codex usage windows and finite credits into allowance forecasting (core 12), with credits on their own allowance row.

## Context

- Status: draft for review. The upstream source review is recorded (Evidence below). The capture in Plan step 1 started on 2026-10-12. Depends on (core 12), which is on `main` with (providers 17). The credits row depends on (core 13). (ui 28) adds the fallback-pool declaration for the credits row after this spec lands.
- `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` — maps the `primary-window-usage`, `secondary-window-usage`, and `credits` metrics with `.unknown` freshness. Sets `lastUpdated` to `Date()` on each mapping. Attaches credits as a detail of the first window row (providers 05 AC7).
- `Sources/Providers/OpenAICodex/CodexAppServerClient.swift` — starts a new `codex app-server` for each read (providers 05 AC3). Decodes `usedPercent`, `resetsAt`, `windowDurationMins`, and `credits { balance, unlimited }`. It does not decode `hasCredits`.
- `account/rateLimits/read` sends a live backend request on each call. The response has no measurement timestamp. `usedPercent` is a whole number. `resetsAt` is the absolute reset time from the server (Evidence).
- An unused window at 0% reports `resetsAt` as the server time plus the window length. The reset moves forward on each read until the window starts (Evidence).
- `balance` is the backend string with no fixed number of decimals, e.g. "80", "12.5", or "1159.5692275000".
- The Codex CLI hides window-limit warnings when the account has credits. This suggests that credits are used after a window runs out. It is not verified (ui 28).
- No `UsageLine` shape shows a plain number today. The App reads a line without a percentage as a currency balance, and hides it unless it has a positive `total`. (core 13) adds a typed balance with a credits unit.
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
- **And** a window without `resetsAt` carries no descriptor
- **And** a window at 0% carries no descriptor, because its `resetsAt` can move with each read; at the default 5-minute refresh, each move passes the reset tolerance of (core 12), starts a new period, and looks like a change to Smart refresh (core 11).

### AC4: Credits are their own allowance row

- **Given** the snapshot reports credits
- **When** the provider maps it
- **Then** credits become a separate `UsageLine` with ID `credits` after the window rows, no longer a detail of the first window row
- **And** finite credits carry a balance descriptor in the credits unit, with one fixed resolution from the evidence (core 12 AC1)
- **And** the provider never derives the resolution from the decimals of each string; the number of decimals can differ between responses, and a changed resolution re-baselines (core 12 AC3)
- **And** the row has a finite balance in the credits unit (core 13), so it shows two localized decimals and no currency symbol, e.g. "1,159.57", not the raw string "1159.5692275000"; the balance and the metric keep the unrounded value
- **And** the credits row does not change compact status, the collapsed card header, or menu-bar selection (core 13 AC3); only (ui 28) promotion can change them
- **And** unlimited credits have an unlimited balance, which shows "Unlimited", and carry no descriptor
- **And** absent credits, or `hasCredits` false with `unlimited` not true, produce no credits row, as the Codex CLI does (providers 05 AC7)
- **And** a balance that does not parse whole as a number, e.g. "1,159.57", carries no metric and no balance; the row shows the raw string as a detail
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
  - an unused window at 0% whose `resetsAt` moves with each read, which carries no descriptor and is no change to Smart refresh
  - the headline line ID with two windows, one window, and no window
  - finite, unlimited, and absent credits, `hasCredits` false, and a response without `hasCredits`
  - a credits row without windows
  - a credit purchase, balances with different numbers of decimals, and an unparseable balance
  - unchanged compact status with the credits row present
  - a replay of the capture in Evidence, which produces no correction and no re-baseline inside a period.

## Plan

1. [ ] Capture `account/rateLimits/read` responses with the installed Codex CLI. Use the same exchange as the provider, no more often than every 30 seconds, because each read sends one or two backend requests. Cover an active session across one five-hour reset and one weekly reset, idle time, and usage from another machine or Codex cloud. Record the CLI version. Also record `rateLimitReachedType` and `spendControlReached` for (ui 28). CLI 0.145.0 sends no `ordinaryUsageAllowed`.
2. [ ] From the capture, record whether `resetsAt` stays within the tolerance, whether `usedPercent` only rises, whether consecutive resets are `windowDurationMins` apart, when `resetsAt` is absent, and the most decimals in `balance`. If credits do not move during the capture, record that credit depletion is not observed.
3. [x] Decide how the credits row shows a plain number. Decided on 2026-10-12: a typed balance on `UsageLine` (core 13). A preformatted string leaves the number unreadable for (ui 28), and a typed unit on `total` keeps two meanings for `total`.
4. [ ] Map the provider. Keep all Codex interpretation inside the module:
   - [x] `.fresh`, one receipt time per read, line IDs, the limit group, and the headline line ID. With the headline line and the limit group, a window at 100% already shows "Limit reached" (core 12 AC9).
   - [ ] Window descriptors, after Plan step 2.
   - [x] The credits row and its descriptor, after (core 13). The resolution is 10⁻¹⁰, because every read in the capture so far has 10 decimals. A credits metric exists only when the credits row exists, so `hasCredits` false also drops the metric. Tests cover finite, unlimited, and absent credits, `hasCredits` false, a response without `hasCredits`, unparseable balances, a credits row without windows, a credit purchase, balances with different numbers of decimals, and a credits row that carries nothing that ranks a provider (core 13 AC3).
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

**Capture, Codex CLI 0.145.0, one read per minute, from 2026-10-12 11:37 UTC:**

The capture runs the provider's exchange from a local script and keeps the raw reads outside the repository. It replaces `accountId` with a short hash. The first reads show:

- The response has no `accountId` and no `ordinaryUsageAllowed`. It has `planType`, `limitId` "codex", `limitName`, `individualLimit`, `rateLimitReachedType`, `spendControlReached`, and `rateLimitResetCredits`.
- `rateLimitResetCredits` lists reset credits titled "Full reset (Weekly + 5 hr)", with `availableCount` 3. A user can spend one to reset both windows before `resetsAt`.
- The five-hour window was at 0%. On each read, its `resetsAt` was the receipt time plus 300 minutes, within 1.3 seconds: 16:37:38 at 11:37:38, then 16:38:34 at 11:38:35.
- The weekly window was at 38%, with a steady `resetsAt` of 2026-10-18 10:04:32 UTC. The reset has seconds, not whole minutes.
- `balance` was "811.7749020000", with 10 decimals and trailing zeros, on all 79 reads up to 2026-10-12 13:01 UTC. `hasCredits` was true and `unlimited` false.

## Risks

- Moving credits to their own row is a visible UI change for Codex users.
- If the backend returns an older value after a newer one, each drop is a correction (core 12 AC3), and the history restarts. The capture must show that this does not occur. If it occurs, this spec needs a rule like (providers 17 AC3).
- `codex login` can switch accounts. CLI 0.145.0 sends no `accountId`, and Core has no field for an account change (core 12 AC11). The forecast can span two accounts until a reset re-baselines.
- A reset credit resets both windows before `resetsAt`. The windows drop to 0% and lose their descriptors (AC3), so their histories restart. This is correct, not a defect.
- A plan change can change how much one percentage point is worth. A rate can span the change until the next reset.
- Until (ui 28) lands, a window at 100% shows "Limit reached" in the headline (core 12 AC9), even when work continues on credits.
- Credits can stay flat for days. After each launch, wake, or gap, the credits row shows "Learning your usage rate…" for two hours, and then no forecast text. An estimate appears only after the windows run out and credits start to move.
- `codex app-server` is experimental (providers 05). Field names can change between CLI releases.

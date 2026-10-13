## Objective

Opt z.ai's weekly window into allowance forecasting (core 12), and leave the five-hour window and the monthly web-tool calls unsupported.

## Context

- Status: implemented ahead of the live evidence. Plan step 1 stays open until a capture confirms the weekly window. Depends on (core 12), which is on `main`.
- `Sources/Providers/ZAI/ZAIProvider.swift` — maps the five-hour, weekly, and monthly web-tool limits (providers 01, providers 11).
  - Metrics `five-hour-usage`, `weekly-usage`, and `monthly-web-tool-usage` carry the percentage.
  - `<id>-absolute` carries `currentValue` when the response sends it.
  - Freshness is `.unknown`. Lines have no IDs and no limit group, and the quota names no headline line.
  - The headline shows the five-hour window, or the weekly window when there is no five-hour window.
- `Sources/Providers/ZAI/ZAIWire.swift` — recognizes windows by `type` and `unit`. `unit` 6 is weekly, whatever `number` says.
- Legacy plans send `TOKENS_LIMIT` windows with a percentage only. Credit plans send `CREDIT_LIMIT` windows with `currentValue` (credits used) and `usage` (the credit allowance) (providers 11).
- One weekly percentage point is 100 credits on a 10,000-credit week. Credits are therefore 100 times finer than the percentage.
- `Tests/ZAIProviderTests/` — mapping tests, plus fixtures from the user's legacy account and a public credits capture (providers 11).

## Acceptance Criteria

### AC1: The five-hour window and web-tool calls stay unsupported

- **Given** the five-hour window or the monthly web-tool limit
- **When** the provider maps it
- **Then** it carries no descriptor and shows no forecast UI (core 12 AC2)
- **And** this holds because the five-hour window gives usage back five hours after it was spent, so it slides (Evidence)
- **And** the web-tool calls are a separate pool that only legacy plans have. Their month follows the subscription, so its length varies.

### AC2: The weekly window maps to a fixed-period descriptor

- **Given** a weekly limit with a `nextResetTime`
- **When** the provider maps it
- **Then** one metric carries a fixed-period descriptor
  - Its reset is `nextResetTime`, passed unchanged.
  - Its period length is 7 days.
  - Its usage line ID is `weekly-usage`.
- **And** the window's type sets the unit:
  - On a `CREDIT_LIMIT` window, the absolute metric carries it, with limit `usage`, unit credits, and resolution 1. Without `currentValue` or a positive `usage`, the window carries no descriptor.
  - On a `TOKENS_LIMIT` window, the percentage metric carries it, with limit 100, unit percentage points, and resolution 1.
- **And** the descriptor never moves between the two metrics. A read without `currentValue` would otherwise give the percentage metric a new descriptor, and Smart refresh would read that as activity (core 11)
- **And** the other metric of that line carries no descriptor (core 12 AC1)
- **And** a weekly window without `nextResetTime`, or recognized more than once in one response, carries no descriptor
- **And** a reset card moves `nextResetTime`, and Core starts a new period (core 12 AC3)
- **And** the window is a long period, so it uses the average pace since the period started (core 12 AC13).

### AC3: Lines have IDs, a limit group, and a headline line

- **Given** the provider builds lines
- **When** it assigns IDs
- **Then** each line's ID equals its percentage metric's ID
- **And** the five-hour and weekly lines share one limit group, because either one blocks usage when it is full
- **And** the web-tool line has no limit group, because it blocks only web tools
- **And** the headline line is the line the headline summarizes: the five-hour window, or the weekly window when there is no five-hour window
- **And** a five-hour window at 100% therefore reads "100% · Limit reached" in the headline (core 12 AC9)
- **And** a weekly window at 100% reads "Limit reached" in its row (core 12 AC15)
- **And** the weekly row shows its own forecast, e.g. "Runs out in about 2d · last 96 hours"
- **And** otherwise the headline stays as the provider wrote it, because the five-hour line has no forecast.

### AC4: Timing is approximate

- **Given** a successful live response
- **When** the provider maps it
- **Then** the observation is `.fresh` with approximate receipt timing
- **And** `lastUpdated` and every descriptor use one receipt time
- **And** recorded evidence shows how soon a request reaches the weekly values. A delay longer than a few minutes is documented as a limitation.

### AC5: Rate limiting keeps its existing handling

- **Given** a 429 response or an active retry gate
- **When** a refresh is attempted
- **Then** no observation is recorded and the retry gate is unchanged
- **And** a weekly window at 100%, or with `currentValue` at or above `usage`, is exhaustion reported by the provider (core 12 AC7).

### AC6: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover:
  - the unsupported windows
  - the credits and percentage descriptors
  - a credit window without `currentValue` or a positive allowance
  - a weekly window without a reset
  - a repeated weekly window
  - `nextResetTime` jitter, which is no change to Smart refresh
  - a weekly rollover on the subscription anchor rather than on a Monday
  - a reset card that moves the reset mid-period
  - a drop in usage without a reset
  - a window at its limit.

## Plan

1. [ ] Confirm the weekly window with live data. A local script outside the repository polls the quota endpoint every 30 seconds.
   - It keeps only each limit's `type`, `unit`, `number`, `percentage`, `currentValue`, `usage`, and `nextResetTime`.
   - It reads the key on every request from a dedicated Keychain item that the user creates.
   - It confirms four things:
     - `nextResetTime` stays put within a period;
     - the next reset lands 7 days after the previous one;
     - the values are integers;
     - how soon a request reaches the weekly values.
   - The user's weekly reset fell on a Sunday at 02:02 UTC in August, so a capture must run past one such reset.
   - If no account is available, the public evidence and synthetic fixtures stand in, as in (providers 20).
2. [x] Add line IDs, the limit group, the headline line, one receipt time, and `.fresh`. The mapping moved to `ZAIProvider+Mapping.swift`. The receipt time is taken when the quota response arrives, before the subscription request.
3. [x] Add the weekly descriptor: credits on `CREDIT_LIMIT` windows, the percentage on `TOKENS_LIMIT` windows.
4. [x] Add the fixtures and tests from AC6. Existing tests that compare whole metrics compare ID, kind, and value instead, because descriptors carry the receipt time. The two committed captures cover both descriptors. Synthetic responses cover the rest. A week of half-hour reads rolls over on a Sunday reset, and a reset card starts a period from its use.

### Evidence

**Public sources, read on 2026-10-13:**

- [docs.z.ai FAQ](https://docs.z.ai/devpack/faq), undated:
  - "This quota starts counting from the time you place your order, and the quota is refreshed and reset on a 7-day cycle."
  - With a reset card, "The next reset time will be recalculated from the moment the card is used."
- [docs.bigmodel.cn overview](https://docs.bigmodel.cn/cn/coding-plan/overview), undated:
  - Weekly credits refresh on a 7-day cycle from the order.
  - A renewal keeps the cycle.
  - An upgrade refreshes credits at once. It does not say whether the reset moves.
- [docs.z.ai overview](https://docs.z.ai/devpack/overview), and the plan update of 2026-07-30: "5-hour credits: Dynamically refreshed; credit quota resets 5 hours after consumption."
- Every public capture has integer percentages and integer credits.
  - CodexBar #2724 (2026-08-06) has 71 of 10,000 weekly credits at 1%.
  - CodexBar's parser rejects any value that is not an integer.
- cc-switch has seen the weekly window as both `unit` 6 with `number` 1 and `unit` 6 with `number` 7.
- ORG2's public capture of 2026-06-29 has a weekly reset at 02:38:06.997 UTC and a web-tool reset at 02:38:06.976 UTC: the same time of day.

**The user's capture of 2026-08-18 (`quota-legacy-v2.json`):**

- The weekly reset was Sunday 2026-08-23 02:02:45.998 UTC.
- The web-tool reset was 2026-09-02 02:02:45.999 UTC.
- Both share the subscription's time of day. The weekly window does not follow the calendar week.

## Risks

- On legacy plans, whole percentage points make the weekly average coarse early in the week. Credit plans do not have this problem.
- An upgrade refreshes credits at once. If the reset stays put, the average still counts from the period start, so the pace reads slower than it is until the next reset. In a replay at a steady pace, an estimate turns into "Should last until reset" at the drop.
- The API has sent a five-hour reset about 10 hours away (CodexBar #2871). The five-hour window carries no descriptor, so this cannot reach a forecast.
- z.ai documents neither the monitoring response nor its update delay. A change of shape drops the descriptor; it does not break the lines.
- Some China-host responses mix `TOKENS_LIMIT` and `CREDIT_LIMIT` windows (providers 11). A repeated weekly window then shows no forecast.

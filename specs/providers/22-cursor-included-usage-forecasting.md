## Objective

Opt Cursor's included usage into allowance forecasting (core 12) through its total percentage, over the billing cycle that the API reports.

## Context

- Status: implemented without live data, because Cursor is not installed on this Mac. On 2026-10-13 public evidence replaced the dollar basis with the total percentage (Evidence). Depends on (core 12), which is on `main`.
- `Sources/Providers/Cursor/CursorProvider.swift` — maps `GetCurrentPeriodUsage` (providers 07).
  - "Included usage" has `used`/`total` from `includedSpend`/`limit`, a percentage from `totalPercentUsed`, and its reset from `billingCycleEnd`. Its bar shows `totalPercentUsed`.
  - Auto and API percentages are details under that line, not lines.
  - "Bonus credits", "On-demand spend", and "Pooled spend" follow.
  - Lines have no IDs, and the quota names no headline line.
  - The headline reads the money left, e.g. "$42.50 left · resets in 5d".
- `Sources/Providers/Cursor/CursorProvider+ActivityObservation.swift` — `included-usage` carries `includedSpend` in dollars. Freshness is `.unknown`.
- `Sources/Providers/Cursor/CursorProvider+Normalization.swift` — `planUsage` amounts are integer cents. The legacy `individualUsage.plan` sends request-style counters, which the provider normalizes into the same fields (providers 07).
- The response carries `billingCycleStart` and `billingCycleEnd` as millisecond strings. The provider reads the period length from them and needs no calendar rule.
- Included usage has two pools: Auto and Composer, and API. Each has a cap that Cursor does not report, and the caps have changed several times (Evidence).
  - `includedSpend` stops at `limit` while Cursor keeps serving from bonus credit. A full `includedSpend` therefore does not mean included usage is gone.
  - `totalPercentUsed` is Cursor's own measure across both pools. It is not `includedSpend` divided by `limit`.
- When included usage runs out, on-demand spend can take over, if the user enabled it. A full included allowance therefore does not always block use.
- `Tests/CursorProviderTests/` — mapping and observation tests.

## Acceptance Criteria

### AC1: The total percentage maps to a fixed-period descriptor

- **Given** a `planUsage` response with `totalPercentUsed` and a billing cycle whose end is after its start
- **When** the provider maps it
- **Then** a metric `included-usage-percent` carries `totalPercentUsed` and a fixed-period descriptor:
  - Its limit is 100.
  - Its reset is `billingCycleEnd`.
  - Its period length is `billingCycleEnd` minus `billingCycleStart`.
  - Its unit is percentage points, with resolution 0.01.
  - Its usage line ID is `included-usage`.
- **And** the `included-usage` metric keeps `includedSpend` in dollars, without a descriptor
- **And** a cycle longer than one day is a long period, so it uses the average pace since `billingCycleStart` (core 12 AC13).

### AC2: Other amounts stay unsupported

- **Given** any of the following cases
- **When** the provider maps the response
- **Then** none of them carries a descriptor, and none shows forecast UI (core 12 AC2):
  - `includedSpend` stops at `limit` while use continues.
  - Bonus credits are spend with no limit.
  - On-demand and pooled spend carry no reset, and their period is not verified.
  - The Auto and API percentages are details, not lines, and their caps are not reported.
  - The legacy `individualUsage.plan` shape has no verified meaning for its percentage (providers 07).
  - The plan is unlimited.
  - `totalPercentUsed` is missing.
  - The billing cycle is missing, unparseable, or ends before it starts.

### AC3: The included line has an ID and the headline stays the provider's

- **Given** the provider builds lines
- **When** it assigns IDs
- **Then** the included-usage line has the ID `included-usage`
- **And** the quota names no headline line, and the lines have no limit group
- **And** this is because on-demand spend can continue after included usage is full. "Limit reached" in the headline would then be wrong (core 12 AC9)
- **And** the forecast appears only in the included-usage row, e.g. "Runs out in about 9d · last 504 hours"
- **And** the row's bar and its forecast both read `totalPercentUsed`
- **And** the headline keeps the money left and the reset countdown.

### AC4: Timing is approximate

- **Given** a successful live response
- **When** the provider maps it
- **Then** the observation is `.fresh` with approximate receipt timing
- **And** `lastUpdated` and the descriptor use one receipt time
- **And** the delay before a request reaches the response is a documented limitation: Cursor serves these numbers from a cache that refreshes periodically (Evidence).

### AC5: Rate limiting keeps its existing handling

- **Given** a 429 response or an active backoff
- **When** a refresh is attempted
- **Then** no observation is recorded and the backoff is unchanged
- **And** `totalPercentUsed` at or above 100 is exhaustion reported by the provider (core 12 AC7).

### AC6: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover:
  - the descriptor
  - a captured response whose `includedSpend` is at `limit` while the total percentage is not, which is not exhaustion
  - cycles of 28, 30, and 31 days read from the response
  - a cycle rollover into a new period
  - an upgrade that restarts the cycle
  - a percentage drop within a cycle, as when Cursor raises a cap
  - the legacy shape
  - an unlimited plan
  - a missing total percentage
  - included dollars, bonus, on-demand, and pooled spend without descriptors
  - a missing or inverted cycle
  - repeated reads that are no change to Smart refresh
  - a total percentage at 100.

## Plan

1. [x] Confirm the billing cycle. Cursor is not installed on this Mac, so public evidence stands in for a capture, as in (providers 20). The answers to the four questions:
   - `billingCycleStart` and `billingCycleEnd` stay put within a cycle. The cycle starts at the moment of subscription, and an upgrade restarts it.
   - How soon a request reaches the response is not documented. The numbers come from a cache, which froze for days until about 2026-08-14.
   - `includedSpend` stops at `limit`. Use continues from bonus credit.
   - `totalPercentUsed` does not match `includedSpend` divided by `limit`. Cursor calls it a different internal metric.
2. [x] Add the line ID, one receipt time, and `.fresh`. The receipt time is taken when the usage response arrives, before decoding.
3. [x] Add the descriptor for the `planUsage` shape only. It lives in `CursorProvider+ActivityObservation.swift`.
4. [x] Add the fixtures and tests from AC6. Existing tests that compare whole metrics compare ID, kind, and value instead, because descriptors carry the receipt time. Synthetic responses cover each case. An hour-by-hour replay rolls a 31-day cycle into a 30-day one.
5. [x] Move the descriptor from `includedSpend` to `totalPercentUsed`, after the evidence of step 1. The first version would have said "Runs out" when only the dollar figure stopped.

### Evidence

**Public sources, read on 2026-10-13:**

- [Cursor billing help](https://cursor.com/help/account-and-billing/billing), undated:
  - "Your cycle starts on the date you subscribe."
  - "Individual plans reset monthly."
  - "Teams plans renew on the team signup date."
- Cursor staff on forum.cursor.com:
  - t/168136/8: "included usage resets at your subscription's anchor time (when you first subscribed), not midnight".
  - t/164974/14, on an upgrade: "the billing cycle resets, so the new period starts immediately".
  - t/168210/7: the percent fields "are not calculated as a simple totalSpend / limit. They reflect a different internal metric". The `displayMessage` uses `includedSpend` divided by `limit`.
  - t/168140/7: the numbers come "from a cached aggregate, and for active accounts it can lag or freeze on the last value". t/157133/5: they refresh "periodically, not in real-time".
  - t/164663/4, the order of use: "Auto + Composer (included) → API (included) → On-Demand (if enabled) → blocked."
  - t/169032/5: named third-party models draw only from the API pool.
- Public captures:
  - maxh213/dandelion `tasks/006-cursor.md`, an Ultra plan: cycle 2026-08-30T16:45:06Z to 2026-09-30T16:45:06Z, `includedSpend` 40000 at `limit` 40000, `totalPercentUsed` 31.09.
  - auerbachb/claude-code-config `ai-quotas.md`: `includedSpend` 40000 at `limit` 40000, bonus 157210, `apiPercentUsed` 100, `totalPercentUsed` 56.35.
  - CodexBar #154 and litianyi-007/cusor-usage: cycles exactly one calendar month long, to the second.
  - No public capture starts on the 29th to the 31st, so month-end handling is unknown. The provider reads both dates, so it needs no rule.
- Every capture fits `totalPercentUsed` = (`includedSpend` + `bonusSpend`) / (Auto cap + API cap). The caps are inferred, not reported, and the Auto caps have grown more than once during 2026.

## Risks

- "Runs out" refers to included usage. With on-demand spend enabled, work continues after it. The row label says "Included usage", but a user can still read it as a hard stop.
- The API pool can block named models, such as Opus, while the total is far below 100. Only the API detail under the row shows this.
- When Cursor raises a cap, the total percentage drops within a cycle. The average still counts from the cycle start, so the forecast turns optimistic for the rest of the cycle.
- A cached value that freezes reads as no use, so the average pace falls until it catches up.
- CodexBar #2614 lost its Cursor forecast, which needs both cycle dates, for two to three days after a plan switch. The cause was not confirmed. The same would hide this row's forecast.
- Teams Premium seats can omit `totalPercentUsed`, so they show no forecast.
- The endpoint is undocumented (providers 07). A change of shape drops the descriptor; it does not break the lines.
- A long period shows no forecast text during its first day (core 12 AC13).
- Evidence spans count only hours and minutes, so three weeks read "last 504 hours". The same wording already applies to every weekly window. A fix belongs in (core 12), not here.

## Objective

Opt Kimi Code's weekly and monthly windows into allowance forecasting (core 12) and calendar-month pacing (ui 39), next to the five-hour window from (providers 29).

## Context

- Status: implemented, 2026-10-30, uncommitted. The manual check in Plan step 4 is open. Uses the shared calendar-month rule from (ui 39). Builds on (providers 29), which already forecasts the five-hour window and adds the optional period length to each window. Follows the shape of (providers 20). Closes the forecasting item in (providers 24, Out of scope).
- The user asked on 2026-10-27 for the Kimi Code monthly row to match the Codex weekly row, forecast line included: "Runs out in about 5d 13h · 29 hours of history".
- `Sources/Providers/KimiCode/KimiCodeProvider+Mapping.swift`:
  - Lines already have IDs (`five-hour-usage`, `weekly-usage`, `monthly-usage`) and the shared `membership` limit group.
  - The monthly line declares `UsageWindowDuration.month`, 30 days.
  - The observation is `.fresh`. Only the five-hour metric carries a forecast descriptor (providers 29).
  - `headlineUsageLineId` names the tightest window, normally the five-hour line (providers 24 AC5).
- Evidence on windows (providers 24, Evidence; providers 27, Live capture):
  - The five-hour window is a fixed block on a 5-hour grid, not a rolling window. A live capture showed it (providers 29, Evidence). The `:50`/`:51` flip of its `reset_time` is reset jitter.
  - The monthly pool resets on the subscription day at `00:00:00Z`. The user's account reads `2026-11-27T00:00:00Z` on 2026-10-27, a 31-day period. When it runs out, Kimi Code is frozen until the reset.
  - The weekly window exists only on legacy plans. It comes from `usage` and `limit_7d`, with a subscription-anchored reset. The user's new plan has no weekly window.
  - Ratios carry two decimals of a percentage. Legacy counters are whole percentages, rounded to nearest. The merge keeps the ratio when the two agree within 1 point (providers 27 AC3).
- `Tests/KimiCodeProviderTests/` — mapping and fixture tests, including `usages-live-new-plan.json`.

## Acceptance Criteria

### AC1: The five-hour window keeps its descriptor

- **Given** the five-hour window
- **When** the provider maps it
- **Then** its metric carries the 5-hour descriptor from (providers 29 AC2), unchanged by this spec.

### AC2: Weekly and monthly windows carry fixed-period descriptors

- **Given** a weekly or monthly window with a reset date
- **When** the provider maps it
- **Then** its metric carries a fixed-period descriptor:
  - Its limit is 100, and its reset is the window's reset date.
  - The weekly length is 7 days.
  - The monthly length is `UsageWindowDuration.calendarMonth(endingAt:)` (ui 39 AC1).
  - Its unit is percentage points, with resolution 0.01.
  - Its timing is the receipt time, and its usage line ID is the line's ID.
- **And** both are long periods, so they use the average pace since the period started (core 12 AC13)
- **And** a window without a reset date carries no descriptor.

### AC3: The monthly line declares its real length

- **Given** a monthly window with a reset date
- **When** the provider maps it
- **Then** the line's `windowDuration` equals the descriptor's length, e.g. 31 days for a reset on `2026-11-27T00:00:00Z`
- **And** the row gets monthly pacing with a daily allowance (ui 39 AC3, AC4)
- **And** a monthly window without a reset date has no `windowDuration`, and keeps the standard row.

### AC4: Existing headline and limit group stay

- **Given** a mapped response
- **When** the forecast UI is built
- **Then** `headlineUsageLineId` still names the tightest window, so the headline speaks only for that line (core 12 AC15)
- **And** all three lines keep the `membership` limit group, because any full window freezes Kimi Code (core 12 AC8)
- **And** the five-hour descriptor from (providers 29) stays unchanged.

### AC5: Activity metrics are unchanged apart from the descriptor

- **Given** a mapped response
- **When** the provider builds its activity observation
- **Then** each metric keeps its ID, kind, unrounded value, and `.fresh` freshness (providers 27 AC5)
- **And** the descriptor's reset and length stay the same across reads within one period, so Smart refresh sees no false change (core 11).

### AC6: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover the live new-plan fixture (no weekly descriptor, monthly 31 days, five-hour descriptor unchanged from (providers 29)), a legacy-plan fixture with a weekly descriptor, a window without a reset, a monthly rollover, a monthly reset in February and on a month's last day, and a window pinned at 100 as exhaustion (core 12 AC7).

### AC7: The package builds clean

- **Given** a fresh checkout after the change
- **When** the validation gate runs
- **Then** format, lint, both builds, and `swift test` pass with zero warnings, and `KimiCodeProvider` depends only on `Core`.

## Plan

1. [x] Land (ui 39) steps 1–4 first. Merged in #107.
2. [x] Mapping: each window has one duration, from its reset date. Five hours and 7 days are fixed. Monthly comes from the Core rule. The line's `windowDuration` and the descriptor both use it, and a window without a reset gets no descriptor. Remove `UsageWindowDuration.month`, which no provider declares now (ui 39, Plan step 1).
3. [x] Tests from AC6. Synthetic bodies cover the rollover and the month-end cases. No new live capture is needed for the mapping.
4. [ ] Manual check with the user's account: the monthly row shows the pace bar and "/day" text at once. The forecast line appears only after a day of use, as (core 12 AC13) requires.
5. [x] Update (providers 24, Out of scope) and (core 12) step 11 with this spec.

## Implementation findings

- The separate forecast period length from (providers 29) is gone. Every Kimi window is now a fixed period, so its line duration and its descriptor length are the same value.
- Removing `UsageWindowDuration.month` changed three tests outside Kimi Code: the Core constant test, a 30-day pacing test, and a precision test. They now use literal day counts.
- The monthly metric of `usages-monthly-plan.json` now carries a descriptor, so its activity test expects one.

## Risks

- **No forecast for the first day.** The user's period started on 2026-10-27, so no "Runs out" text shows until 2026-10-28. This is (core 12 AC13) as designed.
- **Mixed precision.** The resolution is 0.01, but a legacy counter can win the merge and move in whole points. For long periods the average pace absorbs this. A whole-point jump only reaches learning sooner.
- **Readings can step back.** When the merge switches from a higher legacy reading to an agreeing ratio, the value can drop by up to 1 point. Core reads a drop as a correction and starts a new baseline (core 12 AC3). Forecast text then waits for new evidence.
- **Unknown month-end rule.** See (ui 39, Risks). A period that starts earlier than assumed makes the average pace read faster, never slower.
- **Weekly is untested live.** No legacy-plan account is available, so the weekly descriptor relies on public captures and synthetic tests.

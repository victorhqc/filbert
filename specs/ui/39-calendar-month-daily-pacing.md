## Objective

Pace monthly rows over their real calendar-month length, and show the sustainable daily allowance that weekly rows already show.

## Context

- Status: implemented and on `main` (#107). The manual check in Plan step 6 is open. Supersedes (ui 22 AC2, AC3, AC4, AC6), and parts of (ui 22 AC1, AC5, AC11), where they fix the month at 30 days and the allowance at one week. Keeps (ui 19) for weekly rows.
- The user asked on 2026-10-27 for the Kimi Code "Monthly" row to read like the Codex "Weekly" row: a pace bar, an elapsed marker, the time left, and "About N.N%/day available". They chose a daily allowance for monthly rows over the weekly one from (ui 22).
- Why the Kimi row shows a plain bar today:
  - Kimi's monthly pool resets on the subscription day at 00:00 UTC. The live capture of 2026-10-27 reads `reset_time` `2026-11-27T00:00:00Z`, so this period is 31 days (providers 27, Live capture).
  - `BudgetPace` accepts a monthly line only when `windowDuration` is exactly 30 days and at most 30 days remain (ui 22 AC2, AC10). At 30d 14h left, the line falls back to the standard row.
  - OpenCode Go has the same gap. Its monthly line also declares 30 days, while its period runs 28 to 31 days (providers 20 AC2). In a 31-day period it loses pacing for the first day, and its elapsed marker is off by up to 3 days.
- `Sources/Core/ProviderProtocol.swift` — `UsageWindowDuration.month` is exactly 30 days. It gains a calendar-month rule that providers can share.
- `Sources/Providers/OpenCodeGo/OpenCodeGoProvider+Mapping.swift` — `monthlyPeriodLength(resetsAt:)` holds that rule today, for the forecast descriptor only. It moves to Core, unchanged.
- `Sources/App/BudgetPace.swift` — `Configuration` pairs one exact window duration with an allowance unit and a divider interval. `AllowanceUnit.week` exists only for monthly rows.
- `Sources/App/PacedUsageLineText.swift` — "About %@%%/week available" is used only by monthly rows.
- `Sources/App/UsageLineRow.swift` — draws dividers from `configuration.dividerFractions`.
- `Sources/App/QuotaStatusResolver.swift` — the compact tier reuses `BudgetPace`, so it follows without its own change (ui 22 AC8).
- `Tests/AppTests/MonthlyBudgetPaceTests.swift`, `Tests/AppTests/BudgetPaceTests.swift`, `Tests/OpenCodeGoProviderTests/` — monthly calculations, weekly regression, and the OpenCode Go mapping.
- Kimi Code adopts the Core rule in (providers 28).
- Cursor's billing cycle is not a percentage line with a `windowDuration`, so it is out of scope.

## Acceptance Criteria

### AC1: Core shares the calendar-month rule

- **Given** a monthly reset date
- **When** a provider calls `UsageWindowDuration.calendarMonth(endingAt:)`
- **Then** it returns the length of the period that ends at that reset, in whole days, computed in UTC
- **And** the period starts one calendar month before the reset, at the same UTC time, with the day capped at the end of that month
- **And** a reset on the last day of its month starts the period on the last day of the previous month, the latest possible start (providers 20 AC2)
- **And** the result is always 28, 29, 30, or 31 days
- **And** `UsageWindowDuration.calendarMonths` is the range 28 days through 31 days.

### AC2: OpenCode Go uses the shared rule

- **Given** an OpenCode Go monthly window
- **When** the provider maps it
- **Then** the line's `windowDuration` and the forecast descriptor's length are both `calendarMonth(endingAt: resetsAt)`
- **And** the private `monthlyPeriodLength(resetsAt:)` is removed
- **And** every other OpenCode Go output is unchanged.

### AC3: Any calendar-month line gets monthly pacing

- **Given** a percentage line whose `windowDuration` is within `calendarMonths`
- **When** its reset is in the future and the time left does not exceed its `windowDuration`
- **Then** the row uses the paced presentation
- **And** the elapsed marker is `1 - (resetDate - now) / windowDuration`, clamped from zero through one
- **And** a line with any other duration, or with missing, expired, non-finite, or inconsistent data, keeps the standard row and raw-percentage tier (ui 22 AC10)
- **And** weekly lines still need exactly 7 days (ui 19).

### AC4: Monthly rows show a daily allowance

- **Given** an eligible monthly line with at least 24 hours left
- **When** it renders
- **Then** the footer reads "About N.N%/day available"
- **And** `availablePerDay = remainingPercentage / (remainingTime / 86,400)`, with unrounded values
- **And** with less than 24 hours left it reads "N% available until reset" (ui 19 AC4)
- **And** e.g. 3.30% used with 30d 14h left reads "About 3.2%/day available"
- **And** "About %@%%/week available" and `AllowanceUnit.week` are removed.

### AC5: The tier uses the daily allowance

- **Given** an eligible monthly line
- **When** the app resolves its tier
- **Then** `warningBoundary = min(elapsedPercentage + allowance, 100)`, where the allowance is the daily or until-reset allowance from AC4
- **And** the one-point tolerance and critical precedence of (ui 19 AC3) apply
- **And** the collapsed card uses the same tier when the monthly line drives it (ui 22 AC8).

### AC6: Dividers mark weeks of the real month

- **Given** an eligible monthly line
- **When** its bar renders
- **Then** dividers sit at days 7, 14, 21, and 28 of the line's own `windowDuration`
- **And** a 28-day month has dividers at days 7, 14, and 21 only
- **And** weekly rows keep their six daily dividers.

### AC7: Accessibility follows the new allowance

- **Given** VoiceOver on an eligible monthly row
- **When** it reads the row
- **Then** it announces the daily or until-reset allowance, using the same strings as weekly rows (ui 22 AC11).

### AC8: Weekly rows and other providers are unchanged

- **Given** the change is in
- **When** any weekly, five-hour, or untimed line renders
- **Then** its text, tier, dividers, and marker are unchanged
- **And** no App code names a provider.

### AC9: The package builds clean

- **Given** a fresh checkout after the change
- **When** the validation gate runs
- **Then** format, lint, both builds, and `swift test` pass with zero warnings.

## Plan

1. [x] Core: move the calendar-month rule into `UsageWindowDuration.calendarMonth(endingAt:)`, and add `calendarMonths`. Keep `month`: Kimi Code still declares it, and (providers 28) removes it. Until then, its 30-day line is within `calendarMonths` and gets the daily allowance. Tests: resets on the 27th of a 31-day month, on Feb 28 and 29, on Mar 31, on Apr 30, and with millisecond jitter.
2. [x] OpenCode Go: use the Core rule for the line and the descriptor. Update its monthly fixture tests to expect the real length.
3. [x] App: replace the fixed `windowDuration` in `BudgetPace.Configuration` with an eligibility check. Weekly is exactly 7 days. Monthly is within `calendarMonths`. Both use the daily allowance. Dividers come from the line's duration. Remove `AllowanceUnit.week` and the weekly-allowance string in every locale.
4. [x] Tests: the Kimi case from AC4 (31 days, 3.30%, 30d 14h left), a 28-day and a 31-day month at start, middle, and end, the 24-hour switch, the tier boundary, compact parity, the divider positions from AC6, and the weekly regression tests unchanged.
5. [x] Mark the superseded criteria in (ui 22) with a pointer to this spec.
6. [ ] Manual check: Kimi Code (after providers 28) and OpenCode Go, both with a monthly pace bar and "/day" text.

### Implementation findings

- The rule lives in `Sources/Core/UsageWindowDuration+CalendarMonth.swift`, because `ProviderProtocol.swift` is at its lint length limit. It returns an optional, like the code it replaces; a `nil` gives OpenCode Go's monthly line no `windowDuration`. A sweep over every day from 2026 through 2028 always returns whole days within `calendarMonths`.
- `AllowanceUnit` is gone, not only its `week` case. Both row types use a day, so `Allowance.perUnit` became `.perDay`.
- One compact-tier test used 45% at day 11 of 30 as "good". Under a daily allowance it is still over the allowance (Risks, "Monthly rows warn sooner"), so the test now checks day 19 of 31.
- Kimi Code's monthly line still declares 30 days (Plan step 1). It is within `calendarMonths`, so it already shows the daily allowance once less than 30 days remain. Its marker reads one day early in a 31-day period until (providers 28).

## Risks

- **Monthly rows warn sooner.** A weekly allowance put the warning boundary about 22 points ahead of the marker. A daily one puts it about 3 points ahead. A heavy first day of the month now shows the warning tier. This matches the weekly row, and the user chose it.
- **Unknown month-end rule for Kimi.** The latest-start rule comes from OpenCode Go's source. For a reset on a month's last day, the real period can start up to 3 days earlier. The marker then reads early, and the daily allowance stays correct, because it uses only the time left.
- **Dense bars.** A 31-day bar with four dividers and a three-day tail is the same geometry as (ui 22). No new crowding.
- **Removed string.** Translators lose "About %@%%/week available". No other row uses it.

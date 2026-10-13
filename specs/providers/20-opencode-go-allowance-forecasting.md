## Objective

Opt OpenCode Go's weekly and monthly windows into allowance forecasting (core 12), and leave the sliding five-hour window unsupported.

## Context

- Status: implemented, without live data. On 2026-10-13 the user chose the upstream source, public reports, and synthetic fixtures instead (Evidence). Depends on (core 12), which is on `main`.
- `Sources/Providers/OpenCodeGo/OpenCodeGoProvider.swift` — maps the `rolling-window-usage`, `weekly-window-usage`, and `monthly-window-usage` metrics from a live HTTPS request. Freshness is `.unknown` today. Lines have no IDs and no limit group.
- Since 2026-10-11, `/zen/go/v1/usage` forwards to a separate inference service whose code is not public (anomalyco/opencode#54563). Migrated accounts used that service from 2026-09-09 (#48123). The window rules in Evidence come from the last version that computed them in the open repository.
- Live evidence (providers 10):
  - `percent` is an integer, rounded down, and pinned at 100 when rate-limited.
  - The five-hour `rolling` window slides with the latest usage.
  - The weekly window follows the calendar week. The monthly window is anchored to the subscription.
  - `resetsAt` milliseconds track fetch time.
  - Usage lands a few seconds after a request completes.
- One point is about $0.30 of the weekly window and $0.60 of the monthly window. A forecast needs two points within the maximum horizon (core 12).
- `Tests/OpenCodeGoProviderTests/` — mapping and fixture tests.

## Acceptance Criteria

### AC1: The sliding window stays unsupported

- **Given** the `rolling` window
- **When** the provider maps it
- **Then** it carries no descriptor and shows no forecast UI (core 12 AC2).

### AC2: Weekly and monthly windows map to typed descriptors

- **Given** the weekly or monthly window
- **When** the provider maps it
- **Then** the metric carries a fixed-period descriptor with limit 100, the window's `resetsAt`, a period length, unit percentage points, and resolution 1
- **And** the weekly length is 7 days
- **And** the monthly period starts one calendar month before `resetsAt`, at the same UTC time, with the day capped at the end of that month. When `resetsAt` falls on the last day of its month, the period starts on the last day of the previous month. Several subscription days share such a reset, and this is the latest start among them, so an unknown subscription day can only make the pace look faster, never slower
- **And** both are long periods, so they use the average pace since the period started (core 12 AC13)
- **And** the provider passes `resetsAt` unchanged; Core's reset tolerance absorbs millisecond jitter (core 12 AC3)
- **And** the `UsageLine` ID equals the metric ID
- **And** the provider names no headline line, because its headline is a fixed label, so weekly and monthly forecasts appear only inside their rows and the headline rules of (core 12 AC9) do not apply
- **And** all three windows share one limit group, including the unsupported rolling window, because any of them blocks usage.

### AC3: Timing is approximate

- **Given** a successful live response
- **When** the provider maps it
- **Then** the observation is `.fresh` with approximate receipt timing.

### AC4: Rate limiting keeps its existing handling

- **Given** a 429 response or an active backoff
- **When** a refresh is attempted
- **Then** no observation is recorded and the backoff is unchanged
- **And** a window at 100 percent is exhaustion reported by the provider (core 12 AC7).

### AC5: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover the unsupported rolling window, weekly and monthly descriptors, `resetsAt` jitter, a calendar-week rollover, a subscription-anchored monthly rollover, monthly periods in months of different lengths including a reset on the last day of a short month, and a window pinned at 100.

## Plan

1. [x] Confirm the window rules, because the current service is not public. No live key is available, so public reports stand in for a capture (Evidence). They match the source, but none is later than 2026-10-11.
2. [x] Add descriptors for the weekly and monthly windows only, line IDs, the limit group, `.fresh`, and receipt timing. The mapping moved to `OpenCodeGoProvider+Mapping.swift`. The monthly length counts whole days between the two anchors, so millisecond jitter in `resetsAt` never changes it.
3. [x] Add the fixtures and tests from AC5. Without live data, synthetic responses cover each case: the rolling window without a descriptor, both descriptors, jitter that keeps one period and is no change to Smart refresh, a Monday rollover over a full week of reads, a monthly rollover on the anchor, monthly lengths across months including resets on the last day of a short month, and a window pinned at 100 as exhaustion.

### Evidence

**Upstream source, anomalyco/opencode `5caf1f9f6`, the last version that computed the windows in the open repository, read on 2026-10-13:**

- `routes/zen/go/v1/usage.ts` sends `resetsAt` as the fetch time plus `resetInSec`, and `resetInSec` rounds the seconds left up. A reset therefore reads up to one second late, and the milliseconds follow the fetch time.
- `percent` is `Math.floor(min(100, usage / limit × 100))`, and 100 when rate-limited (`subscription.ts`).
- The rolling window ends `rollingWindow` hours after the last usage update. It is 0 percent when that update is older than the window.
- The weekly window runs from Monday 00:00 UTC to the next Monday 00:00 UTC (`getWeekBounds` in `util/date.ts`). UTC has no daylight saving time, so it always lasts 7 days.
- The monthly window runs between two anchors on the subscription's UTC day and time. In a shorter month, the day is capped at the last day of that month (`getMonthlyBounds`). A subscription on the 31st has periods of 28 to 31 days.
- A window whose last usage update is older than its start reads 0 percent with the new reset.

**Public reports from live responses:**

- anomalyco/opencode#53701, 2026-10-07: `percent` values 0, 0, and 31, floored, where the dashboard showed one decimal. The weekly `resetsAt` was `2026-10-12T00:00:00`, a Monday at 00:00 UTC. The monthly reset was on Oct 21, a subscription day rather than the first of the month.
- #54284, 2026-10-10: a live Go key still returned only `usage`. The pull request was closed, and the new backend serves migrated workspaces.
- #52506 and the reports it links: server-side meter errors raised windows, and later corrections lowered them within a period.

## Risks

- Rounding down to whole points means weekly and monthly forecasts appear only under sustained heavy use. Most of the time these rows show learning and then no forecast text.
- Asynchronous usage landing can shift a step into a later observation and create an apparent burst.
- The usage service is not public, so its window rules can change without a source change to read. Drift fixtures catch a change of shape, not a change of rule.
- When the subscription day is unknown, the monthly period can start up to 3 days later than it really does. Early in such a period, the average pace reads faster than it is.
- A server-side correction that lowers a window reads as a correction, and Core starts a new baseline (core 12 AC3).

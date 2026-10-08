## Objective

Opt OpenCode Go's weekly and monthly windows into allowance forecasting (core 12), and leave the sliding five-hour window unsupported.

## Context

- Status: draft for review. Depends on (core 12).
- `Sources/Providers/OpenCodeGo/OpenCodeGoProvider.swift` — maps the `rolling-window-usage`, `weekly-window-usage`, and `monthly-window-usage` metrics from a live HTTPS request. Freshness is `.unknown` today.
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
- **Then** the metric carries a fixed-period descriptor with limit 100, the window's `resetsAt`, unit percentage points, and resolution 1
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
- **Then** they cover the unsupported rolling window, weekly and monthly descriptors, `resetsAt` jitter, a calendar-week rollover, a subscription-anchored monthly rollover, and a window pinned at 100.

## Plan

1. Add descriptors and line IDs for the weekly and monthly windows only.
2. Add the fixtures and tests from AC5.

## Risks

- Rounding down to whole points means weekly and monthly forecasts appear only under sustained heavy use. Most of the time these rows show learning and then no forecast text.
- Asynchronous usage landing can shift a step into a later observation and create an apparent burst.

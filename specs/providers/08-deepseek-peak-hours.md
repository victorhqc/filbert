## Objective

Expose DeepSeek's upcoming peak/off-peak billing in the existing provider-agnostic peak-hours UI.

## Context

- `Sources/Core/ProviderProtocol.swift` — `PeakHoursConfig` currently supports one daily window and no future effective date; DeepSeek needs two windows and must not appear active before launch.
- `Sources/Providers/DeepSeek/DeepSeekProvider.swift` — supplies DeepSeek-owned pricing metadata alongside the existing balance response (providers 04).
- `Sources/Providers/ZAI/ZAIProvider.swift` — migrates its single-window metadata to the generalized shape without changing Z.AI behavior (providers 01, ui 04).
- `Sources/App/QuotaView.swift` — renders every configured peak window in local time and distinguishes scheduled pricing from active peak/off-peak pricing without branching on provider ID (ui 04).
- `Tests/CoreTests/PeakHoursConfigTests.swift` — covers multiple windows, effective-date boundaries, and existing multiplier behavior.
- `Tests/DeepSeekProviderTests/DeepSeekProviderTests.swift` and `Tests/ZAIProviderTests/ZAIProviderTests.swift` — verify each provider publishes only its own schedule.
- DeepSeek's official [Models & Pricing](https://api-docs.deepseek.com/quick_start/pricing/) page, verified 2026-08-14, defines daily peak windows of `01:00–04:00` and `06:00–10:00` UTC, peak rates at twice off-peak rates, and an effective instant of `2026-08-16 16:00 UTC`.

## Acceptance Criteria

### AC1: Peak-hours metadata supports multiple daily windows
- **Given** a provider with one or more non-overlapping peak windows in a named time zone
- **When** `PeakHoursConfig` evaluates an instant
- **Then** the instant is in peak when its local time falls inside any configured half-open window
- **And** existing single-window providers retain the same boundary behavior

### AC2: Future pricing remains visibly scheduled until activation
- **Given** a peak-hours configuration with an effective date in the future
- **When** the popover renders it before that instant
- **Then** the block identifies the pricing as upcoming and shows the localized effective date
- **And** it does not claim that the current time is in peak, off peak, or subject to a multiplier
- **And** at the effective instant the block switches to the active peak/off-peak status

### AC3: Every peak window is shown in the user's local time
- **Given** a peak-hours configuration with multiple windows
- **When** the popover renders the peak-hours block
- **Then** every window is converted from the provider's time zone to the user's current time zone
- **And** the windows are displayed in schedule order in one localized line without truncating the provider card

### AC4: DeepSeek publishes the announced schedule
- **Given** a successful DeepSeek balance response
- **When** `DeepSeekProvider` maps it to `ProviderQuota`
- **Then** `peakHoursConfig` contains UTC windows `01:00–04:00` and `06:00–10:00`
- **And** its peak multiplier is `2`, its off-peak multiplier is `1`, and its effective date is `2026-08-16 16:00 UTC`
- **And** the existing balance headline, lines, and activity observation remain unchanged (providers 04)

### AC5: DeepSeek status follows both windows and exact boundaries
- **Given** DeepSeek's active schedule
- **When** an instant falls at `01:00`, before `04:00`, at `06:00`, or before `10:00` UTC
- **Then** it is in peak and reports a `2×` multiplier
- **And** at `04:00`, before `06:00`, at `10:00`, or outside both windows it is off peak and reports a `1×` multiplier

### AC6: Z.AI behavior is preserved
- **Given** the generalized peak-hours model
- **When** Z.AI supplies its existing schedule
- **Then** its `14:00–18:00 Asia/Shanghai` window, peak and off-peak multipliers, and promotional cutoff behave exactly as before (ui 04)
- **And** neither provider module imports or references the other

### AC7: The change passes the repository validation gate
- **Given** a fresh checkout with the implementation applied
- **When** the documented validation commands run
- **Then** formatting, the full test suite, strict concurrency checks, release build, and static analysis complete without warnings or errors

## Plan

1. Replace the single start/end pair in `PeakHoursConfig` with a small `PeakHoursWindow` value and an ordered array of windows. Add an optional effective date and queries for whether a schedule is active and whether an instant falls in any window.
2. Update `PeakHoursBlock` to format all windows in local time. Before the effective instant, render an upcoming-pricing state; afterward, retain the current peak/off-peak dot and multiplier presentation.
3. Add DeepSeek-owned constants for the two UTC windows, `2×`/`1×` multipliers, and the effective instant, then attach that configuration while mapping a successful balance response.
4. Migrate Z.AI to the array-based initializer with its existing single window and promotional cutoff unchanged.
5. Add focused Core boundary tests, provider metadata tests for DeepSeek and Z.AI, and localized strings for the upcoming state.

## Risks

- Local-time conversion can move a UTC window to the previous or next calendar day. The UI shows times rather than day labels, matching the existing compact presentation, while schedule evaluation remains in the provider time zone.
- A future DeepSeek announcement could change the effective instant or schedule. All values remain isolated in the DeepSeek module and are sourced from the official pricing page.
- Generalizing `PeakHoursConfig` touches Z.AI's existing presentation path. Regression tests must cover its window boundaries and promotional multiplier cutoff before handoff.

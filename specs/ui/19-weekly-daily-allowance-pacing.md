## Objective

Keep weekly usage in the good tier while it remains within the current dynamically calculated allowance, so early-window activity does not produce a premature warning.

## Context

- `Sources/App/WeeklyBudgetPace.swift` — currently compares usage directly with exact elapsed time, even though it already calculates a sustainable allowance from the remaining budget and exact remaining time (ui 18).
- `Sources/App/UsageLineRow.swift` — displays that dynamic daily or until-reset allowance and must describe the revised tier meaning consistently.
- `Sources/App/QuotaStatusResolver.swift` — applies the weekly tier to a collapsed card when its compact percentage represents the same weekly line.
- `Tests/AppTests/WeeklyBudgetPaceTests.swift` — covers weekly calculations, tier boundaries, compact status, and malformed timing data.
- `Sources/App/Resources/Localizable.xcstrings` — localizes the revised accessibility status text.

## Acceptance Criteria

### AC1: The warning boundary includes the current dynamic allowance
- **Given** an eligible weekly line with clamped usage, a valid elapsed marker, and at least 24 hours remaining
- **When** the app calculates its warning boundary
- **Then** `remainingPercentage = max(100 - usedPercentage, 0)`
- **And** `remainingDays = (resetDate - now) / 86,400` using the exact positive fractional value
- **And** `availablePerDay = remainingPercentage / remainingDays`
- **And** `elapsedPercentage = elapsedFraction * 100`
- **And** `warningBoundary = min(elapsedPercentage + availablePerDay, 100)`
- **And** the boundary is recalculated from the current usage and remaining time rather than from a fixed `100 / 7` allowance, a rounded day count, or a seven-segment index

### AC2: Early weekly usage does not warn prematurely
- **Given** an eligible weekly line at approximately one hour into its window with 3% used and 6 days 23 hours remaining
- **When** the app calculates the dynamic allowance and tier
- **Then** the remaining daily allowance is approximately 13.9 percentage points
- **And** the warning boundary is approximately 14.5% before display tolerance
- **And** the row uses the good tier
- **And** the same inputs produce the same tier regardless of provider

### AC3: Tiers use the dynamic boundary
- **Given** an eligible weekly line below 100% usage
- **When** its usage is at or below the dynamic warning boundary, allowing the existing one-percentage-point display tolerance
- **Then** the weekly pace uses the good tier
- **When** its usage exceeds that tolerated boundary
- **Then** the weekly pace uses the warning tier
- **When** its usage reaches or exceeds 100%
- **Then** the weekly pace uses the critical tier
- **And** the critical tier takes precedence over any remaining allowance or tolerance

### AC4: The final partial day uses the until-reset allowance
- **Given** an eligible weekly line with less than 24 hours remaining
- **When** the app calculates its warning boundary
- **Then** the allowance added to the elapsed percentage is the full `remainingPercentage` shown as available until reset
- **And** the warning boundary is clamped to 100%
- **And** the app does not calculate or display a greater-than-100% daily rate

### AC5: The marker and color answer different pace questions
- **Given** an eligible weekly line whose fill extends beyond the exact elapsed marker but remains within the dynamic warning boundary
- **When** the pace bar renders
- **Then** the marker continues to show the exact elapsed fraction of the seven-day window from (ui 18)
- **And** the fill uses the good tier color because the current dynamic allowance has not been exceeded
- **And** the seven visual segments remain guides only and do not determine the tier
- **And** crossing the elapsed marker alone does not change the tier

### AC6: Expanded and compact presentations agree over time
- **Given** a weekly line drives both an expanded row and a collapsed card's compact percentage
- **When** usage or wall-clock time changes the dynamic warning boundary
- **Then** both presentations use the identical weekly tier
- **And** the tier refreshes locally at least once per minute without fetching provider data, reading credentials, or altering refresh scheduling

### AC7: Accessibility describes the allowance-based status
- **Given** VoiceOver is reading an eligible weekly row
- **When** the row is within or beyond the dynamic warning boundary
- **Then** its localized accessibility value describes usage as within the current allowance or over the current allowance
- **And** it continues to announce percentage used, remaining time, and the remaining daily or until-reset allowance from (ui 18)
- **And** it does not call usage merely over pace when it is beyond the exact marker but still within the dynamic allowance

### AC8: Existing fallbacks and unrelated quotas are unchanged
- **Given** a non-weekly line or a weekly line with missing, expired, unsupported, or invalid timing data
- **When** it renders or resolves a compact status
- **Then** it retains the existing fallback and raw-percentage behavior from (ui 04, ui 18)
- **And** provider modules require no changes because the calculation uses generic `UsageLine` timing metadata

## Plan

Extend `WeeklyBudgetPace` with an allowance-based warning boundary derived from its existing remaining-percentage and exact remaining-time calculations. Use the daily allowance while at least 24 hours remain and the full until-reset allowance during the final partial day. Keep the exact elapsed marker and seven visual segments unchanged, but use the new boundary for the expanded-row and compact-card tier.

Update the weekly accessibility status to distinguish the exact pace marker from the allowance-based tier. Add focused tests for the reported early-window scenario, changing usage and remaining time, the tolerated boundary, the final partial day, critical precedence, compact-tier parity, and unchanged malformed and non-weekly fallbacks.

## Risks

- A green fill may extend beyond the exact elapsed marker. The marker remains useful as the linear pace reference, while accessibility and allowance text must make clear that color represents the current spending allowance.
- Because the allowance uses current usage, its size shrinks as budget is consumed. Boundary tests must calculate with unrounded values to prevent color flicker near the displayed threshold.
- The transition into the final 24 hours changes the buffer from a per-day allowance to all budget available until reset. Tests must cover both sides of that boundary.
- A local clock update can change the tier without new provider data. Expanded and compact presentations must continue to share the same pure calculation.

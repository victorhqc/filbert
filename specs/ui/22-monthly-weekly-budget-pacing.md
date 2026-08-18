## Objective

Turn 30-day quota rows into an at-a-glance budget pace visualization that shows usage, time remaining, and the sustainable weekly allowance for the rest of the window.

## Context

- `Sources/Core/ProviderProtocol.swift` — `UsageWindowDuration` has shared five-hour and seven-day values but no shared 30-day value.
- `Sources/Providers/OpenCodeGo/OpenCodeGoProvider.swift` — currently declares its 30-day monthly duration privately and will use the shared duration without changing its request or response mapping (providers 10).
- `Sources/App/WeeklyBudgetPace.swift` — contains the pure calculations introduced for seven-day pacing and will be generalized so weekly and monthly rows share one calculation path (ui 18, ui 19).
- `Sources/App/UsageLineRow.swift` — currently selects and renders paced rows only for seven-day windows.
- `Sources/App/QuotaStatusResolver.swift` — currently applies allowance-based pacing to a collapsed card only when its compact percentage comes from a seven-day line.
- `Tests/CoreTests/ProviderProtocolTests.swift`, `Tests/OpenCodeGoProviderTests/OpenCodeGoProviderTests.swift`, and `Tests/AppTests/WeeklyBudgetPaceTests.swift` — cover duration metadata, provider mapping, calculations, boundaries, and compact-tier parity.
- `Sources/App/Resources/Localizable.xcstrings` — localizes the new weekly-allowance and accessibility text.

## Acceptance Criteria

### AC1: Monthly duration is generic metadata

- **Given** Core describes supported usage-window durations
- **When** a provider reports the existing 30-day monthly window
- **Then** it may use a shared `UsageWindowDuration.month` equal to exactly 30 days
- **And** OpenCode Go replaces its private 30-day constant with that shared value
- **And** no app logic identifies a monthly window by provider ID or localized label

### AC2: Only complete 30-day data enables monthly pacing

- **Given** a percentage-based `UsageLine`
- **When** its duration is exactly `UsageWindowDuration.month`, its reset is in the future, and its remaining time does not exceed 30 days
- **Then** the row uses the monthly budget pace presentation
- **And** a line with missing, unsupported, expired, non-finite, or inconsistent timing or percentage data keeps the existing standard percentage bar and reset presentation from (ui 18)

### AC3: The row answers the monthly budget questions

- **Given** an eligible monthly line
- **When** it renders
- **Then** the header shows the localized label and `NN% used`
- **And** the footer shows a compact remaining time such as `3w 5d left`
- **And** while at least one week remains, the footer shows the sustainable allowance as `about N.N%/week available`
- **And** while less than one week remains, it shows `NN% available until reset` instead of a misleading greater-than-100% weekly rate

### AC4: The monthly calculation uses exact remaining time

- **Given** `usedPercentage`, `resetDate`, a 30-day `windowDuration`, and a supplied `now`
- **When** the app calculates monthly pace
- **Then** `remainingPercentage = max(100 - usedPercentage, 0)`
- **And** `remainingWeeks = max(resetDate - now, 0) / 604,800`
- **And** `availablePerWeek = remainingPercentage / remainingWeeks` while at least one week remains
- **And** the elapsed marker is `1 - ((resetDate - now) / windowDuration)`, clamped from zero through one
- **And** calculations use unrounded values while display formatting rounds only the localized final result

### AC5: The bar marks real weekly boundaries within the month

- **Given** an eligible 30-day line
- **When** its pace bar renders
- **Then** the fill ends at the clamped percentage used
- **And** subtle dividers appear at elapsed days 7, 14, 21, and 28 on the shared zero-to-100 scale
- **And** the final segment represents the actual two-day remainder rather than stretching four weeks to fill 30 days
- **And** a distinct moving marker shows the exact elapsed fraction of the 30-day window
- **And** neither the dividers nor the marker obscure the current fill at the popover's existing width

The intended information hierarchy is:

```text
Monthly                                 30% used
[======|=======|==▲====|=======|--]
3w 5d left                about 21.9%/week available
                 now
```

The four dividers mark completed seven-day intervals. The shorter final segment is the remaining two days in the 30-day window; the diagram is illustrative and spacing may change to fit native SwiftUI rendering.

### AC6: Color uses the current weekly allowance

- **Given** an eligible monthly line with clamped usage and a valid elapsed marker
- **When** at least one week remains
- **Then** `warningBoundary = min(elapsedPercentage + availablePerWeek, 100)` using the exact current values
- **When** less than one week remains
- **Then** the full `remainingPercentage` is used as the until-reset allowance and the warning boundary is clamped to 100
- **And** usage at or below the boundary, with the existing one-percentage-point tolerance, uses the good tier
- **And** usage beyond that tolerance but below 100% uses the warning tier
- **And** usage at or above 100% uses the critical tier

### AC7: Weekly pacing keeps its existing behavior

- **Given** the pacing calculation and presentation are generalized for 30-day windows
- **When** an eligible seven-day line renders or resolves its tier
- **Then** it retains its daily allowance, final-partial-day behavior, six daily dividers, exact elapsed marker, and allowance-based tier from (ui 18, ui 19)
- **And** five-hour, unsupported, and untimed percentage rows retain their existing standard presentation and raw-percentage tiers

### AC8: Expanded and compact monthly status agree

- **Given** an eligible monthly line supplies the compact percentage for a collapsed provider card
- **When** usage or wall-clock time changes its weekly allowance boundary
- **Then** the compact ring and percentage use the same tier as the expanded monthly row
- **And** a monthly line that does not supply the compact percentage does not change the compact tier of a shorter primary window

### AC9: Time-driven values remain current without provider work

- **Given** the popover stays open on an eligible monthly row
- **When** wall-clock time advances
- **Then** the elapsed marker, remaining time, weekly allowance, and expanded and compact tiers refresh locally at least once per minute
- **And** the local refresh does not fetch provider data, read credentials, or alter automatic refresh scheduling

### AC10: Boundary and malformed values fail safely

- **Given** percentage values below zero or above 100
- **When** monthly pace calculates its output
- **Then** visual fill and remaining allowance are clamped to valid bounds without crashing
- **Given** a reset at or before `now`, a non-positive duration, a reset farther in the future than the declared duration, or a non-finite percentage
- **When** the row renders or resolves compact status
- **Then** it falls back to the existing standard and raw-percentage behavior without presenting invented pace information

### AC11: Accessibility and localization carry the same meaning

- **Given** VoiceOver or a non-English locale
- **When** an eligible monthly row renders
- **Then** its accessibility value announces the label, percentage used, remaining time, whether usage is within or over the current allowance, and the remaining weekly or until-reset allowance
- **And** all new visible and accessibility strings use the App String Catalog with localized number and duration formatting
- **And** the visualization does not rely on color alone because the fill-to-marker relationship and accessibility value convey pace independently

### AC12: Provider architecture remains orthogonal and tested

- **Given** monthly pacing is implemented
- **When** another provider supplies the same generic 30-day duration, percentage, and reset metadata
- **Then** it receives the presentation without provider-specific app changes
- **And** provider modules retain no knowledge of pacing calculations or other providers
- **And** focused tests cover duration mapping, start/middle/end calculations, weekly-divider positions, weekly-allowance and final-partial-week boundaries, clamping, malformed timing, expanded/compact parity, weekly regression behavior, and unchanged standard fallbacks

## Plan

Add a shared 30-day duration to Core and use it in OpenCode Go's existing monthly mapping. Generalize the pure weekly pace value into a duration-aware budget pace model whose allowance unit and visual segment interval are explicit presentation configuration: days for seven-day windows and weeks for 30-day windows. Keep reset validation, clamping, elapsed-marker arithmetic, tolerance, and tier resolution shared.

Update the usage row to select the paced presentation for either supported duration, render localized daily or weekly allowance copy, and place dividers from the configured interval rather than a hard-coded count. Reuse the same pure model in compact status resolution and the existing minute-based local timeline. Extend the focused Core, provider, and App tests before running the repository validation gate.

## Risks

- A 30-day window is not four equal weeks. Exact seven-day dividers leave a visibly shorter two-day final segment; keeping that geometry honest may require contrast tuning at the popover's width.
- “Monthly” can mean a 28-, 29-, 30-, or 31-day calendar interval. This change deliberately supports the existing server-described 30-day contract only; other durations retain the standard presentation until their semantics are specified.
- A green fill may extend beyond the exact elapsed marker because color represents the current dynamic allowance, not the linear marker. Accessibility and allowance text must preserve that distinction from (ui 19).
- Generalizing working weekly code can regress its calculations or compact status. Shared model tests must preserve every seven-day boundary before the old weekly-specific names are removed.
- Minute-based local updates can change the tier without new provider data. They must remain pure view updates with no network, Keychain, or scheduling side effects.

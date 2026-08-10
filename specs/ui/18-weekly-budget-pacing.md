## Objective

Turn seven-day quota rows into an at-a-glance budget pace visualization that shows usage, time remaining, and the sustainable allowance for the rest of the window.

## Context

- `Sources/Core/ProviderProtocol.swift` — `UsageLine` has percentage and reset data but no duration, so the app cannot identify seven-day windows without inspecting localized labels (core 01).
- `Sources/Providers/ZAI/ZAIProvider.swift` — maps z.ai's weekly token window and will declare its seven-day duration (providers 01).
- `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift` — maps Claude Code's seven-day window and will declare its duration (providers 02).
- `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` — already receives each rate-limit duration in minutes and will preserve it in `UsageLine` (providers 05).
- `Sources/App/QuotaView.swift` — replaces the plain weekly `UsageBar` with the paced variant while leaving shorter and non-percentage rows unchanged (ui 04).
- `Sources/App/WeeklyBudgetPace.swift` — new pure presentation model for time, allowance, and pace calculations.
- `Tests/CoreTests/ProviderProtocolTests.swift`, the three affected provider test suites, and `Tests/AppTests/WeeklyBudgetPaceTests.swift` — cover metadata mapping, calculations, and boundary behavior.
- `Sources/App/Resources/Localizable.xcstrings` — localizes the new visible and accessibility text.

## Acceptance Criteria

### [x] AC1: Providers describe window duration explicitly
- **Given** a provider returns a time-bounded percentage quota
- **When** it creates a `UsageLine`
- **Then** it may set a new optional `windowDuration` value alongside `resetDate`
- **And** z.ai, Claude Code, and OpenAI Codex set it to exactly seven days for their weekly windows
- **And** no app logic identifies a weekly window by comparing its localized label

### [x] AC2: Only complete seven-day data enables pacing
- **Given** a percentage-based `UsageLine`
- **When** its duration is seven days and it has a future `resetDate`
- **Then** the row uses the weekly budget pace presentation
- **And** any line with missing, unsupported, expired, or invalid timing data keeps the existing percentage bar and reset presentation from (ui 04)

### [x] AC3: The row answers the three budget questions
- **Given** an eligible weekly line
- **When** it renders
- **Then** the header shows the localized label and `NN% used`
- **And** the footer shows a compact time remaining value such as `4d 8h left`
- **And** while at least 24 hours remain, the footer also shows the remaining sustainable allowance as `about N.N%/day available`
- **And** while less than 24 hours remain, it shows `NN% available until reset` instead of a misleading greater-than-100% daily rate

### [x] AC4: Seven-segment bar compares usage with elapsed time
- **Given** an eligible weekly line
- **When** its pace bar renders
- **Then** the bar fill ends at the clamped percentage used, six subtle dividers mark the seven equal daily budget segments, and a distinct moving marker shows the elapsed fraction of the seven-day window
- **And** the fill and marker share the same zero-to-100 scale, so fill extending beyond the marker means usage is ahead of a sustainable pace
- **And** neither the dividers nor the marker obscure the current fill amount at the popover's existing width

The intended information hierarchy is:

```text
Weekly                                  30% used
[======|==▲====|------|------|------|------|------]
5d 23h left                 about 11.7%/day available
         now
```

`▲` marks the sustainable pace at the current point in the week. Fill extending past it is ahead of budget. The diagram is illustrative; spacing and the marker glyph may change to fit native SwiftUI rendering.

### [x] AC5: Pace uses the remaining budget and exact remaining time
- **Given** `usedPercentage`, `resetDate`, `windowDuration`, and a supplied `now`
- **When** the app calculates weekly pace
- **Then** `remainingPercentage = max(100 - usedPercentage, 0)`
- **And** `remainingDays = max(resetDate - now, 0) / 86,400`
- **And** `availablePerDay = remainingPercentage / remainingDays`
- **And** the elapsed marker is `1 - ((resetDate - now) / windowDuration)`, clamped to zero through one
- **And** calculations use the unrounded values while display formatting is localized and rounds only the final result

### [x] AC6: Color communicates pace rather than raw weekly total
- **Given** an eligible weekly line with a valid elapsed marker
- **When** percentage used is at or behind the marker, allowing a one-percentage-point display tolerance
- **Then** the pace fill uses the good tier color
- **When** percentage used is beyond that tolerance but below 100%
- **Then** the pace fill uses the warning tier color
- **When** percentage used reaches or exceeds 100%
- **Then** the pace fill uses the critical tier color
- **And** when a collapsed card's compact percentage represents that same eligible weekly line, its ring and percentage use the identical pace tier and refresh from the local clock at least once per minute
- **And** non-weekly bars retain the existing raw-percentage color thresholds from (ui 04)

### [x] AC7: Time-driven values remain current without a quota request
- **Given** the popover stays open
- **When** wall-clock time advances
- **Then** the marker, remaining time, daily allowance, and pace color refresh locally at least once per minute
- **And** this local refresh does not fetch provider data, read credentials, or alter automatic refresh scheduling

### [x] AC8: Boundary and malformed values fail safely
- **Given** percentage values below zero or above 100
- **When** the weekly presentation calculates its output
- **Then** visual fill and remaining allowance are clamped to valid bounds without crashing
- **Given** a reset at or before `now`, a non-positive duration, or a reset farther in the future than the declared duration
- **When** the row renders
- **Then** it falls back to the existing bar instead of presenting invented pace information

### [x] AC9: Accessibility and localization carry the same meaning
- **Given** VoiceOver or a non-English locale
- **When** an eligible weekly row renders
- **Then** its accessibility value announces the label, percentage used, remaining time, whether usage is on pace or over pace, and the remaining daily allowance or until-reset allowance
- **And** all new visible and accessibility strings use the App String Catalog with localized number and duration formatting
- **And** the visualization does not rely on color alone because the fill-to-marker relationship and accessibility value convey pace independently

### [x] AC10: Provider architecture remains orthogonal
- **Given** a provider with no seven-day quota or no duration metadata
- **When** it is added or rendered
- **Then** it requires no weekly pacing code and its current presentation is unchanged
- **And** adding another seven-day provider requires only that provider to populate the generic duration field, with no provider-specific branch in the app

## Plan

Add optional `windowDuration: TimeInterval?` metadata to `UsageLine`, defaulting to `nil` for source compatibility. Populate it from known provider semantics for z.ai and Claude Code and from the reported duration for OpenAI Codex.

Create a pure `WeeklyBudgetPace` value in the App target. It accepts a line and an injected `now`, validates eligibility, and exposes clamped usage, remaining time, remaining allowance, allowance per day, elapsed marker position, and pace tier. Keeping date arithmetic outside SwiftUI makes the rules deterministic and directly testable.

Add a `WeeklyPaceBar` beside the existing `UsageBar`. It uses full-width shapes and scale/offset layout compatible with the window-style `MenuBarExtra`, draws the six daily dividers above the track, and draws a higher-contrast elapsed-time marker. Wrap the weekly row and its corresponding collapsed compact status in minute-based `TimelineView`s so time-derived presentation advances without network work.

Keep the existing `usageLineRow` structure and select the paced presentation only when `WeeklyBudgetPace` validates the line. Add focused tests for start, middle, and end of window; ahead/behind pace; sub-day display; clamping; expired and inconsistent timestamps; provider metadata; and the unchanged fallback path.

## Risks

- The bar compares quota percentage with elapsed-time percentage, which assumes an even pace as guidance rather than a provider rule. The copy says `about` and the UI does not block or limit usage.
- Provider reset timestamps can be stale or temporarily inconsistent during reset. Strict validation and the existing fallback prevent a misleading marker until fresh data arrives.
- Seven marks plus a moving marker can become visually noisy in the 280-point popover. Dividers must stay subtle, the current-time marker must dominate, and the layout needs verification in light mode, dark mode, and increased-contrast mode.
- A minute-based timeline adds local view updates while the popover is open. It must remain scoped to eligible weekly rows and perform no I/O.
- A compact card may summarize a shorter primary window before a weekly line. Pace color applies only when the compact number itself comes from the weekly line, so unrelated windows do not inherit weekly guidance.

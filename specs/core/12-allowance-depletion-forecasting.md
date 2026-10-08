## Objective

Estimate how long each supported allowance would last at the user's recent pace, using a shared Core engine and provider-owned measurement semantics.

## Context

- Status: draft for review. No production changes accompany this proposal.
- This spec owns the contract, the engine, the app wiring, and the UI. Each provider opts in through its own spec: (providers 17, providers 18, providers 19, providers 20). This spec lands together with (providers 17) as its first consumer. A test provider covers the generic contract.
- The forecast assumes continued recent consumption. It does not model calendar time, typical daily usage, or idle time.
- `Sources/Core/ProviderProtocol.swift` — `ProviderActivityMetric` carries numeric values for activity detection (core 09, core 11), but no period, limit, resolution, or per-metric timing. `UsageLine` has no stable ID.
- `Sources/Core/SmartRefreshPolicy.swift` — discards only `.stale` observations. `.unknown` and `.fresh` count equally as activity evidence.
- `Sources/App/QuotaViewModel+Fetch.swift`, `Sources/App/QuotaViewModel+Results.swift` — the accepted-result path is the only source of observations. Forecasting must not cause more provider work.
- `Sources/App/QuotaViewModel+Activity.swift` — existing sleep and wake observers, reused to invalidate evidence.
- `Sources/Core/AutoRefreshPreferences.swift` — the slow interval ranges from 1 to 60 minutes. Smart refresh polls faster during detected activity (core 08, core 11).
- `Sources/App/BudgetPace.swift` — sustainable daily and weekly allowances remain distinct from depletion forecasts (ui 18, ui 19, ui 22).
- `Sources/App/QuotaView.swift` — renders the provider's title string (`ProviderQuota.headline`) above the rows. Estimated and beyond-reset forecasts replace its reset countdown.
- Related: (ui 28) promotes a fallback credit or money pool once its limit group runs out and the pool starts to decrease. It reuses this spec's line IDs, limit groups, and forecasts.
- `Sources/App/UsageLineRow.swift` — renders one small forecast line inside its matching row without replacing usage, reset, or pace information.
- `Sources/App/Resources/Localizable.xcstrings` — forecast text and accessibility descriptions.
- `Tests/CoreTests/`, `Tests/AppTests/` — engine, lifecycle, and presentation tests.

## Acceptance Criteria

### AC1: Providers own meaning; Core owns calculation

- **Given** a provider opts an activity metric into forecasting
- **When** it maps an upstream result
- **Then** the metric carries a forecast descriptor with accounting semantics, unit, measurement resolution, source timing, and the stable ID of its usage row
- **And** Core reads the numeric value from the same metric that activity detection uses, so both share one value and one freshness
- **And** a fixed-period descriptor carries its limit and reset timestamp, not a localized label or a duration constant
- **And** `UsageLine` gains an optional stable ID; a forecast attaches by that ID, never by array position or display text
- **And** `ProviderQuota` may name the usage line ID its title summarizes; without it, the title never changes
- **And** `UsageLine` gains an optional limit group; lines in one group cap the same usage, so whichever runs out first blocks it
- **And** Core owns bounded history, rate estimation, validity rules, and forecast states
- **And** a metric without a descriptor keeps today's behavior and shows no forecast UI
- **And** Core, App, and other providers contain no branch keyed on a provider ID.

### AC2: Accounting semantics determine eligibility

- **Given** a percentage, money, or credit measurement
- **When** Core evaluates its descriptor
- **Then** fixed-period cumulative consumption can be forecast to its declared limit before its reset
- **And** a finite balance can be forecast to zero in its own unit
- **And** currencies and distinct allowance pools are never combined
- **And** unlimited, unknown, and rolling-window measurements carry no descriptor and produce no estimate
- **And** a rolling window does not become a fixed period because of a five-hour, weekly, or monthly label
- **And** a provider declares a fixed period only after verifying the upstream reset and consumption semantics.

### AC3: An accounting period is not a coding session

- **Given** Core receives the first valid observation for an allowance
- **When** it starts history
- **Then** the observation is a baseline, not a zero-consumption sample or proof that work just started
- **And** a new fixed accounting period, changed limit, changed unit, known account change, or an observation that arrives without its descriptor clears the affected history
- **And** a reset timestamp that moves by less than the reset tolerance belongs to the same period
- **And** a passed reset, or a reset that moves by more than the tolerance, starts a new period
- **And** a fixed-period consumption decrease without a declared reset is a correction and re-baselines
- **And** a balance increase is not consumption; it re-baselines
- **And** no rate crosses one of these boundaries
- **And** a short-window reset does not clear a separate weekly, monthly, or balance history.

### AC4: Only new usable observations enter history

- **Given** a normal provider refresh completes
- **When** Core considers its measurements
- **Then** stale, missing, failed, duplicate, and out-of-order observations do not become new samples
- **And** a repeated read of the same cached source observation does not acquire a new timestamp
- **And** unchanged values from genuinely new observations remain usable evidence
- **And** per-metric source timestamps take precedence over a provider-wide cache timestamp
- **And** a live response without a source timestamp uses receipt time, marked approximate
- **And** an observation with `.unknown` freshness never enters forecast history; Smart refresh keeps its current handling (core 11)
- **And** invalid numbers, impossible limits, and inconsistent timing fail safely without inventing a zero value
- **And** timing and resolution are never inferred by parsing formatted UI text.

### AC5: Recent evidence, not lifetime history, defines the rate

- **Given** comparable observations exist in one segment of an allowance's history
- **When** the engine estimates the recent rate
- **Then** the rate is the consumption between the segment's first and latest observations divided by the elapsed time between them
- **And** the segment covers the recent horizon, and extends back toward the maximum horizon only as far as needed to reach the minimum consumption
- **And** the segment needs the minimum observation count, the minimum evidence span, and at least two resolution steps of consumption
- **And** intermediate observations only confirm contiguity and detect boundaries, so polling cadence alone does not change the rate
- **And** the engine uses unrounded upstream values where the provider supplies them
- **And** a measurement without a declared resolution produces no estimate
- **And** coarse percentage data is never presented as token consumption
- **And** a non-positive rate yields no estimate
- **And** the engine claims no statistical confidence and no future workload stability.

### AC6: Quiet periods and observation gaps invalidate the active rate

- **Given** an allowance had a usable rate, and fresh, contiguous observations since then show no consumption
- **When** the time without consumption reaches the quiet threshold
- **Then** the UI reports "No recent consumption detected", not an unlimited allowance
- **And** the quiet threshold is twice the time the last usable rate needed for one resolution step, clamped between 15 minutes and the maximum horizon
- **And** without a prior usable rate, no consumption is treated as insufficient evidence, not quiet, so a slow-moving window is never called quiet during active work
- **And** this state does not claim that the user or a job stopped working
- **And** later consumption starts a new segment from the latest observation without spanning the quiet period
- **Given** observations stop, the system sleeps, the wall clock moves backward or jumps, or an interval exceeds the maximum gap
- **When** the engine next evaluates the allowance
- **Then** it pauses the estimate and requires a new baseline and enough later evidence
- **And** missing observations are not treated as unchanged usage
- **And** no local process detection, coding-session signal, or idle-time estimate is required.

### AC7: Forecasts are anchored to the latest observation

- **Given** a positive usable rate and a finite remaining allowance
- **When** Core calculates depletion
- **Then** the estimated duration is remaining allowance divided by the rate
- **And** the projected depletion timestamp is anchored to the latest observation's time, not moved forward on each render
- **And** a fixed-period forecast distinguishes depletion before reset from no projected depletion before reset
- **And** it does not extrapolate past the next reset
- **And** reaching a projected depletion timestamp locally without a confirming observation pauses the estimate; it never reports exhaustion
- **And** exhaustion comes only from a usable provider measurement
- **And** each result carries its observation age, evidence span, and timing limitations.

### AC8: Allowance pools remain independent

- **Given** a provider reports several allowances, credit pools, or currencies
- **When** Core forecasts them
- **Then** each pool has its own history and result
- **And** the app does not pick the earliest depletion across independent pools or currencies as a provider-wide deadline
- **And** within one limit group, the earliest depletion is the binding one, and the title shows it (AC9)
- **And** a pool that is consumed only after another allowance runs out is forecast only from its own observed depletion
- **And** a forecast does not predict when consumption will switch between pools
- **And** balance forecasts describe observed net depletion, not verified spend.

### AC9: Forecasts fit the existing card without crowding it

- **Given** a provider names the usage line its card title summarizes, and that line or another line in its limit group has an estimated forecast
- **When** the expanded card renders
- **Then** the title shows the estimate that runs out first in the group, replacing the reset countdown, e.g. "3% · About 1h 20m of use remaining"
- **And** when the binding line is not the named title line, the title adds its label, e.g. "Weekly 95% · About 30m of use remaining"
- **And** a smaller secondary line below the title reads like "Based on the last 20 minutes"
- **And** when every line in the group that has a descriptor is beyond reset, the title reads like "3% · Not expected to run out", with a smaller line "before reset at recent pace"
- **And** a group with lines in weaker states and no estimate keeps the provider's title
- **And** the countdown stays visible in the row's existing reset text below the bar
- **And** only the estimated and beyond-reset states change the title; every other state keeps the provider's title as it is
- **And** the App composes the title from the named line's current value and the forecast; it never parses or edits the provider's title string
- **Given** a row with a forecast descriptor is learning, quiet, too far apart, or paused
- **When** the row renders
- **Then** one small secondary line appears just above the row's reset text
- **And** learning reads like "Learning your usage rate…", and shows only until the maximum horizon has passed since the baseline
- **And** once the maximum horizon passes without enough evidence for a rate, the row shows no forecast text; it never shows an estimate built from insufficient data
- **And** quiet reads like "No recent consumption detected"
- **And** two consecutive accepted intervals longer than the maximum gap read like "Updates too far apart to estimate", in place of a learning state that cannot complete
- **And** stale or interrupted evidence reads like "Forecast paused until fresh data arrives", without hiding the last-known usage and timestamp
- **Given** a row that is not the title's line has an estimated or beyond-reset forecast
- **When** the row renders
- **Then** it shows the estimate as the same kind of small secondary line above its reset text, e.g. "About 1d 4h of use remaining · last 2 hours"
- **And** in every state, the title gains at most one secondary line and each row gains at most one forecast line
- **And** an exhausted allowance shows no forecast text; the existing row already shows it
- **And** unsupported or unlimited measurements show no forecast UI
- **And** approximate timing appears in the help tooltip and VoiceOver, not as another visible line
- **And** visible text says "of use remaining", never just "left", so it cannot be confused with the reset time, e.g. "1d 2h left"
- **And** wording stays conditional and never predicts a calendar date from assumed daily habits
- **And** row reset text, budget pace, compact status tiers, the collapsed card header, and menu-bar selection remain unchanged
- **And** durations use coarse localized formatting, without minute precision for estimates longer than a day
- **And** VoiceOver reads the full conditional sentence, including "at recent pace" and the evidence span, without relying on color.

### AC10: Forecasting adds no provider work

- **Given** manual, automatic, or passive updates deliver provider measurements
- **When** the app records observations or renders a forecast
- **Then** it uses the existing accepted-result path
- **And** it performs no additional API calls, CLI invocations, credential reads, or scheduling changes
- **And** the "Updates too far apart to estimate" state never shortens a refresh interval
- **And** rate limits, retry deadlines, refresh-cost limits, and freshness handling remain authoritative (core 11)
- **And** a manual refresh or "Keep checking" hint does not manufacture consumption evidence
- **And** local time-driven UI updates can pause or age an estimate without network work.

### AC11: History is bounded and memory-only

- **Given** forecasting is enabled
- **When** Core retains measurements
- **Then** it stores only bounded in-memory numeric history and the needed metric metadata
- **And** app relaunch starts learning again
- **And** disabling or removing a provider, replacing or importing its credentials, or changing its endpoint clears that provider's history
- **And** known account-scope changes invalidate history without storing credentials as identity
- **And** logs contain no raw history, account identifiers, credentials, or provider payloads
- **And** no disk store, telemetry, token-content collection, or account-discovery request is added.

### AC12: Boundary cases and real refresh patterns are tested

- **Given** the engine and app wiring are implemented
- **When** deterministic Core and App tests run
- **Then** they cover linear consumption, bursts, quiet periods after a usable rate, no consumption without a prior rate, renewed activity, whole-point percentages, delayed publication, duplicate cache reads, unknown freshness, approximate timing, failures, sleep gaps, repeated long intervals, clock changes, resets, reset jitter inside and beyond tolerance, corrections, top-ups, limit changes, multiple currencies, malformed values, and provider removal
- **And** a trace that consumes 10 percentage points over 20 minutes with 70 points remaining projects 140 minutes of continued use at the latest observation
- **And** traces that differ only in extra intermediate polling produce the same rate
- **And** a weekly-style trace that gains one point in two hours shows learning for two hours and then no forecast text, never quiet and never an estimate
- **And** local renders do not move the depletion timestamp or turn projected exhaustion into reported exhaustion
- **And** UI tests cover row association by ID, title composition for the estimated and beyond-reset states only, the earliest estimate within a limit group with its label when it is not the title line, an unchanged title in every other state, at most one forecast line per row, every localized and accessible state, long-duration formatting, and preservation of budget pace and compact status
- **And** a test provider using only the generic contract obtains forecasts without Core or App changes.

## Plan

1. Add an optional forecast descriptor to `ProviderActivityMetric`, an optional `id` and `limitGroup` to `UsageLine`, and an optional `headlineUsageLineId` to `ProviderQuota`. All default to `nil`, so providers that do not opt in need no change. Unsupported semantics are expressed by omitting the descriptor.

   ```swift
   public struct AllowanceForecastDescriptor: Equatable, Sendable {
       public enum Accounting: Equatable, Sendable {
           case fixedPeriod(limit: Decimal, resetsAt: Date) // metric value = consumed
           case balance                                      // metric value = remaining, boundary 0
       }
       public enum Unit: Equatable, Sendable {
           case percentagePoints
           case currency(String)
           case credits
       }
       public enum Timing: Equatable, Sendable {
           case source(Date)
           case receipt(Date) // approximate
       }
       public let accounting: Accounting
       public let unit: Unit
       public let resolution: Decimal
       public let timing: Timing
       public let usageLineId: String
   }
   ```

2. Implement a pure Core `AllowanceForecaster` with an injected clock. Key history by provider ID and metric ID. Model these states explicitly: learning, estimated, beyond reset, quiet, too far apart, paused, exhausted, insufficient. Exhausted and insufficient render no forecast text. Keep accounting-period boundaries separate from recent-rate segments.
3. Estimate the rate with the simple endpoint delta from (AC5). Do not add regression. Revisit only if replay tests show bursts at segment ends distort estimates materially.
4. Keep every threshold in one shared `AllowanceForecastPolicy`. Provider precision, publication delay, and freshness limits may make a forecast unavailable. Per-provider calculator overrides stay out of scope.
5. Feed accepted results into the forecaster from the existing results path. Invalidate on lifecycle revision changes, sleep and wake, and `NSSystemClockDidChange`. Clear history on provider disable or removal, credential replacement or import, and endpoint changes.
6. In `QuotaView`, compose the title from the binding line of the title's limit group when it is estimated or beyond reset, with the smaller secondary line below it. Otherwise render the provider's title unchanged. Pass every other forecast into `UsageLineRow` by line ID as one small line above the reset text. Use a `TimelineView` for aging. Leave compact status, the collapsed header, and menu-bar selection untouched. The layout follows "Card layout" below.
7. Run the focused tests and the repository validation gate. Then manually inspect normal-width popovers and VoiceOver in the estimated, beyond reset, learning, quiet, too far apart, and paused states.
8. Land the provider opt-ins in order. Mark each one here as it lands:
   - [ ] Claude Code five-hour and weekly windows (providers 17), together with this spec
   - [ ] Codex windows and credits row (providers 18)
   - [ ] DeepSeek total balance (providers 19)
   - [ ] OpenCode Go weekly and monthly windows (providers 20)

Card layout. The panel is small, so forecasts add as little text as possible:

- Only the estimated and beyond-reset states change the title. They replace the title's reset countdown, which the row still shows below its bar. A smaller line under the title gives the evidence or the condition.
- Every other state is one small gray line inside its row, just above the reset text. It never touches the title.
- A row that is not the title's binding line shows its estimate as the same small line.
- Approximate timing lives in the tooltip and VoiceOver only.

```
Estimated (title line binds)          Weaker states (title unchanged)
3% · About 1h 20m of use remaining    3% · resets in 5 hours
Based on the last 20 minutes          5-hour window                 3%
5-hour window                 3%      ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬                     Learning your usage rate…
resets in 5 hours                     resets in 5 hours
Weekly                   6% used
▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
About 1d 4h of use remaining · last 2 hours
1d 2h left  About 83,8%/day available

Beyond reset                          Another group line binds
3% · Not expected to run out          Weekly 95% · About 30m of use remaining
before reset at recent pace           Based on the last 40 minutes
```

The other weak-state lines take the learning line's place: "No recent consumption detected", "Updates too far apart to estimate", and "Forecast paused until fresh data arrives". When a limit group runs out and usage continues from a fallback pool, (ui 28) moves that pool into the title position.

Proposed initial policy values, subject to review:

| Rule | Default |
|---|---|
| Recent horizon | 30 minutes |
| Maximum horizon | 2 hours, used only to reach the minimum consumption |
| Minimum independent observations | 3 |
| Minimum evidence span | 10 minutes |
| Minimum consumption | 2 resolution steps |
| Quiet threshold | 2 × resolution ÷ last usable rate, clamped to 15 minutes – 2 hours; requires a prior usable rate |
| Learning display limit | 2 hours after the baseline, then no forecast text |
| Maximum observation gap or age | 15 minutes, or a stricter provider freshness limit |
| "Too far apart" trigger | 2 consecutive accepted intervals above the maximum gap |
| Reset tolerance | 60 seconds |
| Maximum retained observations | 256 per metric |

A provider refreshed less often than every 15 minutes, and never sped up by Smart refresh, shows "Updates too far apart to estimate". The app explains this state; it never speeds up refresh to resolve it. The thresholds are estimation policy, not proof of coding-session boundaries.

Rejected alternatives:

- Fully provider-specific calculators duplicate history, validity, and UI behavior. Revisit only if a verified accounting model cannot fit the shared contract.
- A generic fit over existing display rows guesses identities and semantics. Typed descriptors are required.
- A forecasting type parallel to `ProviderActivityMetric` creates two numeric channels that can drift apart.
- Elapsed-weighted linear regression adds complexity. Endpoint delta is cadence-invariant by construction and matches it on whole-point data.
- Regression across lifetime history mixes old work, idle time, and accounting periods.
- Calendar runway based on typical daily use needs durable history and an idle-time model. It is outside this version.

## Risks

- Consumption is bursty, and models or workloads can change the rate at once. Conditional wording and short-lived evidence cannot remove this uncertainty.
- Endpoint delta is sensitive to a burst at either end of the segment. A single delayed publication can inflate the rate until the next segment.
- At whole-point resolution, weekly and monthly windows forecast only under sustained heavy use: two points within two hours. Most of the time they show learning and then no forecast text.
- Rounded percentages and delayed publication can hide ongoing work. Quiet means no observed progress, not verified inactivity.
- A balance endpoint cannot reveal consumption offset by a top-up within one interval. Net-depletion forecasts must not be labeled spend.
- A local CLI can switch accounts without exposing a scope change. Clear known changes and document the limit; do not read more credentials.
- Memory-only history adds warm-up after relaunch. Durable history is deferred to avoid stale patterns, privacy concerns, and storage lifecycle complexity.
- Receipt-time measurements are approximate. Delayed provider updates can create a misleading apparent burst.
- The thresholds trade availability for caution, especially under slow polling. Replay tests may justify revisions before release.
- New forecast text can crowd the popover. Keep allowance and reset information legible, and do not change compact status from an uncertain prediction.

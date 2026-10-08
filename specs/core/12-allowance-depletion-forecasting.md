## Objective

Estimate how long each supported allowance would last at the user's recent pace, using a shared Core engine and provider-owned measurement semantics.

## Context

- Status: steps 1, 2, 4, 5, and 6 are implemented. The review of 2026-10-08 reopened steps 3 and 4 and added steps 7 and 8. Step 3, the rest of step 7, and step 8 are pending. The branch merges only after steps 3–10.
- This spec owns the contract, the engine, the app wiring, and the UI. Each provider opts in through its own spec: (providers 17, providers 18, providers 19, providers 20). No provider is ready yet, so this spec merges only together with all four opt-ins. A test provider covers the generic contract.
- The forecast assumes continued recent consumption. It does not model calendar time, typical daily usage, or idle time.
- `Sources/Core/ProviderProtocol.swift` — `ProviderActivityMetric` carries numeric values for activity detection (core 09, core 11), but no period, limit, resolution, or per-metric timing. `UsageLine` has no stable ID.
- `Sources/Core/SmartRefreshPolicy.swift` — discards only `.stale` observations. `.unknown` and `.fresh` count equally as activity evidence.
- `Sources/App/QuotaViewModel+Fetch.swift`, `Sources/App/QuotaViewModel+Results.swift` — the accepted-result path is the only source of observations. Forecasting must not cause more provider work.
- `Sources/App/QuotaViewModel+Activity.swift` — existing sleep and wake observers, reused to invalidate evidence.
- `Sources/Core/AutoRefreshPreferences.swift` — the slow interval ranges from 1 to 60 minutes. Smart refresh polls faster during detected activity (core 08, core 11).
- `Sources/App/BudgetPace.swift` — sustainable daily and weekly allowances remain distinct from depletion forecasts (ui 18, ui 19, ui 22).
- `Sources/App/QuotaView.swift` — renders the provider's headline (`ProviderQuota.headline`) above the rows. An estimate, a beyond-reset forecast, or a reached limit replaces its reset countdown (AC9).
- Related: (ui 28) promotes a fallback credit or money pool once its limit group runs out and the pool starts to decrease. It reuses this spec's line IDs, limit groups, and forecasts.
- `Sources/App/UsageLineRow.swift` — renders one small forecast line inside its matching row without replacing usage, reset, or pace information.
- `Sources/App/Resources/Localizable.xcstrings` — forecast text and accessibility descriptions.
- `Tests/CoreTests/`, `Tests/AppTests/` — engine, lifecycle, and presentation tests.

## Acceptance Criteria

### AC1: Providers own meaning; Core owns calculation

- **Given** a provider opts an activity metric into forecasting
- **When** it maps an upstream result
- **Then** the metric carries a forecast descriptor with accounting semantics, unit, measurement resolution, source timing, and the stable ID of its usage row
- **And** the resolution is the smallest change that the upstream value can show, in the unit of the metric value, e.g. 1 for whole percentage points or 0.01 for a balance with cents
- **And** Core reads the numeric value from the same metric that activity detection uses, so both share one value and one freshness
- **And** a fixed-period descriptor carries its limit and reset timestamp, not a localized label or a duration constant
- **And** `UsageLine` gains an optional stable ID; a forecast attaches by that ID, never by array position or display text
- **And** two metrics in one observation that name the same usage line ID produce no forecast for that line
- **And** `ProviderQuota` can name the usage line ID its headline summarizes; without it, the headline never changes
- **And** `UsageLine` gains an optional limit group; lines in one group cap the same usage, so whichever runs out first blocks it
- **And** Core owns bounded history, rate estimation, validity rules, and forecast states
- **And** a provider withdraws a forecast by sending the metric without a descriptor; that metric keeps today's behavior and shows no forecast UI
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
- **And** a new fixed accounting period, changed limit, changed unit, or an observation that arrives without its descriptor clears the affected history
- **And** the account changes that the app knows clear the provider's history (AC11)
- **And** Core compares each reset timestamp with the first reset timestamp of the period; a difference within the reset tolerance belongs to the same period
- **And** a passed reset, or a reset more than the tolerance from the first one, starts a new period, so small moves cannot add up
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
- **And** an observation with `.unknown` or `.stale` freshness, or a quota marked `isStale`, never enters forecast history; it pauses each history of that provider until the next accepted sample; Smart refresh keeps its current handling (core 11)
- **And** a sample that fails validation pauses its history until the next accepted sample, so the headline never shows a new value next to an old estimate
- **And** a metric that is absent from a fresh observation is missing, not withdrawn; its history pauses, and Core removes the history after the maximum horizon without a sample
- **And** after a sleep, wake, or clock change, only a sample newer than the interruption can become the new baseline
- **And** invalid numbers, impossible limits, and inconsistent timing fail safely without inventing a zero value
- **And** timing and resolution are never inferred by parsing formatted UI text.

### AC5: Recent evidence, not lifetime history, defines the rate

- **Given** comparable observations exist in one segment of an allowance's history
- **When** the engine estimates the recent rate
- **Then** the engine uses a fixed time window that ends at the latest observation
- **And** the value at the start of the window comes from linear interpolation between the two samples around that time; if the segment is shorter than the window, the window starts at the segment's first sample
- **And** the rate is the consumption across the window divided by the window's duration
- **And** the window is the recent horizon; to reach the minimum consumption, it grows in steps of the recent horizon, up to the maximum horizon
- **And** the window needs the minimum observation count, the minimum evidence span, and at least two resolution steps of consumption
- **And** the observation count counts accepted observations, not stored samples
- **And** extra observations that show no new value do not change the rate, so repeated refreshes cannot change an estimate
- **And** Core removes a stored sample when the samples before and after it have the same value; under interpolation this loses no information
- **And** the engine uses unrounded upstream values where the provider supplies them
- **And** a measurement without a declared resolution produces no estimate
- **And** coarse percentage data is never presented as token consumption
- **And** a non-positive rate, or a result that is not finite, yields no estimate
- **And** the engine claims no statistical confidence and no future workload stability.

### AC6: Quiet periods and observation gaps invalidate the active rate

- **Given** an allowance had a usable rate, and fresh, contiguous observations since then show no consumption
- **When** the time without consumption reaches the quiet threshold
- **Then** the UI reports "No recent consumption detected", not an unlimited allowance
- **And** the quiet threshold is twice the time the last usable rate needed for one resolution step, clamped between 15 minutes and the maximum horizon
- **And** when an estimate ends because its evidence left the maximum horizon, and no consumption occurred for at least 15 minutes, the state is quiet; the row never drops to no text between an estimate and quiet
- **And** without a prior usable rate, no consumption is treated as insufficient evidence, not quiet, so a slow-moving window is never called quiet during active work
- **And** this state does not claim that the user or a job stopped working
- **And** later consumption starts a new segment from the latest observation without spanning the quiet period
- **Given** observations stop, the system sleeps, the wall clock moves backward or jumps, or an interval exceeds the maximum gap
- **When** the engine next evaluates the allowance
- **Then** it pauses the estimate and requires a new baseline and enough later evidence
- **And** the maximum gap is measured between the source timestamps of accepted samples
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
- **And** exhaustion comes only from a usable provider measurement; it stays true until the period resets or the balance increases, even when the measurement is old
- **And** the engine decides the state in this order: a passed reset pauses, a measurement at the limit is exhausted, an interruption pauses, and then too far apart, stale, quiet, learning, and the estimate follow
- **And** each result carries its observation age, evidence span, and timing limitations.

### AC8: Allowance pools remain independent

- **Given** a provider reports several allowances, credit pools, or currencies
- **When** Core forecasts them
- **Then** each pool has its own history and result
- **And** the app does not pick the earliest depletion across independent pools or currencies as a provider-wide deadline
- **And** within one limit group, the headline rules decide which line the headline shows (AC9)
- **And** a pool that is consumed only after another allowance runs out is forecast only from its own observed depletion
- **And** a forecast does not predict when consumption will switch between pools
- **And** balance forecasts describe observed net depletion, not verified spend.

### AC9: Forecasts fit the existing card without crowding it

- **Given** a provider names the usage line its headline summarizes
- **When** the expanded card renders
- **Then** the App takes that line's limit group, or only that line when it has no group, and applies the first rule that matches:
  1. **Limit reached.** A line in the group shows 100% in its current `UsageLine`, with or without a descriptor. The headline reads like "Weekly 100% · Limit reached", with the line's reset countdown below it. When several lines are at 100%, the line with the latest reset wins, because it blocks usage longest.
  2. **Uncertain near the limit.** A group line is paused after its projected depletion time, or a group line without an estimate has less than two resolution steps left. The headline stays as the provider wrote it.
  3. **Earliest estimate.** A group line has an estimated forecast. The estimate that runs out first wins. The headline reads like "3% · About 1h 20m of use remaining", with a smaller line below it like "Based on the last 20 minutes".
  4. **Beyond reset.** The headline line has a beyond-reset forecast, and every other group line with a forecast is beyond reset too. The headline reads like "3% · Not expected to run out", with a smaller line "before reset at recent pace".
- **And** when no rule matches, the headline stays as the provider wrote it
- **And** the winning line is the binding line; the headline shows the binding line's current value
- **And** when the binding line is not the named headline line, the headline adds its label, e.g. "Weekly 95% · About 30m of use remaining"
- **And** the countdown stays visible in the row's existing reset text below the bar
- **And** the App composes the headline from the binding line's current value and its forecast; it never parses or edits the provider's headline string
- **Given** a row with a forecast descriptor is learning, quiet, too far apart, or paused
- **When** the row renders
- **Then** one small secondary line appears just above the row's reset text
- **And** learning reads like "Learning your usage rate…", and shows only until the maximum horizon has passed since the last baseline; a new segment after quiet does not restart this limit
- **And** once the maximum horizon passes without enough evidence for a rate, the row shows no forecast text; it never shows an estimate built from insufficient data
- **And** quiet reads like "No recent consumption detected"
- **And** two consecutive accepted intervals longer than the maximum gap read like "Updates too far apart to estimate", in place of a learning state that cannot complete
- **And** "Updates too far apart to estimate" lasts while the latest observation is younger than the last long interval plus the maximum gap; after that, the row shows the paused text
- **And** stale or interrupted evidence reads like "Forecast paused until fresh data arrives", without hiding the last-known usage and timestamp
- **Given** a row that is not the binding line has an estimated or beyond-reset forecast
- **When** the row renders
- **Then** it shows the estimate as the same kind of small secondary line above its reset text, e.g. "About 1d 4h of use remaining · last 2 hours"
- **And** the binding line's row shows no forecast line, because the headline already shows its forecast
- **And** in every state, the headline gains at most one secondary line and each row gains at most one forecast line
- **And** an exhausted allowance shows no forecast text in its row; the existing row already shows it
- **And** unsupported or unlimited measurements show no forecast UI
- **And** approximate timing appears in the help tooltip and VoiceOver, not as another visible line
- **And** visible text says "of use remaining", never just "left", so it cannot be confused with the reset time, e.g. "1d 2h left"
- **And** wording stays conditional and never predicts a calendar date from assumed daily habits
- **And** forecasts do not change row reset text, budget pace, compact status tiers, the collapsed card header, or menu-bar selection; only (ui 28) promotion can change them
- **And** durations use coarse localized formatting, without minute precision for estimates longer than a day
- **And** an estimate longer than 4 weeks reads like "More than 4w of use remaining"
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
- **And** disabling or removing a provider, saving, deleting, or importing its credentials, or changing its endpoint clears that provider's history
- **And** these are the only account changes that Core knows; the contract has no field for a provider to report an account change
- **And** logs contain no raw history, account identifiers, credentials, or provider payloads
- **And** no disk store, telemetry, token-content collection, or account-discovery request is added.

### AC12: Boundary cases and real refresh patterns are tested

- **Given** the engine and app wiring are implemented
- **When** deterministic Core and App tests run
- **Then** they cover linear consumption, bursts, quiet periods after a usable rate, no consumption without a prior rate, renewed activity, whole-point percentages, delayed publication, duplicate cache reads, unknown freshness, approximate timing, failures, sleep gaps, wake, repeated long intervals, clock changes, resets, reset jitter inside and beyond tolerance, reset drift across many samples, corrections, top-ups, limit changes, multiple currencies, malformed values, missing metrics, duplicate usage line IDs, and provider removal
- **And** a trace that consumes 10 percentage points over 20 minutes with 70 points remaining projects 140 minutes of continued use at the latest observation
- **And** traces that differ only in extra observations without a new value produce the same rate, including bursty traces and repeated manual refreshes
- **And** a 10-second fast interval keeps two hours of evidence
- **And** 15-minute and 29-minute slow intervals produce an estimate, and a 31-minute slow interval shows "Updates too far apart to estimate"
- **And** a weekly-style trace that gains one point in two hours shows learning for two hours and then no forecast text, never quiet and never an estimate
- **And** local renders do not move the depletion timestamp or turn projected exhaustion into reported exhaustion
- **And** UI tests cover row association by ID, each headline rule (AC9), the label of a binding line that is not the headline line, an unchanged headline when no rule matches, at most one forecast line per row, every localized and accessible state, long-duration formatting, and preservation of budget pace and compact status with forecasts present
- **And** App tests cover history clearing on every lifecycle event in (AC11), and the sleep, wake, and clock-change observers
- **And** a test provider using only the generic contract obtains forecasts without Core or App changes.

## Plan

1. [x] Add an optional forecast descriptor to `ProviderActivityMetric`, an optional `id` and `limitGroup` to `UsageLine`, and an optional `headlineUsageLineId` to `ProviderQuota`. All default to `nil`, so providers that do not opt in need no change. Unsupported semantics are expressed by omitting the descriptor.

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
       public let resolution: Decimal // smallest change of the upstream value, in the metric's unit
       public let timing: Timing
       public let usageLineId: String
   }
   ```

2. [x] Implement a pure Core `AllowanceForecaster`. Callers pass the current time. Key history by provider ID and metric ID. Model these states explicitly: learning, estimated, beyond reset, quiet, too far apart, paused, exhausted, insufficient. Exhausted and insufficient render no forecast text. Keep accounting-period boundaries separate from recent-rate segments.
3. [ ] Estimate the rate with the interpolated fixed window from (AC5). Remove repeated samples as (AC5) describes. Do not add regression. The first version used the endpoint delta from the last sample before the cutoff. Extra observations moved that sample and changed the rate.
4. [x] Keep every threshold in one shared internal `AllowanceForecastPolicy`, with `let` fields. Apply the values in "Policy values" below. A provider with a stricter freshness limit marks its observation `.stale`. Per-provider calculator overrides stay out of scope.
5. [x] Feed accepted results into the forecaster from the existing results path. Invalidate on lifecycle revision changes, sleep and wake, and `NSSystemClockDidChange`. Clear history on provider disable or removal, credential save, delete, or import, and endpoint changes.
6. [x] In `QuotaView`, compose the headline from the binding line, with the smaller secondary line below it. Otherwise render the provider's headline unchanged. Pass every other forecast into `UsageLineRow` by line ID as one small line above the reset text. Use a `TimelineView` for aging. Leave compact status, the collapsed header, and menu-bar selection untouched. The layout follows "Card layout" below.
7. [ ] Apply the fixes from the review of 2026-10-08:
   - [ ] The headline rules in (AC9), with "Limit reached" and its accessibility sentence.
   - [ ] Rejected data pauses its history: `.unknown` or `.stale` freshness, `isStale` quotas, invalid samples, and missing metrics (AC4).
   - [ ] Core removes the history of a missing metric after the maximum horizon. `hasHistory` counts only the remaining histories (AC4).
   - [ ] After an interruption, only a sample newer than the interruption becomes the new baseline (AC4).
   - [ ] Two metrics with one usage line ID produce no forecast. Add a debug assertion (AC1).
   - [ ] Compare each reset timestamp with the first one of the period (AC3).
   - [ ] Count the learning limit from the last baseline. Remove `learningDisplayLimit` and use the maximum horizon (AC9).
   - [ ] Decide the state in the order of (AC7).
   - [ ] Report quiet when the estimate leaves the maximum horizon after 15 minutes without consumption (AC6).
   - [ ] Use the beyond-reset headline only when the headline line has its own beyond-reset forecast (AC9).
   - [ ] End "Updates too far apart to estimate" after the last long interval plus the maximum gap (AC9).
   - [ ] Produce no estimate from a result that is not finite. Show "More than 4w of use remaining" above 4 weeks (AC5, AC9).
   - [ ] Evaluate forecasts at the later of the timeline date and the current time, so a new sample never shows paused for one tick.
   - [ ] Make Smart refresh compare the descriptor without its timing, so a new limit or period counts as a change (core 11).
   - [x] Move `QuotaHeadlineAndRows` to `QuotaView+HeadlineAndRows.swift`. Put only the forecast text inside the `TimelineView`.
   - [x] Use "headline" in code: rename `Title`, `titleBinding`, `ForecastTitle`, and the catalog keys.
   - [x] Remove `forecastNow`. Give `recordAllowanceObservation` an `at:` argument and pass `activityRuntime.now()`.
   - [x] Install the clock-change observer in its own method, with a `handleSystemClockDidChange` handler.
   - [x] Move the Smart refresh test to a `SmartRefreshPolicy*Tests` file and the default-nil test to `ProviderProtocolTests.swift`. Use `ActivityTestClock` in place of `TestDateClock`.
   - [x] Move the `Decimal` extension to `Decimal+Double.swift`, with internal access.
   - [x] Remove the doc comments that restate acceptance criteria.
   - [x] Make `observationAge(at:)`, `resetAll()`, and `policy` internal or remove them. Require `maximumRetainedObservations` of 2 or more.
8. [ ] Add the tests from (AC12) that are still missing:
   - [ ] Bursts at the start and at the end of a window.
   - [ ] Extra observations without a new value, including repeated manual refreshes, produce the same rate.
   - [ ] A 10-second fast interval keeps two hours of evidence.
   - [ ] 15-minute and 29-minute slow intervals produce an estimate. A 31-minute slow interval shows "too far apart".
   - [ ] A failed refresh adds no sample.
   - [ ] Wake, a forward clock jump, and the `NSSystemClockDidChange` observer.
   - [ ] History clearing on `saveOverrideURL`, `importCredentials`, and `deleteKey`.
   - [ ] Reset drift across many samples starts a new period.
   - [ ] Missing metrics, duplicate usage line IDs, and the state order.
   - [ ] Each headline rule, including "Limit reached" for a line without a descriptor.
   - [ ] The beyond-reset accessibility sentence, and approximate timing in the headline.
   - [ ] Budget pace and compact status with forecasts present. This replaces `testForecastsLeaveBudgetPaceAndCompactStatusUnchanged`, which cannot fail.
9. [ ] Run the focused tests and the repository validation gate. Then manually inspect normal-width popovers and VoiceOver in the limit-reached, estimated, beyond reset, learning, quiet, too far apart, and paused states.
10. [ ] Land the provider opt-ins. Mark each one here as it lands. The branch merges only after all four:
    - [ ] Claude Code five-hour and weekly windows (providers 17)
    - [ ] Codex windows and credits row (providers 18)
    - [ ] DeepSeek total balance (providers 19)
    - [ ] OpenCode Go weekly and monthly windows (providers 20)

### Card layout

The panel is small, so forecasts add as little text as possible:

- Only the headline rules in (AC9) change the headline. They replace the headline's reset countdown, which the row still shows below its bar. A smaller line under the headline gives the evidence, the condition, or the reset.
- Every other state is one small gray line inside its row, just above the reset text. It never touches the headline.
- A row that is not the binding line shows its estimate as the same small line.
- Approximate timing lives in the tooltip and VoiceOver only.

```
Estimated (headline line binds)       Weaker states (headline unchanged)
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

Limit reached
Weekly 100% · Limit reached
resets in 2d 4h
```

The other weak-state lines take the learning line's place: "No recent consumption detected", "Updates too far apart to estimate", and "Forecast paused until fresh data arrives". When a limit group runs out and usage continues from a fallback pool, (ui 28) replaces the "Limit reached" headline with that pool.

### Policy values

| Rule | Default |
|---|---|
| Recent horizon | 30 minutes; the window grows in 30-minute steps |
| Maximum horizon | 2 hours, used only to reach the minimum consumption |
| Minimum accepted observations | 3 |
| Minimum evidence span | 10 minutes |
| Minimum consumption | 2 resolution steps |
| Quiet threshold | 2 × resolution ÷ last usable rate, clamped to 15 minutes – 2 hours; requires a prior usable rate |
| Learning display limit | The maximum horizon after the last baseline, then no forecast text |
| Maximum observation gap | 30 minutes between the source timestamps of accepted samples |
| Maximum observation age | 30 minutes |
| "Too far apart" trigger | 2 consecutive accepted intervals above the maximum gap |
| Reset tolerance | 60 seconds from the first reset timestamp of the period |
| Future timestamp tolerance | 60 seconds; a later measurement time is inconsistent timing |
| Maximum retained samples | 256 per metric, after Core removes repeated values |
| Longest displayed estimate | 4 weeks |

A provider refreshed every 30 minutes or less often, and never sped up by Smart refresh, shows "Updates too far apart to estimate". The real gap is the refresh interval plus the fetch time, so a 30-minute slow interval sits on the limit. The app explains this state; it never speeds up refresh to resolve it. The thresholds are estimation policy, not proof of coding-session boundaries.

### Rejected alternatives

- Fully provider-specific calculators duplicate history, validity, and UI behavior. Revisit only if a verified accounting model cannot fit the shared contract.
- A generic fit over existing display rows guesses identities and semantics. Typed descriptors are required.
- A forecasting type parallel to `ProviderActivityMetric` creates two numeric channels that can drift apart.
- Endpoint delta from the last sample before the cutoff. An extra observation moves the start sample and changes the rate (review of 2026-10-08).
- Elapsed-weighted linear regression adds complexity. The interpolated window already gives the same rate for extra observations without a new value.
- Regression across lifetime history mixes old work, idle time, and accounting periods.
- Calendar runway based on typical daily use needs durable history and an idle-time model. It is outside this version.
- A provider field for account changes. No provider spec can supply it today. Core knows only the account changes in (AC11).

### Implementation findings

- A descriptor's timing changes on every write. Smart refresh therefore compares a metric's kind, value, and descriptor without its timing, so its change detection stays as it was (core 11).
- The last usable rate updates only on an observation that shows consumption, or when no rate exists yet. Otherwise the quiet threshold would grow as the recent window slides over a quiet period, and quiet could never arrive.
- A line at 100% in the headline's limit group gives the "Limit reached" headline (AC9). The headline never shows remaining use for a group that is already blocked.
- Catalog keys need identifier characters for string symbol generation. The headline formats use semantic keys, like the existing "Accessibility sentence format".
- Evidence spans show one unit, rounded to the nearest hour from one hour up, e.g. "last 2 hours".
- Commit `4fd967f` implements steps 1–6 with Core and App tests. The review of 2026-10-08 reopened steps 3 and 4 and added steps 7 and 8.
- `learningDisplayLimit` is removed, and learning uses the maximum horizon. Learning still counts from the segment start until step 7 counts it from the last baseline.
- The maximum observation age is a separate policy field from the maximum gap. Both are 30 minutes.
- The headline and each forecast row line have their own `TimelineView`. Each one evaluates the forecasts at its own tick, so at a state change they can disagree for up to one minute.

## Risks

- Consumption is bursty, and models or workloads can change the rate at once. Conditional wording and short-lived evidence cannot remove this uncertainty.
- The interpolated window is still sensitive to a burst at either end. A single delayed publication can inflate the rate until the burst leaves the window.
- At whole-point resolution, weekly and monthly windows forecast only under sustained heavy use: two points within two hours. Most of the time they show learning and then no forecast text.
- A group line that is still learning does not stop the headline estimate (AC9 rule 3). Example: Weekly at 97% in learning, next to a five-hour estimate of 3 hours. Weekly can run out first. A stricter rule would hide the headline estimate almost always, because weekly windows are usually in learning.
- Rounded percentages and delayed publication can hide ongoing work. Quiet means no observed progress, not verified inactivity.
- A balance endpoint cannot reveal consumption offset by a top-up within one interval. Net-depletion forecasts must not be labeled spend.
- A local CLI can switch accounts without exposing a scope change. Core clears history only on the account changes in (AC11). A rate can span two accounts until a reset or correction re-baselines.
- An endpoint change does not cancel a fetch that is in progress. The first sample after the change can come from the previous endpoint, so a rate can cross the endpoint change for one segment. This risk is accepted.
- With a 30-minute maximum age, an estimate can rest on data up to 30 minutes old. The countdown stays anchored to the observation (AC7), but a burst inside those 30 minutes is not visible.
- Memory-only history adds warm-up after relaunch. Durable history is deferred to avoid stale patterns, privacy concerns, and storage lifecycle complexity.
- Receipt-time measurements are approximate. Delayed provider updates can create a misleading apparent burst.
- The thresholds trade availability for caution, especially under slow polling. Replay tests may justify revisions before release.
- New forecast text can crowd the popover. Keep allowance and reset information legible, and do not change compact status from an uncertain prediction.

## Objective

Estimate how long each supported allowance would last at the user's recent pace, using a shared Core engine and provider-owned measurement semantics.

## Context

- Status: implemented and on `main` (#75). Steps 1–8, 10, and 12–14 are done. The manual check in step 9 is still open, and step 11 tracks the provider opt-ins. The manual checks with Claude Code (providers 17) added step 10 (AC13); those with Codex (providers 18) added steps 12 (AC14), 13 (AC15), and 14 (AC16).
- This spec owns the contract, the engine, the app wiring, and the UI. Each provider opts in through its own spec: (providers 17, providers 18, providers 19, providers 20, providers 21, providers 22). Each opt-in lands on its own. A test provider covers the generic contract.
- Gemini CLI does not opt in. Its quota buckets are daily per model, but public sources do not show whether a day is a fixed block or slides (AC2). A bucket that has not been used reports a reset 24 hours after each read, so the reset moves with every refresh. Google also enforces limits that the buckets do not report. Since 2026-06-18, Google serves Gemini CLI only to Standard and Enterprise accounts. Revisit only with captured evidence of a fixed period.
- Periods of one day or less assume continued recent consumption (AC5). Longer periods use the average pace since the period started, which already includes nights, weekends, and breaks (AC13). Neither models a schedule or idle time.
- `Sources/Core/ProviderProtocol.swift` — `ProviderActivityMetric` carries numeric values for activity detection (core 09, core 11), but no period, limit, resolution, or per-metric timing. `UsageLine` has no stable ID.
- `Sources/Core/SmartRefreshPolicy.swift` — discards only `.stale` observations. `.unknown` and `.fresh` count equally as activity evidence.
- `Sources/App/QuotaViewModel+Fetch.swift`, `Sources/App/QuotaViewModel+Results.swift` — the accepted-result path is the only source of observations. Forecasting must not cause more provider work.
- `Sources/App/QuotaViewModel+Activity.swift` — existing sleep and wake observers, reused to invalidate evidence.
- `Sources/Core/AutoRefreshPreferences.swift` — the slow interval ranges from 1 to 60 minutes. Smart refresh polls faster during detected activity (core 08, core 11).
- `Sources/App/BudgetPace.swift` — sustainable daily and weekly allowances remain distinct from depletion forecasts (ui 18, ui 19, ui 22).
- `Sources/App/QuotaView.swift` — renders the provider's headline (`ProviderQuota.headline`) above the rows. An estimate, a beyond-reset forecast, or a reached limit replaces its reset countdown (AC9).
- Related: (ui 28) promotes a fallback credit or money pool while its limit group is exhausted and the pool has a balance above 0. It reuses this spec's line IDs, limit groups, and forecasts.
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
- **And** a fixed-period descriptor carries its limit, its reset timestamp, and its period length, never a localized label; the provider declares the length only after verifying it
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
- **Then** the App looks only at that line (AC15) and applies the first rule that matches:
  1. **Limit reached.** The line shows 100% in its current `UsageLine`, with or without a descriptor. The headline reads like "100% · Limit reached", with the line's reset countdown below it.
  2. **Uncertain near the limit.** The line is paused after its projected depletion time, or it has no estimate and less than two resolution steps left. The headline stays as the provider wrote it.
  3. **Estimate.** The line has an estimated forecast. The headline reads like "3% · About 1h 20m of use remaining", with a smaller line below it like "Based on the last 20 minutes".
  4. **Beyond reset.** The line has a beyond-reset forecast. The headline reads like "3% · Should last until reset", with a smaller line like "At your pace over the last 20 minutes". The row line reads like "Should last until reset · last 20 minutes".
- **And** when no rule matches, the headline stays as the provider wrote it
- **And** the headline shows the headline line's current value
- **And** the countdown stays visible in the row's existing reset text below the bar
- **And** the App composes the headline from the headline line's current value and its forecast; it never parses or edits the provider's headline string
- **Given** a row with a forecast descriptor is learning, quiet, too far apart, or paused
- **When** the row renders
- **Then** one small secondary line appears just above the row's reset text
- **And** learning reads like "Learning your usage rate…", and shows only from the first consumption after the last baseline until the maximum horizon has passed (AC14); a new segment after quiet does not restart this limit
- **And** once the maximum horizon passes without enough evidence for a rate, the row shows no forecast text; it never shows an estimate built from insufficient data
- **And** quiet reads like "No recent consumption detected"
- **And** two consecutive accepted intervals longer than the maximum gap read like "Updates too far apart to estimate", in place of a learning state that cannot complete
- **And** "Updates too far apart to estimate" lasts while the latest observation is younger than the last long interval plus the maximum gap; after that, the row shows the paused text
- **And** stale or interrupted evidence reads like "Forecast paused until fresh data arrives", without hiding the last-known usage and timestamp
- **Given** a row that is not the headline line has an estimated or beyond-reset forecast
- **When** the row renders
- **Then** it shows the estimate as the same kind of small secondary line above its reset text, e.g. "About 1d 4h of use remaining · last 2 hours"
- **And** the headline line's row shows no forecast line while the headline shows its forecast
- **And** in every state, the headline gains at most one secondary line and each row gains at most one forecast line
- **And** an exhausted allowance shows no forecast text in its row; the existing row already shows it
- **And** unsupported or unlimited measurements show no forecast UI
- **And** approximate timing appears in the help tooltip and VoiceOver, not as another visible line
- **And** a recent-pace estimate says "of use remaining", never just "left", so it cannot be confused with the reset time, e.g. "1d 2h left"; a long-period estimate says "Runs out in about" (AC13)
- **And** wording stays conditional; a calendar duration appears only for long periods, from the observed average pace (AC13), never from assumed daily habits
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
- **And** app relaunch starts a new baseline, so learning starts again with the next consumption (AC14)
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
- **And** a slow trace that gains one point after one hour shows no forecast text until that point, learning for two hours after it, and then no forecast text, never quiet and never an estimate (AC14)
- **And** a flat balance shows no forecast text after a baseline, a wake, or a purchase, and a first decrease of one resolution step starts learning (AC14)
- **And** tests (AC16): a flat stretch followed by steady consumption shows learning until the minimum evidence span has passed since the first consumption, then the rate of that consumption only
- **And** tests (AC15): other lines' estimates, uncertainty, and limits never change the headline; their estimates show in their rows, also when they run out first; a group line at 100% reads "Limit reached" in its row
- **And** local renders do not move the depletion timestamp or turn projected exhaustion into reported exhaustion
- **And** UI tests cover row association by ID, each headline rule (AC9), an unchanged headline when no rule matches, at most one forecast line per row, every localized and accessible state, long-duration formatting, and preservation of budget pace and compact status with forecasts present
- **And** App tests cover history clearing on every lifecycle event in (AC11), and the sleep, wake, and clock-change observers
- **And** long-period tests (AC13): a weekly window 3 days into the period at 7% is beyond reset, projecting about 16% at reset; at 60% it runs out in about 2 days; during the first day it shows no forecast text; one observation after a relaunch is enough; a five-hour window keeps the recent pace
- **And** a test provider using only the generic contract obtains forecasts without Core or App changes.

### AC13: Long periods use the average pace since the period started

- **Given** a fixed-period allowance whose period length is longer than one day, e.g. a weekly or monthly window
- **When** Core forecasts it
- **Then** the pace is the consumed value at the latest observation divided by the time since the period started
- **And** the period starts at the reset timestamp minus the period length
- **And** this pace already includes nights, weekends, and breaks, so the projected depletion is calendar time, not continuous use
- **And** the allowance is estimated only when this pace reaches the limit before the reset; otherwise it is beyond reset
- **And** during the first day of the period, the allowance shows no forecast text, because one heavy morning would distort the average
- **And** one accepted observation is enough, so the forecast appears at once after a relaunch
- **And** the recent-pace rules of (AC5) and the learning, quiet, and too-far-apart states do not apply to it
- **And** a passed reset, exhaustion, an interruption, and stale data keep their states from (AC7), with the long-period maximum observation age
- **And** the evidence span is the time since the period started
- **And** an estimate reads like "Runs out in about 2d" with "At your average pace over the last 3 days"; the row reads like "Runs out in about 2d · last 3 days"
- **And** beyond reset reads like "Should last until reset" with "At your average pace over the last 3 days"
- **And** periods of one day or less keep the recent pace of (AC5), because continuous use within a few hours is realistic and is the risk to warn about.

### AC14: Learning starts with observed consumption

- **Given** an allowance with a recent-pace forecast (AC5), i.e. a balance or a period of one day or less, has a baseline and no rate
- **When** no accepted sample since the baseline shows consumption
- **Then** the state is insufficient, so the row shows no forecast text
- **And** consumption is a fixed-period increase or a balance decrease between two accepted samples after the baseline; the baseline value itself is not consumption (AC3)
- **And** learning starts with the first consumption after the baseline and lasts at most the maximum horizon from it; a new segment after quiet does not restart this limit
- **And** a flat balance, e.g. credits used only after another pool runs out (providers 18), never shows "Learning your usage rate…" after a launch, wake, gap, or purchase
- **And** a balance increase re-baselines (AC3), so a purchase alone never starts learning
- **And** the quiet, too-far-apart, paused, exhausted, and estimated states are unchanged, and long periods keep (AC13).

### AC15: Each line's notice stays with its line

- **Given** a provider names its headline line, and other lines carry forecasts or reach their limits
- **When** the expanded card renders
- **Then** the headline speaks only for the headline line (AC9); no other line's limit, uncertainty, or forecast changes it, and the headline never shows another line's label
- **And** every other line shows its own forecast in its row, also when it runs out before the headline line resets
- **And** another line of the headline line's limit group at 100% reads "Limit reached" in its row, above its reset text
- **And** e.g., a five-hour window at 65% that should last until its reset keeps the headline "65% · Should last until reset", while the weekly row reads "Runs out in about 1d 10h · last 32 hours"
- **And** a weekly window that runs out in about 1h, next to a five-hour window that resets in 3 hours, shows "Runs out in about 1h · last 6 days" in its row; the headline still speaks for the five-hour window
- **And** a weekly window at 100% reads "Limit reached" in its row, while the headline speaks for the five-hour window.

### AC16: The first rate starts at the first consumption

- **Given** an allowance with a recent-pace forecast (AC5) has seen no consumption since its baseline
- **When** its first consumption arrives
- **Then** the rate's evidence starts at the last sample before that consumption, as after a quiet period (AC6); the flat stretch before it is not evidence
- **And** the minimum observation count and evidence span (AC5) apply from that sample, so the row shows learning until they are met
- **And** e.g., credits that stayed flat and then fell 0.94, 2.52, and 4.57 credits a minute show learning for about 10 minutes and then a rate near 210 credits an hour, not about 1.9 credits an hour from a 30-minute window that was mostly flat (providers 18)
- **And** long periods keep (AC13).

## Plan

1. [x] Add an optional forecast descriptor to `ProviderActivityMetric`, an optional `id` and `limitGroup` to `UsageLine`, and an optional `headlineUsageLineId` to `ProviderQuota`. All default to `nil`, so providers that do not opt in need no change. Unsupported semantics are expressed by omitting the descriptor.

   ```swift
   public struct AllowanceForecastDescriptor: Equatable, Sendable {
       public enum Accounting: Equatable, Sendable {
           case fixedPeriod(limit: Decimal, resetsAt: Date, length: TimeInterval) // metric value = consumed
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
3. [x] Estimate the rate with the interpolated fixed window from (AC5). Remove repeated samples as (AC5) describes. Do not add regression. The first version used the endpoint delta from the last sample before the cutoff. Extra observations moved that sample and changed the rate.
4. [x] Keep every threshold in one shared internal `AllowanceForecastPolicy`, with `let` fields. Apply the values in "Policy values" below. A provider with a stricter freshness limit marks its observation `.stale`. Per-provider calculator overrides stay out of scope.
5. [x] Feed accepted results into the forecaster from the existing results path. Invalidate on lifecycle revision changes, sleep and wake, and `NSSystemClockDidChange`. Clear history on provider disable or removal, credential save, delete, or import, and endpoint changes.
6. [x] In `QuotaView`, compose the headline from the binding line, with the smaller secondary line below it. Otherwise render the provider's headline unchanged. Pass every other forecast into `UsageLineRow` by line ID as one small line above the reset text. Use a `TimelineView` for aging. Leave compact status, the collapsed header, and menu-bar selection untouched. The layout follows "Card layout" below.
7. [x] Apply the fixes from the review of 2026-10-08:
   - [x] The headline rules in (AC9), with "Limit reached" and its accessibility sentence.
   - [x] Rejected data pauses its history: `.unknown` or `.stale` freshness, `isStale` quotas, invalid samples, and missing metrics (AC4).
   - [x] Core removes the history of a missing metric after the maximum horizon. `hasHistory` counts only the remaining histories (AC4).
   - [x] After an interruption, only a sample newer than the interruption becomes the new baseline (AC4).
   - [x] Two metrics with one usage line ID produce no forecast. Add a debug assertion (AC1).
   - [x] Compare each reset timestamp with the first one of the period (AC3).
   - [x] Count the learning limit from the last baseline. Remove `learningDisplayLimit` and use the maximum horizon (AC9).
   - [x] Decide the state in the order of (AC7).
   - [x] Report quiet when the estimate leaves the maximum horizon after 15 minutes without consumption (AC6).
   - [x] Use the beyond-reset headline only when the headline line has its own beyond-reset forecast (AC9).
   - [x] End "Updates too far apart to estimate" after the last long interval plus the maximum gap (AC9).
   - [x] Produce no estimate from a result that is not finite (AC5).
   - [x] Show "More than 4w of use remaining" above 4 weeks (AC9).
   - [x] Evaluate forecasts at the later of the timeline date and the current time, so a new sample never shows paused for one tick.
   - [x] Make Smart refresh compare the descriptor without its timing, so a new limit or period counts as a change (core 11).
   - [x] Move `QuotaHeadlineAndRows` to `QuotaView+HeadlineAndRows.swift`. Put only the forecast text inside the `TimelineView`.
   - [x] Use "headline" in code: rename `Title`, `titleBinding`, `ForecastTitle`, and the catalog keys.
   - [x] Remove `forecastNow`. Give `recordAllowanceObservation` an `at:` argument and pass `activityRuntime.now()`.
   - [x] Install the clock-change observer in its own method, with a `handleSystemClockDidChange` handler.
   - [x] Move the Smart refresh test to a `SmartRefreshPolicy*Tests` file and the default-nil test to `ProviderProtocolTests.swift`. Use `ActivityTestClock` in place of `TestDateClock`.
   - [x] Move the `Decimal` extension to `Decimal+Double.swift`, with internal access.
   - [x] Remove the doc comments that restate acceptance criteria.
   - [x] Make `observationAge(at:)`, `resetAll()`, and `policy` internal or remove them. Require `maximumRetainedObservations` of 2 or more.
8. [x] Add the tests from (AC12) that are still missing:
   - [x] Bursts at the start and at the end of a window.
   - [x] Extra observations without a new value, including repeated manual refreshes, produce the same rate.
   - [x] A 10-second fast interval keeps two hours of evidence.
   - [x] 15-minute and 29-minute slow intervals produce an estimate. A 31-minute slow interval shows "too far apart".
   - [x] A failed refresh adds no sample.
   - [x] Wake and the `NSSystemClockDidChange` observer. Core covers the forward clock jump.
   - [x] History clearing on `saveOverrideURL`, `importCredentials`, and `deleteKey`.
   - [x] Reset drift across many samples starts a new period.
   - [x] Missing metrics, duplicate usage line IDs, and the state order.
   - [x] Each headline rule, including "Limit reached" for a line without a descriptor.
   - [x] The beyond-reset accessibility sentence, and approximate timing in the headline.
   - [x] Budget pace and compact status with forecasts present. This replaces `testForecastsLeaveBudgetPaceAndCompactStatusUnchanged`, which cannot fail.
9. [ ] Run the focused tests and the repository validation gate. Then manually inspect normal-width popovers and VoiceOver in the limit-reached, estimated, beyond reset, learning, quiet, too far apart, and paused states.
10. [x] Long periods (AC13), from the manual check of 2026-10-12:
    - [x] Add the period length to `fixedPeriod`. Update the Claude Code opt-in (providers 17).
    - [x] Compute the average-pace forecast for periods longer than one day. Add the policy values below.
    - [x] Add the long-period wording to the catalog in all four languages.
    - [x] Let the composed headline wrap instead of truncating.
    - [x] Add the tests from (AC12).
11. [ ] Land the provider opt-ins, each on its own. Mark each one here as it lands:
    - [x] Claude Code five-hour and weekly windows (providers 17), #76
    - [x] Codex windows and credits row (providers 18), #78. The window descriptors stay open in (providers 18) until the weekly evidence confirms them.
    - [x] DeepSeek total balance (providers 19), #79
    - [x] OpenCode Go weekly and monthly windows (providers 20), #81
    - [x] z.ai weekly window (providers 21), #82. The live capture stays open in (providers 21).
    - [ ] Cursor included usage (providers 22)
    - [x] Kimi Code five-hour window (providers 29), #106
    - [ ] Kimi Code weekly and monthly windows (providers 28). Implemented, not yet merged.
12. [x] Learning starts with consumption (AC14), from the manual check of 2026-10-12 with Codex credits (providers 18). A flat credits row showed "Learning your usage rate…" with nothing to learn.
    - [x] Record the time of the first consumption after each baseline in `AllowanceHistory`. Without it and without a rate, the state is insufficient. With it, learning lasts the maximum horizon from that time.
    - [x] Update the Core tests that expect learning right after a flat baseline, and add the tests from (AC12).
    - [x] Update the Codex replay (providers 18): its baseline read and its flat credits now show no forecast text.
13. [x] Each line's notice stays with its line (AC15), from the manual check of 2026-10-12 with Codex (providers 18). A weekly estimate days away replaced the headline of a five-hour window that reset in 14 minutes.
    - [x] Bind the headline to the named headline line only. Remove the headline label and its catalog key.
    - [x] Show "Limit reached" in the row of another group line at 100%.
    - [x] Update the headline tests and add the tests from (AC12).
14. [x] The first rate starts at the first consumption (AC16), from the Codex capture of 2026-10-12 (providers 18). The first credits estimate after the switch read "About 2W 4d" while credits fell about 210 an hour.
    - [x] Start a new segment at the previous sample when the first consumption after a baseline arrives.
    - [x] Update the tests that expect an estimate right after a flat stretch, and add the tests from (AC12).

### Card layout

The panel is small, so forecasts add as little text as possible:

- Only the headline rules in (AC9) change the headline. They replace the headline's reset countdown, which the row still shows below its bar. A smaller line under the headline gives the evidence, the condition, or the reset. A long headline wraps; it is never truncated.
- Every other state is one small gray line inside its row, just above the reset text. It never touches the headline. A long text wraps to a second line; it is never truncated.
- A row that is not the headline line shows its estimate, or "Limit reached", as the same small line (AC15).
- Approximate timing lives in the tooltip and VoiceOver only.

```
Estimated                             Weaker states (headline unchanged)
3% · About 1h 20m of use remaining    3% · resets in 5 hours
Based on the last 20 minutes          5-hour window                 3%
5-hour window                 3%      ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬                     Learning your usage rate…
resets in 5 hours                     resets in 5 hours
Weekly                   6% used
▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
About 1d 4h of use remaining · last 2 hours
1d 2h left  About 83,8%/day available

Beyond reset                          Another line runs out first (AC15)
3% · Should last until reset          3% · Should last until reset
At your pace over the last 20 minutes At your pace over the last 20 minutes
                                      Weekly                  95% used
                                      ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
                                      About 30m of use remaining · last 40 minutes

Limit reached                         Another line reached its limit (AC15)
100% · Limit reached                  3% · resets in 5 hours
resets in 2h 10m                      Weekly                 100% used
                                      ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
                                      Limit reached
                                      resets in 2d 4h
```

The other weak-state lines take the learning line's place: "No recent consumption detected", "Updates too far apart to estimate", and "Forecast paused until fresh data arrives". When a limit group runs out and its fallback pool has a balance, (ui 28) shows that pool on top; the pool is then the headline line (AC15).

### Policy values

| Rule | Default |
|---|---|
| Recent horizon | 30 minutes; the window grows in 30-minute steps |
| Maximum horizon | 2 hours, used only to reach the minimum consumption |
| Minimum accepted observations | 3 |
| Minimum evidence span | 10 minutes |
| Minimum consumption | 2 resolution steps |
| Quiet threshold | 2 × resolution ÷ last usable rate, clamped to 15 minutes – 2 hours; requires a prior usable rate |
| Learning display limit | The maximum horizon after the first consumption since the last baseline; no forecast text before that consumption or after the limit (AC14) |
| Maximum observation gap | 30 minutes between the source timestamps of accepted samples |
| Maximum observation age | 30 minutes |
| "Too far apart" trigger | 2 consecutive accepted intervals above the maximum gap |
| Reset tolerance | 5 minutes from the first reset timestamp of the period |
| Future timestamp tolerance | 60 seconds; a later measurement time is inconsistent timing |
| Maximum retained samples | 256 per metric, after Core removes repeated values |
| Longest displayed estimate | 4 weeks |
| Long period | A period length longer than 1 day (AC13) |
| Long-period warm-up | 1 day after the period starts; no forecast text before |
| Long-period maximum observation age | 6 hours; the average pace changes slowly, so idle time does not pause it |

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

- A descriptor's timing changes on every write. Smart refresh therefore compares a metric's kind, value, and descriptor without its timing (core 11). It compares reset timestamps within the reset tolerance, because OpenCode Go and Claude Code jitter them on every read (providers 17, providers 20). Exact equality would hold Smart refresh in its fast cadence.
- The last usable rate updates only on an observation that shows consumption, or when no rate exists yet. Otherwise the quiet threshold would grow as the recent window slides over a quiet period, and quiet could never arrive.
- A line at 100% in the headline's limit group gives the "Limit reached" headline (AC9). The headline never shows remaining use for a group that is already blocked.
- Catalog keys need identifier characters for string symbol generation. The headline formats use semantic keys, like the existing "Accessibility sentence format".
- Evidence spans show one unit, rounded to the nearest hour from one hour up, e.g. "last 2 hours".
- Commit `4fd967f` implements steps 1–6 with Core and App tests. The review of 2026-10-08 reopened steps 3 and 4 and added steps 7 and 8.
- `learningDisplayLimit` is removed. Learning lasted the maximum horizon from the last baseline until (AC14) moved its start to the first consumption.
- The maximum observation age is a separate policy field from the maximum gap. Both are 30 minutes.
- The window grows only to reach the minimum consumption. The observation count covers the observations from the sample at or before the window start to the latest one, including removed repeated samples. Without that start sample, a 29-minute interval has only two observations in a 30-minute window.
- History keeps the last sample at or before the maximum-horizon cutoff, so the 2-hour window can interpolate its start.
- `Decimal` division returns NaN on underflow, e.g. a resolution of 10⁻¹⁰⁰. Core treats a rate or a projection that is not finite as no estimate.
- A quota without an activity observation pauses the provider's histories, the same as `.unknown` freshness.
- A manual check with Claude Code on 2026-10-09 showed the five-hour row beyond reset while weekly was learning. The earlier rule 4 needed every group line with a forecast to be beyond reset, so the headline never changed. Weekly windows move about one point every few hours, so they rarely form a rate. Rule 4 now ignores group lines without a rate, like rule 3.
- The same check showed the row line "Not expected to run out before reset · last 10 minutes" truncated at normal width. Row lines now wrap.
- The beyond-reset wording "Not expected to run out" with "before reset at recent pace" read as two unrelated fragments, and named no evidence span. It is now "Should last until reset" with "At your pace over the last 20 minutes", matching the estimate headline's "Based on the last …".
- A manual check on 2026-10-12 showed "Weekly 7% · About 1d 22h of use remaining" in the headline, 4 days before the weekly reset. The recent pace was about 2 points per hour over the last hour, and the engine treated 46 hours of continuous use as calendar time. The week so far averaged about 2.3 points per day, which projects about 16% at reset. Periods longer than one day now use that average (AC13). The composed headline also truncated; it now wraps.
- A manual check on 2026-10-12 showed the composed headline as the raw key "Forecast headline format". `String(localized:)` without `bundle:` reads `Bundle.main`, which has no catalog, so name-style keys fall back to the key. The forecast format keys now pass `bundle: .module`. The other lookups follow (ui 29).
- A capture of Claude Code `/usage` writes on 2026-10-09 (229 writes, 09:39–14:46) showed `resets_at` in whole minutes, with a flip between two neighboring minutes on almost every write. The spread was exactly 60 seconds, which is the old tolerance with no margin. The reset tolerance is therefore 5 minutes. A real reset moves by hours or days. A sliding window moves its reset with each use, so it passes 5 minutes from the period's first reset after 5 minutes of use (providers 17).
- Two histories that name one usage line ID, e.g. one missing and one new, also produce no forecast for that line. The debug assertion sits in the public `record`; Core tests call the internal path that has no assertion.
- An interruption keeps the later of the sleep and wake times, so only a sample newer than the wake can become the baseline.
- Rule 2 in (AC9) needs data that only Core has. `AllowanceForecast` carries `isUncertainNearLimit`: the state is paused after the projected depletion time, or the state has no estimate and less than the minimum consumption remains. An exhausted measurement also sets it. A passed reset clears it.
- "Limit reached" reads the line's unrounded percentage, so a line at 99.6% that displays "100%" does not match. A line without a reset date counts as the one that resets last.
- "Limit reached" needs no forecast history. Without history, the headline renders once with the rows and has no `TimelineView`.
- The headline keeps its accessibility sentences as ordered parts. Semantic catalog keys do not resolve under `swift test`, so tests assert the parts, not the joined label.
- The headline and each forecast row line have their own `TimelineView`. Each one evaluates the forecasts at its own tick, so at a state change they can disagree for up to one minute.
- The texts of a budget-pace row live in `PacedUsageLineText`. Thus a test can compare the row with and without a forecast. Compact status reads only the quota, so a forecast cannot change it.
- The App forecast tests use an `.apiKey` test provider, because `saveOverrideURL` ignores providers without an API key.
- With (AC14), `AllowanceHistory` no longer needs the baseline time; the learning limit counts from the first consumption. Tests that showed a new baseline by its learning state now expect insufficient, and the App lifecycle tests check for an existing history with no row text.
- With (AC15), the headline label, its "Forecast labeled value format" key, and the choice of the latest reset among lines at 100% are gone. The limit group now decides only which other lines read "Limit reached" in their rows.
- Before (AC16), one decrease of many resolution steps after a flat stretch gave an estimate at once, because the flat samples supplied the observation count and the evidence span (AC5). (AC16) starts the segment at the sample before the first consumption, so the flat stretch no longer counts.
- With (AC16), the Claude Code replay forms a faster rate, turns quiet after 15 minutes without a rise, and learns again on the next rise (providers 17). The window-growth test now starts its consumption early enough to need the 60-minute window.

## Risks

- Consumption is bursty, and models or workloads can change the rate at once. Conditional wording and short-lived evidence cannot remove this uncertainty.
- The interpolated window is still sensitive to a burst at either end. A single delayed publication can inflate the rate until the burst leaves the window.
- At whole-point resolution, weekly and monthly windows forecast only under sustained heavy use: two points within two hours. Most of the time they show learning and then no forecast text.
- With (AC15), the headline can read "Should last until reset" for the five-hour window while the weekly row says the week runs out first, or reads "Limit reached". Each notice speaks for its own window, so the headline alone does not say whether usage is blocked.
- Rounded percentages and delayed publication can hide ongoing work. Quiet means no observed progress, not verified inactivity.
- A balance endpoint cannot reveal consumption offset by a top-up within one interval. Net-depletion forecasts must not be labeled spend.
- A local CLI can switch accounts without exposing a scope change. Core clears history only on the account changes in (AC11). A rate can span two accounts until a reset or correction re-baselines.
- An endpoint change does not cancel a fetch that is in progress. The first sample after the change can come from the previous endpoint, so a rate can cross the endpoint change for one segment. This risk is accepted.
- With a 30-minute maximum age, an estimate can rest on data up to 30 minutes old. The countdown stays anchored to the observation (AC7), but a burst inside those 30 minutes is not visible.
- Memory-only history adds warm-up after relaunch. Durable history is deferred to avoid stale patterns, privacy concerns, and storage lifecycle complexity.
- Receipt-time measurements are approximate. Delayed provider updates can create a misleading apparent burst.
- The thresholds trade availability for caution, especially under slow polling. Replay tests may justify revisions before release.
- New forecast text can crowd the popover. Keep allowance and reset information legible, and do not change compact status from an uncertain prediction.

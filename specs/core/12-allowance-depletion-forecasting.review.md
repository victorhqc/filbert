# TEMPORARY — review notes for core 12

> [!NOTE]
> This file is a scratch document. It is not a spec. Do not commit it. Delete it
> after the specs and the code include the decisions.

Source: adversarial review of `feat/allowance-depletion-forecasting` against
`main` on 2026-10-08. The gate passed: SwiftFormat, SwiftLint, `swift build`,
and `swift test` (238 tests, 0 failures).

## Decision table

All decisions are in the specs as of 2026-10-08: core 12, providers 17–20, and
ui 28. The code changes are in core 12 Plan steps 3, 4, 7, and 8.

| # | Finding | Severity | Decision | Spec to change |
|---|---|---|---|---|
| 1 | Spec 18 contradicts core 12 and ui 28 | Blocker | Credits show a forecast. 1b and 1c approved | 18, 28, 12 |
| 2 | Title shows hours of use at the limit | Blocker | Approved: rules 1–4 and option A | 12 |
| 3 | More polls change the rate | Major | Use a robust algorithm | 12 |
| 4 | 256-sample cap cuts the 2-hour horizon | Major | Fix | 12 |
| 5 | 15-minute interval hits "too far apart" | Major | Gap goes to 30 min. Notes below | 12 |
| 6 | Endpoint change and in-flight fetch | Major | Accept the risk | 12 (Risks) |
| 7 | Absent metric keeps its history | Major | Approved: missing = paused, removed after 2 hours | 12 |
| 8 | No contract field for an account change | Major | Approved: option A (App events only) | 12 |
| 9 | Title value and estimate from different observations | Major | Approved: rejected data pauses | 12 |
| 10 | AC12 test list not complete | Major | Approved: list the tests as pending in the spec | 12 |
| 11 | No consumer, spec status wrong | Major | Decided: no merge until the provider specs are complete | 12 |
| 12 | Spec 12 contradicts itself in 4 places | Major | Approved: fix the 4 contradictions as proposed | 12 |
| 13 | Re-baseline after interrupt accepts an older sample | Minor | Approved | — |
| 14 | State order: paused over exhausted, exhausted after reset | Minor | Approved | 12 |
| 15 | Two metrics with one usage line ID | Minor | Approved | 12 |
| 16 | No field for a stricter provider freshness limit | Minor | Approved | 12 |
| 17 | Smaller state defects (5 items) | Minor | Approved: fix all 5 | 12 |
| 18 | Smart refresh does not see a limit or reset change | Minor | Approved | — |
| 19 | Structure and convention breaks | Minor | Approved | 12 |
| 20 | Public API is larger than its use | Minor | Approved | — |

---

## Part A — Your comments on findings 1 to 6

### 1. Spec 18 contradicts core 12 and ui 28

**Your decision:** the credits row shows a forecast. A previous iteration of
spec 18 did not get this update.

**Notes:** this decision removes the first contradiction. The credits row then
uses the core 12 states with no exception:

- After launch, wake, or a gap, the row shows "Learning your usage rate…" for 2
  hours.
- If credits stay flat, the row then shows no text (`.insufficient`).
- When credits start to decrease, the row shows an estimate.

Credits can stay flat for days. Thus "Learning your usage rate…" shows on the
credits row for 2 hours after each launch and each wake. We think that this is
correct, because it is the same rule as the weekly windows. Tell me if you want
a different rule for a pool that is not in use.

Two sub-points of finding 1 are still open:

- **1b. Order of specs 18 and ui 28.** Spec 18 AC3 declares credits as the
  fallback pool. The field for that declaration (`fallbackForLimitGroup`) comes
  from ui 28. Core 12 Plan step 8 puts spec 18 before ui 28.
  - **Proposal:** remove the fallback declaration from spec 18. Ui 28 Plan
    step 6 already adds the declaration to the Codex provider. Spec 18 then
    has no dependency on ui 28.
- **1c. The actor that promotes the pool.** Ui 28 AC2 says "the provider
  promotes the pool". Ui 28 Plan step 2 puts a promotion tracker in the App.
  - **Proposal:** the App promotes. The provider only declares the candidate
    pool. Change ui 28 AC2 to "the app promotes the pool". This agrees with
    the orthogonal provider rule in `AGENTS.md`.

Also decide Question 10 below. It asks if the credits row is in the window limit
group.

### 2. Title shows hours of use at the limit

**Your question:** why `.paused`? Is the user at 100%, or does the user still
have 10%?

**Answer:** the engine does not know. In the trace, the last measurement shows
90%. Then the refreshes fail, so no new measurement arrives. At T+10 min, the
local clock reaches the projected depletion time. AC7 says: "reaching a
projected depletion timestamp locally without a confirming observation pauses
the estimate. It never reports exhaustion." Thus `.paused` means "we expected
the allowance to run out by now, but no measurement confirms it".

The defect is not `.paused` itself. The defect is the next step. The title
ignores the paused 5-hour line and uses the weekly estimate. Thus the title
says "Weekly 50% · About 8h 10m of use remaining" when the user is probably
blocked.

**Your requirement:** if the user is at 100%, the title says 100% used, and
nothing more is available.

**Proposal — title rules for one limit group, in this order:**

1. **Limit reached.** If a line in the group shows 100% in its current
   `UsageLine`, the title shows that line with "Limit reached". The line can be
   a line with or without a descriptor. The detail line shows the reset
   countdown of that line. Example:

   ```
   Weekly 100% · Limit reached
   resets in 2d 4h
   ```

   This rule reads the displayed line, not the forecast state. Thus it also
   covers a rolling window without a descriptor (spec 20). Ui 28 can replace
   this title later, when a fallback pool starts to decrease.
2. **No estimate when a group line is uncertain near its limit.** The title
   keeps the provider title if one of these is true:
   - A group line is `.paused` after it reached its projected depletion time.
   - A group line has no estimate, and its remaining allowance is less than 2
     resolution steps. The engine cannot learn a rate for this line before the
     line runs out. Example: Weekly at 99% with a resolution of 1 point.
3. **Earliest estimate.** Otherwise, the earliest estimate in the group binds,
   as today.
4. **Beyond reset.** If each line in the group with a forecast is beyond reset,
   and the title line is one of them, the title shows "Not expected to run
   out".

**Open point:** rule 2 does not cover Weekly at 97% in learning, next to a
5-hour estimate of 3 hours. Weekly can run out before the 5-hour window. A
stricter rule keeps the provider title when any group line is in learning. But
weekly windows are usually in learning (spec 12 Risks), so the title estimate
then almost never shows for Claude Code. We recommend rule 2 as written, with
this risk in the Risks section. Please decide.

**New strings:** "Limit reached", and its accessibility sentence.

### 3. More polls change the rate

**Your decision:** use a robust algorithm. It must give the same rate when the
user clicks refresh many times.

**Proposal — fixed time window with interpolation:**

- The window is a fixed time span `[latest − H, latest]`. It is not "from the
  last sample before the cutoff".
- The engine calculates the value at `latest − H` by linear interpolation
  between the 2 samples on the two sides of that time. If the history is
  shorter than `H`, the window starts at the first sample.
- Rate = (latest value − interpolated start value) ÷ `H`.
- To reach the minimum consumption, the engine increases `H` in fixed steps:
  30, 60, 90, then 120 min. The steps are times, not samples.

**Why it is robust:** consumption is cumulative and does not decrease in a
period. Thus a sample in a flat part of the history adds no information.
Interpolation in a flat part gives the same value with or without that sample.
Interpolation in a linear part also gives the same value. The trace from the
review then gives 8/30 points each minute for both trace A and trace B.

**Limit:** a poll that shows a new value at a new time adds real information.
Example: a poll at t=28 that shows 1 point, not 0. This poll can change the
rate, and it must. AC5 must say "extra polls that show no new value do not
change the rate". It must not say "polling cadence alone".

**Repeated clicks:**

- Source-timed providers: a repeated read has the same timestamp. The engine
  already ignores it.
- Receipt-timed providers: each click adds a sample. With interpolation, these
  samples do not change the rate. The minimum evidence span (10 min) stops a
  fast series of clicks from becoming false evidence.
- The minimum observation count (3) must count observations received. It must
  not count stored samples, because finding 4 removes repeated samples.

**Spec change:** AC5 bullet 1 and Plan step 3. Remove the claim that endpoint
delta is "cadence-invariant by construction". Add a replay test with bursts and
with random extra polls in flat parts.

### 4. 256-sample cap cuts the 2-hour horizon

**Your decision:** fix it.

**Proposal — remove repeated samples:**

- When the engine appends a sample, it removes the previous sample if 3
  conditions are true:
  - The previous sample and the sample before it have the same value as the
    new sample.
  - The gap rules (finding 5) still accept the new interval.
  - The previous sample is not the start of the segment.
- With the interpolation from finding 3, this removal loses no information.
- The cap of 256 then applies only to samples with different values. At a
  resolution of 1 point, the history must change 256 times in 2 hours before
  the cap applies.
- Keep the cap as a memory limit (AC11).

This change also stops repeated clicks from filling the history.

### 5. 15-minute interval hits "too far apart"

**Your proposal:** change the maximum gap to 30 minutes.

**Answer:** yes, for each slow interval up to 29 minutes. The app starts the
next fetch one interval after the previous result. Thus the real gap is the
interval plus the fetch time:

| Slow interval | Real gap | Result with a 30-min gap |
|---|---|---|
| 1–29 min | Interval + a few seconds | Contiguous. The forecast works |
| 30 min | 30 min + fetch time | On the limit. The same defect as today at 15 min |
| 31–60 min | More than 30 min | "Updates too far apart to estimate" |

The slow interval options are each minute from 1 to 60
(`AutoRefreshPreferences.swift:12`). So the defect moves from 15 min to 30 min.
It does not go away.

**Proposals to go with the 30-min gap:**

1. Fix the loop that makes learning never end. Count the learning limit from
   the baseline, not from each segment (Question 4). The edge then gives
   "too far apart" in a predictable way, not a learning state with no end.
2. Change spec line 276 to: "A provider refreshed every 30 minutes or less
   often shows 'Updates too far apart to estimate'."
3. Keep "maximum age" separate from "maximum gap". The age check pauses a
   forecast when the latest data is old. With a 30-min age, an estimate stays
   on screen with data up to 30 min old. The countdown stays correct because
   AC7 anchors it to the observation. But a burst in those 30 min is not
   visible. We recommend the same 30 min for both, and a note in Risks.
4. The recent horizon (30 min) is then equal to the maximum gap. A 30-min
   window can contain only 2 samples at a 25-min cadence. The window extension
   from finding 3 (60, 90, 120 min) solves this. No other change is necessary.

### 6. Endpoint change and in-flight fetch

**Your decision:** accept the risk.

**Spec change:** add to Risks: "An endpoint change does not cancel a fetch that
is in progress. The first sample after the change can come from the previous
endpoint. A rate can then cross the endpoint change for one segment."

---

## Part B — Proposals for findings 7 to 20

### 7. Absent metric keeps its history

**Proposal:**

- The contract says that a provider withdraws a forecast when it sends the
  metric without a descriptor. This case already clears the history.
- A metric that is absent from a fresh observation is "missing", not
  "withdrawn". The history is paused. This text is correct: Claude Code omits
  stale windows, and "Forecast paused until fresh data arrives" is true for
  them.
- The engine removes a history after the maximum horizon (2 hours) with no
  sample. This limits memory, and it stops the paused text.
- `hasHistory` counts only histories that the engine did not remove. Thus the
  60-second `TimelineView` stops too.

### 8. No contract field for an account change

**Option A (recommended):** narrow AC3 and AC11 to the account changes that the
App knows: credential save, delete, import, and endpoint change. These already
clear the history. Keep the current Risks line about a CLI that changes
accounts without a signal.

**Option B:** add an optional opaque `accountScope: String?` to
`ProviderActivityObservation`. A change clears the provider history. A provider
sets it only from data that it already reads. The App never logs or stores it.

Option A needs no code. Option B adds a contract field that no provider spec
uses at this time. Use option B only if spec 17 or spec 18 can supply the
value.

### 9. Title value and estimate from different observations

**Proposal:** when the forecaster rejects data for a metric that has a history,
the history goes to `.paused` until the next accepted sample. These cases cause
a rejection:

- An observation with `.unknown` or `.stale` freshness pauses each history of
  that provider.
- A metric with a descriptor whose sample fails validation pauses that history.
- A missing metric pauses that history (finding 7).

The title and the row then show "Forecast paused until fresh data arrives",
not an old estimate next to a new value. Also see Question 11 for
`quota.isStale`.

### 10. AC12 test list not complete

Add these tests:

- A burst at the start and at the end of a window (with finding 3).
- Random extra polls in flat parts give the same rate (finding 3).
- A fast interval of 10 s keeps 2 hours of evidence (finding 4).
- A 15-min and a 29-min interval give an estimate. A 31-min interval gives
  "too far apart" (finding 5).
- A failed refresh adds no sample.
- Wake, a forward clock jump, and the `NSSystemClockDidChange` observer.
- History clear on `saveOverrideURL`, `importCredentials`, and `deleteKey`.
- The beyond-reset accessibility sentence, and approximate timing in the title.
- "Limit reached" and the uncertain-group rules (finding 2).
- Replace `testForecastsLeaveBudgetPaceAndCompactStatusUnchanged`. The new
  test must give forecasts to the rows and then compare budget pace and compact
  status.

### 11. No consumer, spec status wrong

**Decision:** the branch does not merge until the provider specs are complete,
because no consumer is ready.

**Spec change:**

- Change the status line to: "Status: steps 1–6 implemented. The branch merges
  only after the provider opt-ins in step 8 and the manual inspection in step
  7."
- Change Context line 8 to agree with this decision.
- Mark Plan steps 1–6 with `[x]`.

### 12. Spec 12 contradicts itself in 4 places

| Point | Proposal | Reason |
|---|---|---|
| Title value | The binding line's value. Change line 138 | Agrees with the example and the code |
| Row that loses its line | The binding line. Change AC9 line 147 | Agrees with the Card layout and the code. Each estimate shows one time only |
| Learning limit | Count from the last baseline. A new segment after quiet does not restart it. Remove `learningDisplayLimit` and use `maximumHorizon` | Stops the learning loop (finding 5). One setting, not two |
| Reset tolerance | Compare with the first `resetsAt` of the period. Store it at each baseline | Small moves cannot add up. A rolling window cannot look like a fixed period |

### 13. Re-baseline after interrupt accepts an older sample

**Proposal:** store the interrupt time. After an interrupt, accept a new
baseline only if its time is after the interrupt time. Ignore older samples, as
the normal path does.

### 14. State order

**Proposal — new order in `state(at:)`:**

1. Reset passed (fixed period) → `.paused`.
2. Latest sample at or past the limit → `.exhausted`. Exhaustion stays true in
   its period, even when the sample is old.
3. Interrupted → `.paused`.
4. Then the current order: too far apart, stale, quiet, learning, estimate.

An exhausted line then shows no text after a sleep. A reset that passed clears
the exhausted state.

### 15. Two metrics with one usage line ID

**Proposal:** if 2 metrics in one observation name the same `usageLineId`, the
forecaster records neither of them, and no forecast shows for that line. Add a
contract test. Add a debug assertion so that the defect is visible in
development.

### 16. No field for a stricter provider freshness limit

**Proposal:** remove the clause "or a stricter provider freshness limit" from
the policy table. Remove "publication delay" from Plan step 4. A provider with
a stricter limit marks its observation `.stale`. The engine already ignores
stale observations. Publication delay is already in the source timestamp. This
needs no Core change, so specs 18–20 stay orthogonal.

### 17. Smaller state defects

| Defect | Proposal |
|---|---|
| No text between estimated and quiet | If a usable rate existed, the estimate is gone, and no consumption occurred for at least 15 min, the state is `.quiet` |
| Beyond-reset title uses another line | Use the beyond-reset title only if the title line itself has a `.beyondReset` forecast |
| "Too far apart" stays after refreshes stop | Show `.tooFarApart` only while the age is less than the last long interval plus the maximum gap. After that, show `.paused` |
| NaN or very large estimates | Core rejects a result that is not finite. For a balance, an estimate of more than 4 weeks shows "More than 4w of use remaining" |
| "Paused" for 1 tick after a new sample | The presentation uses `max(context.date, forecastNow())` as the time |

### 18. Smart refresh does not see a limit or reset change

**Proposal:** `measuresSameValue` compares `kind`, `value`, and the descriptor
without its timing (accounting, unit, resolution, usage line ID). Thus a new
limit or a new period counts as a change. A new timestamp alone does not.

### 19. Structure and convention breaks

| Break | Proposal |
|---|---|
| `QuotaHeadlineAndRows` in a forecast file | Move it to `QuotaView+HeadlineAndRows.swift`. Put only the forecast text in the `TimelineView` |
| "Title" and "headline" | Use "headline" in the code and in the spec, because `ProviderQuota.headline` already exists. Rename `Title`, `titleBinding`, `ForecastTitle`, and the catalog keys |
| Second clock `forecastNow` | Use `activityRuntime.now()`. Give `recordAllowanceObservation` an `at:` argument, the same as `recordActivityObservation` |
| Clock observer in the activity runtime | Install it in a separate method with a `handleSystemClockDidChange` handler |
| Tests outside their suites | Move the Smart refresh test to a `SmartRefreshPolicy*Tests` file. Move the default-nil test to `ProviderProtocolTests.swift`. Use `ActivityTestClock`, not `TestDateClock` |
| `Decimal` extension in the policy file | Move it to `Decimal+Double.swift`, with internal access |
| Commit scope `app` | We do not change git history. Use `feat(core, app)` or the correct scope in the PR title and in the squash message |
| Comments that restate ACs | Remove the 3 comments |
| No `[x]` in the Plan | See finding 11 |

### 20. Public API is larger than its use

**Proposal:**

- Make `AllowanceForecastPolicy` fields `let`. Make the memberwise init
  internal. Tests use `@testable import`.
- Make `observationAge(at:)`, `resetAll()`, and `policy` internal, or remove
  them.
- Add a `precondition` that `maximumRetainedObservations` is 2 or more.

---

## Part C — Questions with proposed answers

Approved on 2026-10-08: questions 1, 3, 4, 5, 6, 7, 8, 9, 10, and 11.
Question 2 waits for the decision on finding 2.

| # | Question | Proposed answer |
|---|---|---|
| 1 | Does this branch merge alone? | No. It is the base for spec 17 (finding 11) |
| 2 | Title when a group line is uncertain or at 100% | Finding 2 rules 1–4. Decide the open point in finding 2 |
| 3 | Title value: named line or binding line? Which row loses its line? | Binding line for both (finding 12) |
| 4 | Learning limit from baseline or from each segment? | From the last baseline (finding 12) |
| 5 | Reset tolerance per sample or per period? | Per period (finding 12) |
| 6 | "Accepted interval": refreshes or source timestamps? | The time between the source timestamps of accepted samples. A 15-min interval works with the 30-min gap (finding 5) |
| 7 | How does a provider report an account change? | Option A: only App events (finding 8) |
| 8 | Absent metric: missing or withdrawn? | Missing. Pause, then remove after 2 hours (finding 7) |
| 9 | `resolution` for currency and credits | The smallest change that the upstream value can show, in the unit of the metric value. Example: 0.01 for a balance in USD with cents. Add this definition to the descriptor in core 12 |
| 10 | Is the Codex credits row in the window limit group? | No. Its `limitGroup` is `nil`. It refers to the window group only with `fallbackForLimitGroup` (ui 28) |
| 11 | Does `quota.isStale` stop a record? | Yes. Treat it as `.stale`, and pause the histories (finding 9) |

---

## Part D — Spec edits after we agree

- **Core 12:**
  - Context: the status line.
  - AC3: the reset tolerance per period, and account change option A.
  - AC4: rejected data pauses.
  - AC5: the interpolated window.
  - AC6: the gap of 30 min.
  - AC9: the title rules, the binding line, and the learning limit.
  - AC12: new tests.
  - Plan: steps 3 and 4, the policy table, `[x]` marks, and the "headline" term.
  - Risks: the endpoint change, the 30-min age, and the learning sibling (finding 2).
  - Descriptor: define `resolution`.
- **Providers 18:**
  - AC3: the credits row shows a forecast.
  - Remove the fallback declaration.
  - The credits row has no limit group.
- **Ui 28:**
  - AC2: the app promotes the pool.
  - Make sure that the "Limit reached" title (finding 2, rule 1) and the
    promoted title do not conflict.
- **Providers 17 and 20:** make sure that their windows agree with the new title
  rules and the 30-min gap.

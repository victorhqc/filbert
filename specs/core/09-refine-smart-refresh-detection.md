## Objective

Make Smart refresh react only to provider-reported usage, credit, or availability changes through an explicit, testable activity signal while giving users finer control over its polling intervals.

## Context

- `Sources/Core/SmartRefreshPolicy.swift` — currently compares display-oriented quota fields, so reset dates, labels, units, limits, and detail text can produce false activity.
- `Sources/Core/ProviderProtocol.swift` — needs a provider-neutral activity observation that is separate from `ProviderQuota` presentation data.
- `Sources/Core/AutoRefreshPreferences.swift` — currently offers only five slow and five fast interval choices across otherwise suitable ranges.
- `Sources/App/QuotaViewModel+Lifecycle.swift` — consumes policy decisions and schedules the next slow or fast check.
- `Sources/App/RefreshSettingsView.swift` — renders the discrete slow and fast interval sliders for Regular and Smart modes.
- `Sources/Providers/ZAI/ZAIProvider.swift`, `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift`, `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift`, `Sources/Providers/DeepSeek/DeepSeekProvider.swift`, and `Sources/Providers/Cursor/CursorProvider.swift` — each provider already knows which response fields represent consumption, credits, and account availability.
- `Tests/CoreTests/SmartRefreshPolicyTests.swift` — needs a table-driven regression matrix for real activity and presentation-only changes.
- `Tests/CoreTests/AutoRefreshPreferencesTests.swift` and `Tests/AppTests/AutoRefreshViewModelTests.swift` — need coverage for the denser interval choices, persistence, and rescheduling.
- Provider suites need focused mapping tests that prove each provider emits the intended activity observation.
- This refines meaningful-change detection from (core 08 AC5, core 08 AC7) without changing its per-provider cadence, three-unchanged-check exit, or failure behavior.

## Acceptance Criteria

### AC1: Existing false positives and missed signals are captured

- **Given** two successful quota results whose displayed reset date, label, unit, total allowance, detail text, line order, or presentation metadata differs while current usage, credits, and availability are unchanged
- **When** the Smart comparison regression tests run
- **Then** every case is classified as unchanged
- **And** changing only `lastUpdated`, `headline`, `error`, `isStale`, or peak-hours metadata remains unchanged
- **And** a provider-reported availability transition is classified as changed even when the rendered headline and quota lines are otherwise unchanged.

### AC2: Providers emit an explicit activity observation

- **Given** a provider maps a successful upstream response into `ProviderQuota`
- **When** it describes the response for Smart refresh
- **Then** it supplies a provider-neutral activity observation containing zero or more stable metrics and an optional availability state
- **And** every metric has a nonlocalized stable ID, a kind of `usage` or `credits`, and a canonical comparable value
- **And** availability distinguishes `available`, `unavailable`, and `unknown`
- **And** the observation contains no API key, account identifier, request body, or user-facing formatted string
- **And** adding a provider requires no provider-ID branch in Core, App, or another provider.

### AC3: Only semantic activity changes enter fast mode

- **Given** a provider has an established Smart baseline
- **When** a later successful observation changes a usage metric, changes a credit metric, adds or removes a tracked usage or credit metric, or changes between known availability states
- **Then** that provider enters or remains in fast mode
- **And** the unchanged-check counter resets to zero
- **And** the transition identifies only the reason categories `usage`, `credits`, or `availability`
- **And** one provider's transition does not alter another provider's baseline, counter, cadence, or next refresh date.

### AC4: Display and quota metadata cannot enter fast mode

- **Given** two successful results have equal activity observations
- **When** any other `ProviderQuota`, `UsageLine`, or `UsageDetail` field changes
- **Then** Smart refresh classifies the result as unchanged
- **And** labels, units, total allowances, reset dates, detail ordering, detail text unrelated to credits, line ordering, and line presentation do not enter fast mode
- **And** localized text changes cannot affect the activity comparison
- **And** Core does not fall back to comparing the rendered quota model when an observation is present.

### AC5: Unknown and absent observations are conservative

- **Given** a successful result has no activity observation, an unknown availability state, or no metrics
- **When** Smart refresh compares it with its previous successful result
- **Then** absence alone does not masquerade as usage or availability activity
- **And** `unknown` becoming `available` or `unavailable`, or the reverse, establishes the new known state without entering fast mode
- **And** a later transition between `available` and `unavailable` does enter fast mode
- **And** the successful result can still establish or update the baseline used by later checks.

### AC6: Policy decisions expose safe diagnostic reasons

- **Given** the policy records a successful result
- **When** it returns its decision
- **Then** the decision reports baseline, unchanged, or changed together with the resulting cadence
- **And** a changed decision reports a set containing only `usage`, `credits`, and/or `availability`
- **And** diagnostics and logs may record those reason categories but never metric values or provider payloads
- **And** scheduling behavior does not depend on log output.

### AC7: Existing cadence and failure rules remain intact

- **Given** activity comparison returns baseline, unchanged, or changed
- **When** the Smart state machine updates
- **Then** the first observation establishes a slow baseline, a changed observation enters fast mode, and exactly three consecutive unchanged fast checks return the provider to slow mode as defined by (core 08 AC4, core 08 AC5, core 08 AC6)
- **And** a changed observation while fast resets the unchanged counter
- **And** fetch and proactive-refresh failures preserve the last successful baseline, return the provider to slow mode, and do not count as availability changes or unchanged checks (core 08 AC10)
- **And** Regular mode and providers without automatic refresh enabled do not create or advance Smart scheduling state.

### AC8: Current providers map only their semantic signals

- **Given** each current provider maps a successful response
- **When** its activity observation is inspected
- **Then** z.ai and Claude Code expose their current consumption values without reset times or limits
- **And** OpenAI Codex exposes current window consumption plus credit balance or unlimited-credit state
- **And** DeepSeek exposes current balance values as credits plus its upstream `is_available` state
- **And** Cursor exposes current included usage, on-demand spend, spend-limit usage, and available bonus credits without billing-cycle dates or configured limits
- **And** each provider owns its stable metric IDs and mapping without knowledge of any other provider.

### AC9: Numeric normalization avoids noise without hiding visible activity

- **Given** an upstream provider reports numeric usage or credits
- **When** the provider creates its activity observation
- **Then** it uses the same meaningful precision represented by its quota mapping rather than a localized display string
- **And** equivalent numeric values compare equally regardless of response formatting such as `10`, `10.0`, or `"10.00"`
- **And** a change large enough to alter the provider's represented usage or credit value is classified as changed
- **And** Core does not contain provider-specific tolerances or rounding rules.

### AC10: Detection and scheduling are covered end to end

- **Given** table-driven policy fixtures, provider mapping fixtures, an injected sleeper, and provider spies
- **When** the Core, provider, and App tests run
- **Then** they cover every included and excluded field from AC1–AC5, multi-reason changes, metric reordering, metric addition and removal, unknown availability, and provider isolation
- **And** they prove a semantic activity change schedules the fast interval while a presentation-only change schedules the slow interval or advances the existing fast-mode unchanged counter
- **And** they prove three unchanged semantic observations exit fast mode and failures do not become availability transitions
- **And** tests perform no network request, Keychain mutation, child-process spawn, or wall-clock sleep
- **And** all existing provider and automatic-refresh suites continue to pass.

### AC11: Slow and fast sliders offer finer interval choices

- **Given** the existing slow range of one through 60 minutes and fast range of 10 through 60 seconds
- **When** the user adjusts automatic-refresh intervals
- **Then** the slow slider offers every whole minute from one through 60 minutes
- **And** the fast slider offers every five-second value from 10 through 60 seconds
- **And** Regular mode shows the slow slider and uses its selected value for every opted-in provider
- **And** Smart mode shows both sliders and uses the slow value outside fast mode and the fast value while activity is detected
- **And** the defaults remain five minutes for slow refresh and 30 seconds for fast refresh
- **And** every slider stop displays a localized duration and exposes that value to assistive technology
- **And** every supported value persists across relaunch and reschedules eligible providers without overlapping work
- **And** stored values outside the supported ranges or increments resolve to the existing defaults as defined by (core 08 AC13, core 08 AC15).

## Plan

1. Add a small Core value model for Smart activity observations. Use stable metric IDs, a `usage`/`credits` kind, canonical numeric or discrete values, and optional three-state availability. Keep it independent of display labels and provider IDs.
2. Attach the observation to successful `ProviderQuota` values. Permit an absent observation for compatibility, but treat it conservatively rather than deriving activity from `UsageLine`.
3. Replace `UsageSnapshot` in `SmartRefreshPolicy` with a canonical activity comparison. Sort metrics by stable ID, reject duplicate IDs in debug builds, and compare reason categories separately so one result can report more than one cause.
4. Return a structured policy decision containing the resulting cadence and baseline/unchanged/changed classification. Allow App diagnostics to log only the provider ID and reason categories.
5. Map observations inside each provider from its decoded upstream model. Normalize values at that boundary and keep reset dates, configured limits, units, localized labels, and other presentation fields out of the observation.
6. Feed the structured decision through the existing `QuotaViewModel` scheduling path without changing interval selection, provider isolation, opt-in gates, or failure handling.
7. Expand the supported slow choices to every whole minute from one through 60 and the fast choices to five-second steps from 10 through 60. Keep the existing ranges, defaults, mode visibility, persistence keys, and completion-driven rescheduling behavior.
8. Expand Core tests with a table of semantic and non-semantic mutations. Add provider fixture tests for exact observation mapping, interval-option and persistence tests, and App tests for the resulting slow/fast schedule.
9. Run the full validation gate from the `writing-code` skill only after this spec is reviewed and implementation is explicitly approved.

## Risks

- The activity observation duplicates a small amount of data already used to render quota lines. That duplication is intentional: presentation fields are not a reliable contract for scheduling behavior.
- An omitted or incomplete provider observation can make Smart mode miss activity. Focused mapping tests for every production provider mitigate this, and future providers must test their observation alongside quota mapping.
- Stable metric IDs become scheduling compatibility keys. Providers must keep them nonlocalized and stable when display labels change.
- Provider-owned normalization may miss changes below the precision that provider exposes. This is preferable to fast-mode churn from insignificant floating-point or formatting noise.
- Treating `unknown`-to-known availability as baseline establishment avoids fast refresh on newly discovered capability, but it delays rapid follow-up until a real known-state transition or metric change occurs.
- Credit balances can decrease during active use and increase after a purchase or grant. Both are real credit changes and intentionally activate fast mode.
- More slider stops improve control but make keyboard and pointer traversal longer. Visible values, discrete stepping, and accessibility announcements must keep the selected interval clear.

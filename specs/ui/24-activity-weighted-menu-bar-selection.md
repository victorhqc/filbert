## Objective

Keep Automatic menu-bar selection focused on providers with recent meaningful activity through a decaying score while making the selected provider glyph and fast-refresh badge legible at standard menu-bar size.

## Context

- `Sources/App/MenuBarProviderSelector.swift` — currently gives fast mode absolute priority and otherwise selects the latest `lastUpdated`, allowing an unchanged background refresh to displace a recently used provider.
- New `Sources/App/MenuBarProviderActivityPolicy.swift` — owns provider-neutral runtime activity baselines, score awards, decay, caps, reset behavior, and deterministic clock-based resolution.
- `Sources/App/QuotaViewModel.swift`, `Sources/App/QuotaViewModel+Lifecycle.swift`, and `Sources/App/QuotaViewModel+Results.swift` — route successful observations and fast-mode transitions into the score policy and expose the observable time needed to expire activity without fetching quota.
- `Sources/Core/ProviderProtocol.swift` — already exposes canonical provider-owned usage and credit metrics through `ProviderActivityObservation` (core 09).
- `Sources/App/MenuBarProviderPresentation.swift` and `Sources/App/MenuBarStatusIcon.swift` — currently stack a 7-point bolt above a 9-point provider glyph; they will render a larger glyph with an overlapping top-right bolt badge in the existing leading bitmap.
- `Sources/App/AppearanceSettingsView.swift` and `Sources/App/Resources/Localizable.xcstrings` — update the Automatic explanation to describe recent activity rather than latest refresh time.
- `Tests/AppTests/MenuBarProviderSelectorTests.swift`, `Tests/AppTests/MenuBarProviderSelectionViewModelTests.swift`, `Tests/AppTests/MenuBarProviderPresentationTests.swift`, and `Tests/AppTests/MenuBarStatusIconTests.swift` — cover scoring, expiration, selection, and bitmap geometry without real time or external work.
- This replaces fast-first and latest-update priority from (ui 23 AC5, ui 23 AC6, ui 23 AC7, ui 23 AC9) while retaining its eligibility, manual-mode, fallback, presentation, and accessibility rules.
- This revises the vertically stacked identity column from (ui 23 AC11, ui 23 AC12) without changing the single leading bitmap constraint established by (ui 10, ui 12, ui 14).

## Acceptance Criteria

### AC1: Automatic selection uses an activity score

- **Given** Automatic is on and one or more displayable loaded providers satisfy the candidate rules from (ui 23 AC4)
- **When** the menu-bar provider is selected
- **Then** the eligible provider with the greatest effective activity score is selected
- **And** `ProviderQuota.lastUpdated`, dictionary iteration order, provider ID, and provider type do not award score or outrank a greater score
- **And** an unchanged background refresh cannot displace a provider with a positive score
- **And** the selector remains pure and receives already-resolved scores rather than reading a clock, starting work, or mutating provider state.

### AC2: Meaningful consumption awards points

- **Given** a provider has an established activity-observation baseline
- **When** a later successful result contains at least one numeric `usage` metric whose value increased or one numeric `credits` metric whose value decreased
- **Then** that provider receives 10 activity points once for the successful result
- **And** the award is 10 points whether one or several qualifying metrics changed so providers with more reported windows do not receive an automatic advantage
- **And** the award does not scale with raw magnitude because provider metrics use incomparable units such as percentages, currency, spend, and credits
- **And** equal numeric values, increased credit balances, decreased usage values caused by window resets, availability-only changes, discrete-value changes, metric reordering, and presentation-only changes award no consumption points.

### AC3: Baselines are conservative and provider-neutral

- **Given** the activity policy has no previous successful observation for a provider
- **When** it records the provider's first successful observation
- **Then** it establishes a baseline without awarding consumption points
- **And** absent observations, empty observations, absent metrics, and numeric metrics added to or removed from an observation do not infer consumption
- **And** later comparisons match metrics by stable ID and kind rather than array position
- **And** the policy contains no provider-ID, provider-type, display-label, unit, or localized-text branch.

### AC4: Entering fast mode awards a boost

- **Given** a provider is not currently in Smart fast mode
- **When** its observable fast-refresh state changes to active
- **Then** that provider receives a 30-point activity boost
- **And** remaining in fast mode does not repeatedly award the boost
- **And** leaving fast mode awards and removes no points
- **And** a successful result that both qualifies under AC2 and causes entry into fast mode receives both awards
- **And** fast mode is an input event rather than an absolute selector priority, so all eligible providers continue to compete by effective score.

### AC5: Scores are capped and decay to equilibrium

- **Given** a provider has earned activity points
- **When** its effective score is resolved at a supplied date
- **Then** the score is capped at 60 points and decays linearly by one point per minute elapsed since its last score update
- **And** decay never produces a negative score
- **And** awarding points first resolves the provider's decayed score at the event date, adds the award, applies the cap, and stores the new score and date
- **And** a score at zero is removed from active score state
- **And** when all eligible providers have reached zero, Automatic selection returns to saved provider order rather than latest refresh time.

### AC6: Ties and fallbacks remain deterministic

- **Given** two or more eligible candidates have equal effective scores
- **When** the selector resolves the tie
- **Then** the earliest candidate in `configuredProviderIds` wins
- **And** a malformed unlisted candidate sorts after listed candidates and provider ID ascending is the final defensive tie-breaker
- **And** when no provider satisfies the existing displayable-candidate rules, selection falls back to `configuredProviderIds.first`
- **And** an empty configured list selects no provider and keeps the Filbert fallback icon as defined by (ui 23 AC7, ui 23 AC8).

### AC7: Decay updates selection without quota work

- **Given** Automatic is on and at least one provider has a positive score
- **When** elapsed time can change the winning provider by exhausting the current winning score
- **Then** the view model schedules one cancellable wake-up for the earliest relevant score-expiration date
- **And** the wake-up updates observable selection time and recomputes scores from absolute dates
- **And** it starts no quota fetch, Keychain read, provider mutation, or repeating polling loop
- **And** a new score event, eligibility change, selection-mode change, sleep, or wake cancels and recalculates the pending expiration
- **And** clock jumps and time spent asleep apply the full elapsed decay rather than counting timer ticks.

### AC8: Score lifecycle does not leak across unrelated state

- **Given** provider or app state changes
- **When** a provider is disabled, unconfigured, removed from the registry, or reset for a new configuration lifecycle
- **Then** its activity baseline and score are removed
- **And** a refresh failure awards no points and preserves the existing score only until normal time decay removes it
- **And** switching to manual mode preserves no selection side effect and continues to select `configuredProviderIds.first`
- **And** scores and baselines remain runtime-only, are not written to `UserDefaults` or the Keychain, and restart at equilibrium after relaunch
- **And** provider order, automatic-selection preference, automatic-refresh preference, Smart scheduling state, and Vintage Mac preference remain independent.

### AC9: The motivating sequence remains stable

- **Given** provider 3 earns a fast-entry boost and becomes the Automatic menu-bar provider
- **When** provider 2 and then provider 4 complete unchanged background refreshes while provider 3 enters and later leaves fast mode
- **Then** neither background refresh awards points
- **And** provider 3 remains selected while its score is greater than zero even after leaving fast mode
- **And** provider 4 can replace it only by earning a greater score, by provider 3 becoming ineligible, or after scores return to equilibrium and saved order selects provider 4
- **And** the selected provider is not sticky beyond the score and eligibility rules.

### AC10: Settings explains the effective policy

- **Given** at least one provider is configured
- **When** the Provider order card renders
- **Then** localized supporting text explains that Automatic favors recently active providers and returns to saved order as activity fades
- **And** it does not claim that the most recently updated provider wins
- **And** the existing localized current-selection text updates with the effective provider
- **And** VoiceOver communicates the same behavior, toggle state, and current provider as required by (ui 23 AC10).

### AC11: The provider glyph uses the full identity area

- **Given** the selected provider resolves to a percentage or balance presentation
- **When** the leading menu-bar bitmap renders
- **Then** the provider glyph is aspect-fit in a 12-by-12-point area within a 14-by-14-point identity canvas
- **And** the glyph remains centered when fast mode is inactive
- **And** the identity canvas remains beside the existing ring or Vintage Mac face in the same compact, unboxed, leading bitmap followed by text
- **And** template rendering, the neutral missing-asset fallback, provider-neutral glyph resolution, same-render provider identity, and VoiceOver hiding remain governed by (ui 23 AC11).

### AC12: Fast mode uses an overlapping corner badge

- **Given** the selected provider is currently in Smart fast mode
- **When** its identity canvas renders
- **Then** a 7-by-7-point monochrome `bolt.fill` badge overlaps the provider glyph at the top-right corner instead of stacking above it
- **And** a small transparent clearance around the bolt separates it from the glyph so both template shapes remain legible without relying on color or a persistent box
- **And** the badge remains inside the 14-by-14-point identity canvas and does not increase its height or width
- **And** selected-fast, selected-non-fast, unselected-fast, fallback, and localized accessibility behavior remain governed by (ui 23 AC12)
- **And** the ring, balance text, Vintage Mac face, percentage text, and Filbert fallback otherwise remain unchanged.

### AC13: Activity selection is covered by deterministic tests

- **Given** pure policy inputs, injected dates, an injected expiration sleeper, and isolated view-model state
- **When** the activity and selection tests run
- **Then** they cover baseline creation; unchanged values; usage increases; usage decreases; credit decreases; credit increases; multiple qualifying metrics receiving one award; fast entry; repeated fast state; fast exit; combined awards; the 60-point cap; partial decay; exact zero; long elapsed time; and clock jumps
- **And** they cover unequal scores, equal-score saved-order ties, malformed-order defensive ties, unchanged refreshes, candidate ineligibility, failure preservation, provider reset, manual mode, relaunch equilibrium, and the complete sequence from AC9
- **And** expiration tests prove cancellation and rescheduling without a wall-clock wait
- **And** no test performs a network request, Keychain mutation, child-process spawn, or real-time sleep
- **And** existing provider ordering, Smart refresh, and menu-bar selection tests continue to pass.

### AC14: Badge geometry is covered by focused tests

- **Given** provider glyphs, missing assets, percentage and balance states, Vintage Mac mode, fast state, and fallback state
- **When** menu-bar presentation tests run
- **Then** they verify the 14-by-14-point identity canvas, 12-by-12-point glyph area, top-right 7-by-7-point bolt bounds, overlap rather than vertical stacking, transparent separation, unchanged composite height, and template rendering
- **And** snapshot-independent geometry tests prove the fast and non-fast identity canvases have equal size
- **And** presentation tests retain coverage for provider changes, neutral glyph fallback, no provider glyph or bolt in the Filbert fallback, and `Fast refresh active` accessibility output.

## Plan

Add a pure App-layer activity policy with per-provider canonical observation baselines and score anchors. Compare only matched numeric metrics: rising usage and falling credits produce one 10-point consumption event per successful result. Feed false-to-true fast-state transitions into the same policy as 30-point events. Resolve decay from an injected date at one point per minute, cap scores at 60, and keep all state in memory.

Change the selector to rank eligible candidates by effective score, saved order, and provider ID, removing `lastUpdated` and categorical fast priority from selection. Route every accepted successful result through the activity policy independently of refresh origin or Smart opt-in. Clear provider activity state with the existing lifecycle invalidation paths. Use a cancellable, injected one-shot sleeper only for the next selection-relevant score expiration and recompute from absolute time after wake.

Replace the vertical identity renderer with a fixed 14-point canvas. Draw the provider glyph in a centered 12-point area, clear a small separation shape at the top-right, and draw a 7-point bolt over that corner when the selected provider is fast. Preserve the single template bitmap passed to `MenuBarExtra`, the adjacent status visual, and the existing accessibility label. Update localized Automatic copy and add focused policy, selector, view-model, renderer, and accessibility tests before running the repository validation gate after review.

## Risks

- The constants determine how long recent activity dominates saved order: a lone fast-entry plus consumption event lasts 40 minutes, while sustained observations can hold the 60-minute cap. They are intentionally centralized in the pure policy so later tuning is small and testable.
- Raw metric magnitudes cannot be compared fairly across providers. A fixed award per successful observation avoids unit bias, but a one-point and a large consumption change receive the same award.
- Credit replenishment and usage-window resets deliberately award no consumption points, but either can still cause Smart refresh to enter fast mode under its existing change classification and therefore receive the fast-entry boost.
- Runtime-only scores mean relaunch returns Automatic selection to saved order until new activity is observed. Persisting behavioral history would add migration, privacy, and stale-state costs that this follow-up avoids.
- A one-shot expiration task adds lifecycle work. Absolute-date resolution, cancellation, and injected timing tests are necessary to avoid timer drift, duplicate tasks, and incorrect decay after sleep.
- Overlaying two monochrome shapes can reduce recognition for dense provider glyphs. The transparent clearance, fixed geometry tests, and 14-point size mitigate this, but the result still needs visual review on light and dark menu bars at standard and increased display scaling.

## Objective

Add provider-by-provider opt-in automatic refresh with a shared configurable Smart mode that temporarily polls an active provider faster when its usage changes.

## Context

- `Sources/Core/AutoRefreshPreferences.swift` — new provider-ID-neutral `UserDefaults` storage for per-provider opt-in, the shared refresh mode, and shared interval choices.
- `Sources/Core/SmartRefreshPolicy.swift` — new pure state machine that compares successful usage snapshots and chooses each provider's next cadence independently.
- `Sources/Core/ProviderProtocol.swift` — supplies the provider-neutral quota fields from which a stable usage snapshot is derived (core 01).
- `Sources/Core/ProviderRegistry.swift` — remains the only route to provider fetch and proactive-refresh operations, preserving the enablement boundary from (ui 17 AC6, ui 17 AC10).
- `Sources/App/QuotaViewModel.swift`, `Sources/App/QuotaViewModel+Lifecycle.swift`, and `Sources/App/QuotaViewModel+Results.swift` — replace the unconditional five-minute loops with opt-in, completion-driven scheduling and feed successful results into the Smart policy.
- `Sources/App/QuotaView.swift` — shows a compact per-provider status in the popover while that provider is using the fast Smart cadence.
- `Sources/App/MenuBarStatusIcon.swift` — remains unchanged by refresh cadence; fast-mode status is not added to the menu-bar icon.
- `Sources/App/RefreshSettingsView.swift` and `Sources/App/SettingsView.swift` — add a Refresh tab with per-provider opt-in controls, a Regular/Smart mode picker, interval controls, and an explanation of the current behavior.
- `Sources/App/Resources/Localizable.xcstrings` — localizes the new labels, interval descriptions, paused states, Claude Code quota warning, fast-mode status, help text, and accessibility text.
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` — allows scheduled proactive refresh at the minimum supported fast cadence while retaining process coalescing and bounded execution (providers 03, providers 06).
- `Tests/CoreTests/AutoRefreshPreferencesTests.swift` and `Tests/CoreTests/SmartRefreshPolicyTests.swift` — cover persistence, defaults, snapshot comparison, and every policy transition without real timers.
- `Tests/AppTests/AutoRefreshViewModelTests.swift` — covers scheduling, provider isolation, lifecycle cancellation, and Settings mutations with an injected clock and provider spies.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherTests.swift` — verifies Claude Code's proactive refresh can run at the supported fast cadence without parallel child processes.
- This replaces the unconditional five-minute periodic refresh inherited from (ui 02 AC7) while preserving quiet result presentation from (ui 07).

## Acceptance Criteria

### AC1: Automatic refresh is a separate per-provider opt-in

- **Given** any registered provider with no saved automatic-refresh preference
- **When** Filbert resolves its automatic-refresh state
- **Then** automatic refresh is off for that provider, including on an upgraded installation where the provider is already enabled and configured
- **And** enabling one provider's automatic refresh persists only that provider ID in `UserDefaults`
- **And** the choice survives relaunches and is independent of provider enablement, credentials, helper installation, ordering, and collapse state
- **And** adding a provider requires no provider-ID branch in Core, App, or Settings.

### AC2: Opt-in controls periodic work, not initial display or manual refresh

- **Given** a provider is enabled and configured but automatic refresh is off
- **When** the app launches, the provider is newly enabled, or the user clicks Refresh
- **Then** the existing initial quota load and explicit manual refresh still run so the app can display current data
- **And** no periodic refresh task remains scheduled after that work completes
- **And** a disabled or unconfigured provider performs no initial, manual, or scheduled provider work, preserving (ui 17 AC6)
- **And** turning automatic refresh off never disables the provider, removes its saved setup, or hides its last-known quota.

### AC3: Regular mode uses the shared slow interval

- **Given** a configured provider has automatic refresh on and the shared mode is Regular
- **When** its initial or most recent refresh finishes
- **Then** its next automatic refresh starts after the shared slow interval
- **And** the default slow interval is five minutes
- **And** every successful Regular refresh schedules another slow interval regardless of whether usage changed
- **And** separate providers have separate tasks, so one slow or failed provider never delays another.

### AC4: Smart mode starts slow and establishes a baseline

- **Given** a configured provider has automatic refresh on and the shared mode is Smart
- **When** Smart mode has no previous successful usage snapshot for that provider
- **Then** the first successful result becomes its baseline and the provider remains in slow mode
- **And** switching from Regular to Smart uses the provider's current successful quota as the baseline when one exists
- **And** launching or re-enabling automatic refresh does not treat the absence of an earlier snapshot as a usage change
- **And** Smart mode and its no-change counter are runtime scheduling state and reset to slow on app relaunch.

### AC5: A usage change enters and sustains fast mode

- **Given** an automatically refreshed provider in Smart mode has a previous successful usage snapshot
- **When** a later successful check contains different meaningful usage data
- **Then** that provider enters fast mode, resets its consecutive no-change count to zero, and schedules its next check after the shared fast interval
- **And** every further changed result keeps that provider in fast mode and resets the count to zero
- **And** the default fast interval is 30 seconds
- **And** activity in one provider does not change any other provider's mode, counter, baseline, or next refresh date.

### AC6: Three unchanged fast checks return only that provider to slow mode

- **Given** a provider is in Smart fast mode
- **When** a successful check has the same meaningful usage snapshot as the previous successful check
- **Then** its consecutive no-change count increments by one
- **And** the first and second consecutive unchanged results schedule another fast check
- **And** the third consecutive unchanged result immediately moves that provider to slow mode, clears the counter, and schedules the next check after the slow interval
- **And** any changed result before the third unchanged result resets the count to zero
- **And** an unchanged result received while already slow leaves the provider slow.

### AC7: Snapshot comparison ignores refresh bookkeeping

- **Given** two successful `ProviderQuota` values for the same provider
- **When** Smart mode compares them
- **Then** it compares a canonical snapshot of each `UsageLine`'s `label`, `used`, `total`, `percentage`, `unit`, `resetDate`, and sorted `UsageDetail` label/value pairs
- **And** line ordering and detail ordering alone do not count as usage changes
- **And** `providerName`, formatted `headline`, `lastUpdated`, `error`, `isStale`, and peak/off-peak presentation metadata do not participate
- **And** a percentage, balance, spend, total, reset date, line addition/removal, unit, or detail value change does participate
- **And** the comparison lives in Core and requires no provider-specific comparison implementation.

### AC8: Claude Code automatic refresh updates its source cache

- **Given** Claude Code is enabled, configured, and opted into automatic refresh
- **When** a scheduled check starts
- **Then** the view model calls `registry.proactiveRefresh(for:)` before `registry.fetchQuota(for:)`, using the same provider-neutral capability route as manual refresh (providers 03 AC3, providers 03 AC7)
- **And** Claude Code runs its bounded, window-less `/usage` refresh and then reads the resulting cache
- **And** providers that do not conform to `ProactiveRefreshable` fall through to their normal quota fetch without error or App-layer branching
- **And** the Claude Code refresher's completed-attempt debounce is reduced from 60 seconds to 10 seconds, superseding (providers 03 AC4), so every allowed fast-interval choice can perform real work
- **And** the existing in-flight task coalescing, timeout, process cleanup, cache safety, and quiet execution guarantees remain unchanged (providers 03 AC2, providers 03 AC4, providers 03 AC5, providers 03 AC6).

### AC9: Claude Code opt-in discloses possible quota use

- **Given** the user views the Claude Code row in Refresh Settings
- **When** its automatic-refresh control renders, before or after opt-in
- **Then** an inline disclosure says Filbert runs `claude -p "/usage"` in the background and these checks may use some of the user's Claude Code quota
- **And** the disclosure is visible before opt-in and is not hidden in a tooltip
- **And** it warns that shorter Smart intervals can increase the number of checks
- **And** the command and quota consequence are included in the row's accessibility description.

### AC10: Failed checks do not masquerade as unchanged usage

- **Given** a scheduled proactive refresh or quota fetch fails
- **When** the Smart policy receives the failure
- **Then** it does not replace the last successful snapshot or increment the no-change counter
- **And** it returns that provider to slow mode and schedules no fast retry
- **And** the quiet-refresh UI retains last-known data and exposes the failure as specified by (ui 07 AC6, ui 07 AC7)
- **And** provider handling of `429`, `Retry-After`, and exponential backoff remains authoritative; Smart scheduling never bypasses or shortens it
- **And** the next successful result is compared with the last successful snapshot.

### AC11: Shared settings have bounded, understandable controls

- **Given** the user opens the Refresh Settings tab
- **When** the shared controls render
- **Then** a segmented picker offers `Regular` and `Smart`
- **And** Regular explains that every opted-in provider uses the slow interval
- **And** Smart explains, using the selected values, that a provider starts slow, changes move it to fast checks, and three unchanged checks return it to slow
- **And** the slow-interval slider offers discrete values from one minute through one hour, including the five-minute default
- **And** the fast-interval slider is visible only for Smart mode and offers discrete values from 10 seconds through one minute, including the 30-second default
- **And** each slider shows its selected value as localized text rather than requiring the user to infer it from position.

### AC12: Provider opt-in and shared Smart settings are clearly separated

- **Given** the Refresh Settings tab lists all registered providers
- **When** the user reviews the list
- **Then** each row shows the provider glyph, display name, and an `Automatic refresh` toggle
- **And** the page explains that provider toggles choose *which* providers refresh while the shared mode and intervals choose *how often*
- **And** a disabled provider's saved automatic-refresh choice is retained but visibly marked paused, and no scheduler starts until provider enablement allows work
- **And** an enabled but unconfigured provider may retain its choice but is visibly marked as waiting for setup
- **And** no status check for a disabled provider crosses the no-work boundary from (ui 17 AC6).

### AC13: Preference changes take effect without overlapping work

- **Given** automatic refresh tasks may be sleeping or fetching
- **When** the user changes a provider opt-in, shared mode, or interval
- **Then** sleeping tasks are rescheduled with the new policy
- **And** an in-flight fetch is allowed to finish unless provider disablement requires cancellation
- **And** no provider has more than one Filbert-initiated refresh in flight
- **And** intervals are measured from completion to the next start, so a slow request cannot create a catch-up burst
- **And** waking the Mac after missed intervals causes at most one refresh per eligible provider, never one refresh per missed tick
- **And** disabling a provider or its automatic refresh cancels its pending sleep and rejects any late result from scheduling more work (ui 17 AC5).

### AC14: Manual checks participate only when Smart automatic refresh is active

- **Given** a provider is opted into Smart automatic refresh
- **When** an initial, manual, or scheduled check returns a successful quota
- **Then** the result updates that provider's baseline and Smart transition state using AC4–AC7
- **And** a manual change can enter fast mode and a manual unchanged check can contribute to the three-check exit
- **And** when automatic refresh is off or the shared mode is Regular, successful checks do not create or advance Smart fast-mode scheduling state
- **And** manual refresh never starts a periodic task for a provider whose automatic refresh toggle is off.

### AC15: Refresh settings are persistent, localized, and accessible

- **Given** the app relaunches or runs with assistive technology
- **When** the Refresh Settings tab renders
- **Then** provider opt-ins, shared mode, and both intervals restore from `UserDefaults`
- **And** invalid or obsolete stored interval values resolve to the documented defaults instead of escaping the supported ranges
- **And** every new user-facing string is in the App String Catalog and resolved through `String(localized:)`
- **And** toggles, picker options, sliders, paused/setup states, current values, and Smart behavior have descriptive accessibility labels, values, and help
- **And** mode and provider state are never communicated by color alone.

### AC16: Scheduling and policy are covered without real waits

- **Given** isolated `UserDefaults`, a controllable test clock/sleeper, and provider spies
- **When** Core, App, and provider tests run
- **Then** they cover default-off migration, per-provider persistence, Regular cadence, Smart baseline creation, change-to-fast, changed-result reset, exactly three no-change results, failure-to-slow, interval edits, mode edits, relaunch reset, sleep/wake behavior, and late-result rejection
- **And** they prove Claude Code proactive refresh runs automatically while non-proactive providers use only `fetchQuota`
- **And** they prove one provider's result never changes another provider's schedule
- **And** a Settings test verifies the Claude Code quota disclosure is visible before automatic refresh is enabled and contains the `claude -p "/usage"` command
- **And** tests perform no real network request, Keychain mutation, child-process spawn, or wall-clock sleep
- **And** all existing provider suites continue to pass without adding refresh-policy logic to individual provider modules.

### AC17: The popover identifies providers currently refreshing fast

- **Given** a provider is currently in Smart fast mode
- **When** the menu-bar popover is open
- **Then** that provider's header shows a compact lightning-bolt icon and the localized label `Fast refresh active`
- **And** the status remains visible when that provider's quota details are collapsed
- **And** the icon and label identify the affected provider rather than implying that every provider is in fast mode
- **And** the status disappears as soon as that provider returns to slow mode, automatic refresh is turned off, the shared mode changes to Regular, or the provider becomes ineligible for automatic work
- **And** no fast-mode badge, lightning icon, or other cadence state is added to the menu-bar top-bar icon
- **And** assistive technology announces the status as part of that provider's header, without relying on the icon or color alone
- **And** App tests verify the status visibility for fast and non-fast provider states, including two providers in different cadences.

## Plan

1. Add `AutoRefreshPreferences` in Core. Store a provider-ID Boolean map plus one shared mode (`regular` or `smart`), slow interval, and fast interval in `UserDefaults`. Missing provider values resolve to `false`; missing or invalid shared values resolve to Regular, five minutes, and 30 seconds.
2. Add a pure `SmartRefreshPolicy` state machine in Core. Keep a runtime record per provider containing the last successful canonical usage snapshot, current slow/fast mode, and consecutive unchanged count. Expose events for successful quota, failure, provider reset, and global mode change.
3. Derive the canonical snapshot from existing provider-neutral quota lines. Treat lines and details as canonical multisets so response ordering does not cause false activity; exclude timestamps and presentation-only fields listed in AC7.
4. Replace `QuotaViewModel`'s fixed `refreshInterval` loop with one cancellable completion-driven task per eligible opted-in provider. Inject the sleep/clock boundary for deterministic tests. Route both scheduled and manual work through one result pipeline so Smart state sees successful checks consistently, and expose each provider's current cadence as observable read-only presentation state.
5. Add an automatic refresh entry point that attempts `proactiveRefresh(for:)`, catches only `.notSupported` as capability absence, and then runs the normal provider-scoped fetch. Keep manual presentation and automatic presentation on the quiet-refresh path from (ui 07).
6. Reconcile provider enablement, setup, automatic-refresh opt-in, and scheduling in lifecycle helpers. A task exists only when all gates permit it. Use lifecycle revisions and task cancellation to prevent late results from reviving stopped schedules.
7. Reduce Claude Code's completed-attempt debounce to 10 seconds while retaining its single in-flight task and process timeout/cleanup behavior. Do not add scheduling knowledge or Smart policy to the provider module.
8. Add a Refresh Settings tab. Present provider toggles separately from one shared policy card, use a segmented mode picker, and use stepped sliders for slow and fast choices. Render dynamic explanatory copy with the selected durations and the fixed three-unchanged transition. Show a persistent inline warning on the Claude Code row that names `claude -p "/usage"`, says checks may use Claude Code quota, and explains that shorter Smart intervals cause more checks.
9. Add a compact lightning-bolt and `Fast refresh active` label to each fast provider's popover header, including its collapsed state. Keep `MenuBarStatusIcon` independent of cadence.
10. Add localized and accessible copy, then cover preference, policy, lifecycle, popover status, UI mutation, provider capability routing, and Claude debounce behavior with isolated stores, spies, and a controllable clock.
11. Run the full validation gate from the `writing-code` skill only after this spec is reviewed and implementation is explicitly approved.

## Risks

- Every existing provider currently receives a five-minute loop once configured. Defaulting the new per-provider preference to off intentionally stops that background behavior after upgrade until the user opts in.
- Initial load remains automatic even when periodic refresh is off. This keeps the popover useful on launch, but it means the opt-in is a periodic-polling control rather than a global prohibition on all non-manual provider access.
- Claude Code Smart mode can launch `claude -p "/usage"` as often as every 10 seconds during sustained activity. Anthropic may count these checks against the user's Claude Code quota in addition to their local process and service cost; the persistent warning and default-off opt-in make that tradeoff explicit.
- A provider that rounds usage coarsely may remain slow until its displayed/shared values change. A provider that emits genuinely noisy numeric values may remain fast longer. The shared comparison deliberately uses the quota values providers already expose rather than provider-specific tolerances.
- Reset dates participate in comparison. A new quota window can therefore enter fast mode even when its percentage happens to match the old window; this is desirable because the underlying usage window changed.
- Falling back to slow after any failure favors provider safety over rapid recovery. The next successful slow check compares against the last successful baseline and can re-enter fast mode.
- Shared intervals are simpler to understand and prevent configuration sprawl, but they cannot accommodate a provider with a stricter minimum cadence. Provider rate limits and backoff remain authoritative, and a future capability may need to expose a provider-specific minimum without weakening provider orthogonality.
- The fast-mode label adds width to a provider header. It must remain legible without crowding the provider name or refresh controls, especially when the popover is narrow.

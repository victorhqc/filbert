## Objective

Let users keep the Mac awake for a chosen duration from Filbert's panel while making the control optional and the active state visible.

## Context

- `Sources/App/AppMain.swift` — owns the app-lifetime sleep-prevention controller and passes it to the panel, menu-bar label, and Settings window.
- `Sources/App/QuotaView.swift` — adds the keep-awake selector between the provider content and the existing Settings/version/Quit footer.
- `Sources/App/MenuBarStatusIcon.swift` — composites an active keep-awake mark into the normal status-ring presentation, building on (ui 10), while leaving the Vintage Mac presentation unchanged as allowed by (ui 12).
- `Sources/App/AppearanceSettingsView.swift` — adds the default-on setting that controls whether the feature appears in the panel.
- `Sources/App/Resources/Localizable.xcstrings` — stores the selector, countdown, error, setting, help, and accessibility strings.
- `Package.swift` — links the app target to macOS IOKit power-management APIs if Swift Package Manager does not infer the framework from the module import.
- The feature is local to the app layer. It does not change provider modules, provider refresh behavior, networking, or Keychain storage.
- macOS exposes process-scoped IOKit power assertions for this purpose. Filbert uses `IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleDisplaySleep` and releases the returned assertion with `IOPMAssertionRelease`; it does not launch a `caffeinate` subprocess.

## Acceptance Criteria

### AC1: The panel shows a keep-awake selector by default
- **Given** the user has not disabled the feature
- **When** the Filbert panel opens
- **Then** a full-width row labeled "Prevent Mac from sleeping for…" appears after the provider or empty-state content and before the Settings/version/Quit footer
- **And** a divider separates the row from the content above and another divider separates it from the footer below
- **And** the row remains available when no provider is configured

### AC2: The selector offers the requested durations
- **Given** the keep-awake row is visible
- **When** the user opens its selector
- **Then** it offers exactly 5 minutes, 10 minutes, 20 minutes, 30 minutes, 1 hour, 2 hours, and "Until turned off"
- **And** choosing any option starts sleep prevention immediately without closing Filbert or requiring system authorization

### AC3: An active timed session shows a live countdown
- **Given** the user chose a finite duration
- **When** sleep prevention is active
- **Then** the row reads "Mac won't sleep for <remaining time>" using a localized, monospaced countdown
- **And** durations below one hour use `m:ss`, while durations of one hour or more use `h:mm:ss`
- **And** the displayed value never becomes negative
- **And** the selector remains usable so the user can replace the current duration or choose "Turn Off"

### AC4: An indefinite session remains active until stopped
- **Given** the user chose "Until turned off"
- **When** sleep prevention is active
- **Then** the row reads "Mac won't sleep until turned off"
- **And** the selector offers "Turn Off"
- **And** choosing "Turn Off" immediately releases sleep prevention and restores the inactive row label

### AC5: Filbert owns one idle-display-sleep assertion
- **Given** no keep-awake session is active
- **When** the user chooses a duration
- **Then** Filbert creates one process-scoped `kIOPMAssertionTypePreventUserIdleDisplaySleep` assertion through IOKit with a human-readable reason containing "Filbert"
- **And** the assertion prevents idle display sleep and the resulting idle system sleep while leaving explicit Sleep commands, lid-close sleep, shutdown, and restart under macOS control
- **And** choosing a different duration reuses the active assertion and replaces its deadline rather than accumulating assertions
- **And** stopping, expiry, controller teardown, or loss of feature visibility releases any assertion Filbert owns
- **And** macOS also removes the process-scoped assertion if Filbert exits unexpectedly

### AC6: Timed sessions expire according to wall-clock time
- **Given** a finite keep-awake session is active
- **When** its deadline arrives
- **Then** Filbert releases the assertion, clears the active state, and restores the inactive row and menu-bar presentation
- **And** the deadline is based on an absolute `Date`, so time spent with the panel closed still counts
- **And** if the user explicitly sleeps the Mac and wakes it after the deadline, the first lifecycle or timer update ends the expired session immediately
- **And** an active session is not restored after Filbert quits and relaunches

### AC7: Assertion failures are safe and visible
- **Given** IOKit fails to create the power assertion
- **When** the user chooses a duration
- **Then** Filbert remains inactive, shows a localized error in the panel, and does not show an active menu-bar mark
- **And** the user can retry by selecting a duration again
- **And** the failure does not crash the app or affect provider data

### AC8: The normal menu-bar status indicates an active session
- **Given** sleep prevention is active and the Vintage Mac icon is disabled
- **When** the menu-bar label renders
- **Then** a small monochrome `sun.max.fill` awake mark is composited into the center of the normal usage ring without replacing the provider glyph, usage text, or fast-refresh mark from (ui 10, ui 24)
- **And** when no usage ring is available, the same awake mark is composited beside the provider or fallback glyph so the active state remains visible
- **And** the mark disappears on stop, expiry, or assertion failure
- **And** the combined accessibility label appends a localized "Mac sleep prevention active" status

### AC9: Vintage Mac mode is unchanged
- **Given** the Vintage Mac icon is enabled
- **When** sleep prevention starts or stops
- **Then** no keep-awake mark is added to the Vintage Mac bitmap or menu-bar text
- **And** the panel still shows and controls the active session normally
- **And** no existing Vintage Mac rendering or accessibility behavior from (ui 12) regresses

### AC10: Users can remove the feature from the panel
- **Given** the Settings window is open on the Appearance tab
- **When** it renders
- **Then** a "Show sleep prevention" toggle appears in a "Panel" card with a localized subtitle explaining that it shows a keep-awake timer in Filbert's panel
- **And** the toggle defaults to on for new and existing users and persists through UserDefaults
- **And** turning it off removes the panel row immediately, suppresses the menu-bar awake mark, and stops any active session so Filbert never holds a hidden assertion
- **And** turning it back on restores the inactive selector without restoring the prior session

### AC11: The lifecycle and duration rules are covered by tests
- **Given** an injected fake power-assertion client, clock, scheduler, and isolated UserDefaults suite
- **When** the App test suite runs
- **Then** it verifies every duration, finite countdown formatting, indefinite sessions, replacing a deadline, manual stop, expiry, wake-after-deadline reconciliation, creation failure, exactly-once release, default-on visibility, persisted visibility, and disabling during an active session
- **And** menu-bar presentation tests verify the awake-mark selection for ring and fallback states and its suppression for inactive and Vintage Mac states

### AC12: All new interface text is accessible and localized
- **Given** the panel, menu bar, or Settings is used with VoiceOver or a non-English locale
- **When** the new controls and state render
- **Then** every new user-facing string goes through `String(localized:)` and is recorded in `Localizable.xcstrings`
- **And** the selector has a localized accessibility label, value, and hint that distinguish inactive, timed, indefinite, and failed states

## Plan

1. [x] Add an app-layer `SleepPreventionController` observable to hold the visibility preference, selected deadline or indefinite state, remaining time, and last activation error. Inject small protocols for the clock, scheduler, and power assertion so lifecycle rules are deterministic in tests.
2. [x] Add an `IOKitPowerAssertionClient` that calls `IOPMAssertionCreateWithName` for `kIOPMAssertionTypePreventUserIdleDisplaySleep`, retains only the returned assertion ID, and releases that ID exactly once. Keep this macOS side effect behind the client boundary. Swift Package Manager inferred the framework from `import IOKit.pwr_mgt`, so `Package.swift` required no link setting.
3. [x] Create one controller in `AppMain` for the process lifetime and pass it explicitly to `QuotaView`, `MenuBarStatusIcon`, and `SettingsView`. Do not add keep-awake state to `QuotaViewModel`, because it is independent of providers and quota refresh.
4. [x] Add a one-second scheduler only while a finite session is active. Each tick derives remaining time from the stored absolute deadline rather than decrementing a counter. Stop the scheduler for inactive and indefinite states, and reconcile the deadline when the app becomes active after sleep.
5. [x] Add the panel `Menu` row with the seven durations and a conditional "Turn Off" action. Use one presentation formatter for the visible countdown and accessibility value.
6. [x] Extend the bitmap composition in `MenuBarStatusIcon` with a small awake-mark renderer. Overlay it on a normal ring when one exists, append it to fallback/identity imagery otherwise, and bypass it when Vintage Mac mode is active.
7. [x] Add the default-on "Show sleep prevention" UserDefaults preference and its Appearance-tab toggle. The controller handles disabling as a single operation that persists the preference, stops the timer, releases the assertion, and clears session state.
8. [x] Add focused App tests for the controller, formatting, preference, IOKit-client contract through a fake, and menu-bar visual selection. Validate manually on macOS by starting a five-minute session and checking the assertion with `pmset -g assertions`.

The user approved this spec before production implementation began.

## Risks

- A keep-awake session increases display-on time and battery use. The active row, menu-bar mark, countdown, and explicit stop action reduce the chance of leaving it enabled accidentally.
- IOKit assertion ownership is stateful. Replacing durations or disabling the feature must never leak or double-release an assertion; the injected client and lifecycle tests cover those transitions.
- A one-second countdown causes periodic SwiftUI updates while a finite session is active. It is bounded to the App controller and stops at expiry; provider state and network refreshes remain untouched.
- The ring center is small at menu-bar scale. The `sun.max.fill` mark must be checked at 1× and 2× backing scales; if it is not legible, the implementation should use the adjacent fallback placement without changing the active-state semantics.
- Assertions intentionally do not override explicit user actions such as closing the lid or choosing Sleep. Presenting the feature as idle sleep prevention avoids implying otherwise.

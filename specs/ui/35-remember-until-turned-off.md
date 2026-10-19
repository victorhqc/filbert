## Objective

Add an opt-in setting that restores a Keep Awake "Until turned off" session when Filbert launches again.

## Context

- Status: implemented 2026-10-19, not committed. Plan steps 1–7 are done. The manual check (step 8) and the native review of the new strings are open.
- Problem: a user keeps Keep Awake on "Until turned off" all the time. After a restart of the Mac, Filbert opens again with Keep Awake off, and the Mac sleeps. The user must select "Until turned off" again after each restart.
- Amends (ui 25 AC6). That AC says no session is restored after a relaunch. This spec makes one exception: an "Until turned off" session, when the new setting is on. Timed sessions are still never restored.
- `Sources/App/SleepPreventionController.swift` — `SleepPreventionPreferences` stores the "Show Keep Awake" value (ui 25 AC10). The new setting and the saved session go in the same place. `SleepPreventionController.init` restores the session.
- `Sources/App/AppearanceSettingsView.swift` — the Keep Awake card (ui 30 AC2) gets the new toggle under "Show Keep Awake".
- `Sources/App/AppMain.swift` — creates one controller for the app lifetime. No change is expected, because the controller restores itself in `init`.
- Nothing calls `stop()` when Filbert quits. macOS releases the process-scoped assertion when the process exits (ui 25 AC5). So the saved session stays as it was at quit.
- `Sources/App/Resources/Localizable.xcstrings` — the two new strings, in all catalog languages (ui 31), with "Keep Awake" and "Until turned off" as in `docs/localization-glossary.md`.
- The restore happens on any launch. To restore after a Mac restart, Filbert must also open at login (ui 26).

## Acceptance Criteria

### AC1: The setting is in the Keep Awake card, off by default

- **Given** the Settings window is open on the Appearance tab
- **When** the Keep Awake card renders
- **Then** a toggle "Remember “Until turned off”" shows under "Show Keep Awake"
- **And** its subtitle reads "After a restart, Filbert turns Keep Awake back on if it was set to Until turned off."
- **And** the toggle is off for new and existing users, and its value persists through `UserDefaults`.

### AC2: The setting needs Keep Awake to be visible

- **Given** "Show Keep Awake" is off
- **When** the Keep Awake card renders
- **Then** the "Remember" toggle is disabled and keeps its value
- **And** no session is restored at launch while "Show Keep Awake" is off.

### AC3: "Until turned off" is restored at launch

- **Given** the setting is on
- **And** Keep Awake was on "Until turned off" when Filbert quit, or when the Mac restarted
- **When** Filbert launches
- **Then** Keep Awake starts on "Until turned off" with no user action
- **And** the panel row reads "Until turned off" (ui 25 AC4) and the menu-bar mark shows (ui 25 AC8).

### AC4: "Turn Off" is remembered as off

- **Given** the setting is on and Keep Awake is on "Until turned off"
- **When** the user selects "Turn Off"
- **Then** the Mac can sleep again, and the setting stays on
- **And** on the next launch, Keep Awake stays off.

### AC5: Selecting "Until turned off" again makes it sticky again

- **Given** the setting is on and Keep Awake was turned off (AC4)
- **When** the user selects "Until turned off" again, and later Filbert launches
- **Then** Keep Awake starts on "Until turned off" (AC3).

### AC6: Timed durations are never restored

- **Given** the setting is on
- **When** the user selects a timed duration, for example 10 minutes, from an inactive state or from "Until turned off"
- **Then** the timed session works as before, and the Mac can sleep after its deadline (ui 25 AC6)
- **And** if Filbert launches again, before or after that deadline, Keep Awake is off.

### AC7: With the setting off, nothing is restored

- **Given** the setting is off
- **And** Keep Awake was on "Until turned off" when Filbert quit
- **When** Filbert launches
- **Then** Keep Awake is off, as in (ui 25 AC6).

### AC8: Turning on the setting during a session applies to that session

- **Given** the setting is off and Keep Awake is on "Until turned off"
- **When** the user turns on the setting, and later Filbert launches
- **Then** Keep Awake starts on "Until turned off".

### AC9: A failed restore is safe

- **Given** the setting is on and an "Until turned off" session is saved
- **When** Filbert launches and IOKit fails to create the assertion
- **Then** Keep Awake stays off and the panel shows the error from (ui 30 AC3)
- **And** the saved session is kept, so the next launch tries again
- **And** the app does not crash, and provider data is not affected.

### AC10: Tests cover the restore rules

- **Given** a fake power manager and an isolated `UserDefaults` suite
- **When** the App test suite runs
- **Then** it verifies AC1 to AC9 at the controller level: the default value, the restore, "Turn Off", a timed duration, the setting off, Keep Awake hidden, the setting turned on during a session, and a failed restore.

### AC11: New text is localized

- **Given** any catalog language
- **When** the Keep Awake card renders
- **Then** the toggle and subtitle use `String(displayLocalized:bundle:)` and have a translation in every catalog language
- **And** "Keep Awake" and "Until turned off" use the same words as the panel row in that language.

## Plan

1. [x] Add two keys to `SleepPreventionPreferences`: `sleep-prevention-remember-indefinite` (the setting, default `false`) and `sleep-prevention-indefinite-active` (the saved session, default `false`).
2. [x] In the controller, write the saved session at each change: `true` after `start(.untilTurnedOff)` creates its assertion, `false` after a timed `start` or after `stop()`. Always write it, also when the setting is off, so AC8 works. `setFeatureVisible(false)` calls `stop()`, so it also clears the saved session.
3. [x] In `init`, if the feature is visible, the setting is on, and the saved session is `true`, call `start(.untilTurnedOff)`. A failure leaves the saved session as it is (AC9). In all other cases, set the saved session to `false`, so an old value cannot come back later.
4. [x] Add `remembersUntilTurnedOff` and `setRemembersUntilTurnedOff(_:)` to the controller, as for `isFeatureVisible`.
5. [x] Add the toggle to the Keep Awake card, disabled when "Show Keep Awake" is off. It uses the default macOS checkbox style, as "Show Keep Awake" does.
6. [x] Add the two strings to `Localizable.xcstrings` for all catalog languages.
7. [x] Add controller tests for AC10, in `Tests/AppTests/SleepPreventionRestoreTests.swift`. The fakes in `SleepPreventionControllerTests.swift` are now internal, so both files use them.
8. [ ] Check manually: select "Until turned off", quit Filbert, open it again, and confirm the assertion with `pmset -g assertions`.

## Risks

- Keep Awake can now stay on across restarts without a user action. This uses more battery and keeps the display on. The setting is off by default, and the panel row and the menu-bar mark show the active state at launch.
- If Filbert crashes during a session, the saved session is still `true`, and the next launch restores it. This is correct: the user did not turn it off.
- A restore at launch happens before the user opens the panel. A failed restore (AC9) shows its error only when the panel opens.
- Translations for `ru`, `zh-Hans`, `pt-PT`, and `ja` still need the native review from (ui 31).

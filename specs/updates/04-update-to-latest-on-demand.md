## Objective

Make every update install the newest release in the feed, so a user several versions behind updates with one click and one restart.

## Context

- `packaging/Info.plist` — ships `SUAutomaticallyUpdate = YES`. A scheduled check downloads, extracts, and stages the update to install on quit. Filbert is a menu-bar app and seldom quits, so a staged update can wait for days.
- `.build/checkouts/Sparkle/Sparkle/SPUUpdater.m` — `checkForUpdatesWithDriver` resumes a waiting installer or a kept download and does not read the feed. Scheduled checks, `checkForUpdates`, and `checkForUpdateInformation` all go through this path. Sparkle 2.9.6 has no public API to cancel a staged installer.
- `.build/checkouts/Sparkle/Sparkle/SPUStandardUserDriver.m` — gentle scheduled reminders keep the session open with the first update found. They have the same stale-version problem.
- `checkForUpdateInformation` keeps no download or installer state. When nothing is staged, it and `checkForUpdates` read the feed every time.
- `Sources/App/UpdateCoordinator.swift` — becomes the gate that turns a scheduled check into an information-only check.
- `Sources/App/AboutSettingsView.swift` — loses the "Download updates automatically" toggle.
- `Sources/App/Resources/Localizable.xcstrings` — the toggle string and its translations go away.
- `docs/automatic-updates.md` — describes silent downloads and install-on-quit.
- `Tests/AppTests/UpdateCoordinatorTests.swift` — gate and phase tests without the live appcast.
- `scripts/build-dmg.sh` and `scripts/test-local-signing.py` — local launches already turn off checks and downloads. No change.
- Replaces automatic downloads in (updates 01 AC3, updates 01 AC6) and background staging in (updates 03 AC3). Keeps the popover row from (updates 02) and the standard flow from (updates 03 AC4).

### Root cause

A user on 0.19.0 gets 0.20.0 staged by a scheduled check. Releases 0.21.0 and 0.22.0 come out while Filbert keeps running. Every later check resumes the staged 0.20.0 without reading the feed. "Restart to Update" installs 0.20.0. Installing also resets Sparkle's last-check time, so 0.22.0 is found only after up to four more hours.

## Acceptance Criteria

### [ ] AC1: Background checks only report

- **Given** an installed release with automatic checks on
- **When** Sparkle's scheduled check is due
- **Then** Filbert runs an information-only check instead
- **And** Sparkle downloads nothing, extracts nothing, and stages no installer
- **And** the popover shows the newest version in the feed as `available`
- **And** Sparkle still owns the four-hour interval, the last-check time, and the automatic-check preference.

### [ ] AC2: The popover follows the feed

- **Given** the popover shows 0.21.0 as available
- **When** 0.22.0 is published and the next background check runs
- **Then** the popover shows 0.22.0.

### [ ] AC3: One click installs the newest release

- **Given** Filbert 0.19.0 runs, the popover shows any available version, and the feed's newest release is 0.22.0
- **When** the user selects `Update` in the popover or "Check for Updates…" in Settings
- **Then** Sparkle's user-initiated check reads the feed and offers 0.22.0
- **And** the popover row shows 0.22.0
- **And** after "Install and Relaunch" the app reports 0.22.0, and no intermediate version was installed.

### [x] AC4: Automatic downloads are gone

- **Given** any installed release, including one whose preferences store `SUAutomaticallyUpdate = YES` from an older version
- **When** the user opens Settings → About or a Sparkle update window
- **Then** Settings shows "Check for updates automatically" and no download toggle
- **And** Sparkle's update window shows no "Automatically download and install updates" checkbox
- **And** `SPUUpdater.automaticallyDownloadsUpdates` is `NO`.

### [x] AC5: The replaced scheduled check leaves no trace

- **Given** Filbert replaces a scheduled check
- **When** Sparkle reports the end of that check
- **Then** the popover phase does not change, no alert or window opens, and nothing counts as a failed check
- **And** exactly one information-only check starts.

### [x] AC6: Failed background checks stay quiet

- **Given** the Mac is offline or the feed fails
- **When** the information-only check fails
- **Then** the popover keeps its current state, Filbert keeps running, and the next check follows Sparkle's schedule, as in (updates 01 AC8).

### [ ] AC7: Tests and manual checks cover the change

- **Given** deterministic delegate calls with no network access
- **When** the App test suite runs
- **Then** tests prove that only background checks are refused, the refusal starts one information-only check, information and user checks are allowed, and the refusal error never reaches the popover phase
- **And** the full format, lint, build, and test gate passes
- **But Given** a packaged release of this change and a newer published release
- **When** the older one runs a background check
- **Then** the popover shows the newer version with an `Update` button, not "Restart to Update", and Console shows no Sparkle download
- **And** `Update` downloads, verifies, and relaunches into the newest release.

## Plan

1. **Info.plist.** Remove `SUAutomaticallyUpdate`. Add `SUAllowsAutomaticUpdates = NO`. Sparkle then reports `automaticallyDownloadsUpdates = NO` whatever the stored preference, and hides its own checkbox. Keep `SUEnableAutomaticChecks` and `SUScheduledCheckInterval`.
2. **Gate in `UpdateCoordinator`.** Implement `updater(_:mayPerformUpdateCheck:error:)`. Return `false` with a Filbert-owned error for `.updatesInBackground`, and `true` for the other checks. In `updater(_:didFinishUpdateCycleFor:error:)`, when the check is `.updatesInBackground` and the error is the Filbert one, call `checkForUpdateInformation()`. Sparkle clears the session before it calls this delegate method and does not reschedule while a new session runs (`SPUUpdater.m`, `abortUpdateDriver`). The information check then schedules the next one. `updater(_:didAbortWithError:)` ignores the Filbert error.
3. **Coordinator cleanup.** Remove `automaticallyDownloadsUpdates`, `allowsAutomaticUpdates`, `setAutomaticDownloadsUpdates`, and their observations. The `downloading`, `preparing`, `readyToInstall`, and `installing` phases stay, because the user-initiated flow still reports them.
4. **Settings.** Remove the toggle and its catalog entry.
5. **Docs.** Change `docs/automatic-updates.md` to describe information-only background checks and the one-click update, and change the "automatic downloads enabled" step in the clean-account test.
6. **Tests.** Add gate tests and keep the existing phase tests.

Refusing Sparkle's check reuses Sparkle's scheduler and its stored preference. A Filbert timer would copy the interval, the last-check persistence, and the toggle storage, which (updates 01 AC3) rules out.

## Risks

- The gate depends on Sparkle 2.9.6 calling `didFinishUpdateCycleFor` after it clears the session. A Sparkle upgrade can change this order. Then background checks stop with no error, and manual checks still work. Repeat the AC7 manual check after each Sparkle upgrade.
- Sparkle logs the refused check as an error in Console every four hours. The error message must say that this is intended.
- Users lose silent downloads. After the click, Sparkle's window shows the release notes and a download of about 9 MB.
- If the user closes Sparkle's window after the download and chooses to install on quit, the update is staged again and can go stale. The user made this choice, so it is acceptable.
- Releases before this change still stage updates silently. A user on one of them makes one more stale jump. After that, every update goes to the newest release.
- A release published after the last background check makes the popover show an older version than Sparkle offers on click. The user-initiated check reports the newer version, and the row updates.

## Findings

- 2026-10-22: AC4 to AC6 landed with unit tests. AC1 to AC3 are in code. They stay open until the manual check in AC7 passes on a packaged release.
- AC7 automated part done: format, lint, debug and release builds, all Swift tests, `scripts/test-automatic-updates.py`, and `scripts/test-local-signing.py` pass. The packaged-app manual check is open.
- A misspelled Sparkle delegate method still compiles, because Sparkle's delegate methods are optional. `testCoordinatorImplementsSparkleGateSelectors` checks the exact Objective-C selectors.
- Refusing a scheduled check shows nothing to the user. `SPUScheduledUpdateDriver` passes `showErrorToUser: NO` until it has shown an update, and the refusal comes before that.
- `didFinishUpdateCycleFor` starts the information check synchronously. Sparkle has already cleared the session, and it skips its own reschedule while the new session runs. The information check reschedules when it ends, and it respects "Check for updates automatically".
- The "Download updates automatically" string and its nine translations are removed from the catalog.

## Objective

Make every update install the newest release in the feed, so a user several versions behind updates with one click and one restart.

## Context

- `packaging/Info.plist` — ships `SUAutomaticallyUpdate = YES`. A scheduled check downloads, extracts, and stages the update to install on quit. Filbert is a menu-bar app and seldom quits, so a staged update can wait for days.
- `.build/checkouts/Sparkle/Sparkle/SPUUpdater.m` — `checkForUpdatesWithDriver` resumes a waiting installer or a kept download and does not read the feed. Scheduled checks, `checkForUpdates`, and `checkForUpdateInformation` all go through this path. Sparkle 2.9.6 has no public API to cancel a staged installer.
- `.build/checkouts/Sparkle/Sparkle/SPUStandardUserDriver.m` — gentle scheduled reminders keep the session open with the first update found. They have the same stale-version problem.
- `checkForUpdateInformation` keeps no download or installer state. When nothing is staged, it and `checkForUpdates` read the feed every time.
- `Sources/App/UpdateCoordinator.swift` — becomes the gate that turns a scheduled check into an information-only check. It also loses the install-on-quit path and returns an interrupted user check to `available`.
- `.build/checkouts/Sparkle/Sparkle/SPUAutomaticUpdateDriver.m` — the only caller of `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)`. Sparkle uses this driver only when `automaticallyDownloadsUpdates` is `YES` (`SPUUpdater.m`, `_checkForUpdatesInBackground`). With `SUAllowsAutomaticUpdates = NO`, the `readyToInstall` and `installing` phases can never start.
- `.build/checkouts/Sparkle/Sparkle/SPUCoreBasedUpdateDriver.m` — when the user closes the "Ready to Install" window, `finishInstallationWithResponse` aborts with no error. Sparkle then calls `didFinishUpdateCycleFor` but not `didAbortWithError`.
- `Sources/App/QuotaView+Footer.swift` — loses the "Restart to Update" button and the `readyToInstall` and `installing` status text.
- `Sources/App/AboutSettingsView.swift` — loses the "Download updates automatically" toggle.
- `Sources/App/Resources/Localizable.xcstrings` — the toggle string goes away. So do "Restart to Update", "Restart and update Filbert to version %@", "Filbert %@ is ready to install", and "Installing Filbert %@…", with their translations.
- `docs/automatic-updates.md` — describes silent downloads and install-on-quit.
- `Tests/AppTests/UpdateCoordinatorTests.swift` — gate and phase tests without the live appcast.
- `scripts/build-dmg.sh` and `scripts/test-local-signing.py` — local launches already turn off checks and downloads. No change.
- Replaces automatic downloads in (updates 01 AC3, updates 01 AC6), background staging and "Restart to Update" in (updates 03 AC3), and the `readyToInstall` and `installing` phases in (updates 03 AC1). Keeps the popover row from (updates 02) and the standard flow from (updates 03 AC4).

### Root cause

A user on 0.19.0 gets 0.20.0 staged by a scheduled check. Releases 0.21.0 and 0.22.0 come out while Filbert keeps running. Every later check resumes the staged 0.20.0 without reading the feed. "Restart to Update" installs 0.20.0. Installing also resets Sparkle's last-check time, so 0.22.0 is found only after up to four more hours.

## Acceptance Criteria

`[~]` marks a plausible AC. The code is in place and is assumed to work, but no packaged release has proved it. Change it back to `[ ]` when someone reports a bug against it.

### [~] AC1: Background checks only report

- **Given** an installed release with automatic checks on
- **When** Sparkle's scheduled check is due
- **Then** Filbert runs an information-only check instead
- **And** Sparkle downloads nothing, extracts nothing, and stages no installer
- **And** the popover shows the newest version in the feed as `available`
- **And** Sparkle still owns the four-hour interval, the last-check time, and the automatic-check preference.

### [~] AC2: The popover follows the feed

- **Given** the popover shows 0.21.0 as available
- **When** 0.22.0 is published and the next background check runs
- **Then** the popover shows 0.22.0.

### [~] AC3: One click installs the newest release

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

### [~] AC7: Tests and manual checks cover the change

- **Given** deterministic delegate calls with no network access
- **When** the App test suite runs
- **Then** tests prove that only background checks are refused, the refusal starts one information-only check, information and user checks are allowed, and the refusal error never reaches the popover phase
- **And** tests prove that a user check that ends with no error returns `downloading` or `preparing` to `available`, and leaves `available` and no phase unchanged
- **And** the full format, lint, build, and test gate passes
- **But Given** a packaged release of this change and a newer published release
- **When** the older one runs a background check
- **Then** the popover shows the newer version with an `Update` button, and Console shows no Sparkle download
- **And** `Update` downloads, verifies, and relaunches into the newest release.

### [x] AC8: The popover has no install-on-quit path

- **Given** `SUAllowsAutomaticUpdates = NO`, so Sparkle never calls `willInstallUpdateOnQuit`
- **When** the code and the string catalog are built
- **Then** `UpdatePhase` has only `available`, `downloading`, and `preparing`
- **And** `PopoverUpdate.Action` has only `update`
- **And** `installNow`, the immediate-install handler, the `willInstallUpdateOnQuit` delegate method, the "Restart to Update" button, and the four strings that only this path uses are gone
- **And** the `Update` button and the spinner behave as in (updates 03 AC2, updates 03 AC4).

### [x] AC9: A closed Sparkle window does not leave a spinner

- **Given** the user selected `Update`, and the phase is `downloading` or `preparing`
- **When** the user closes Sparkle's window and the user-initiated check ends with no error
- **Then** the phase returns to `available` with the same version
- **And** the row shows `Update` again when `canCheckForUpdates` is `YES`
- **And** a check that ends with an error still goes through `didAbortWithError`, as in (updates 03 AC1)
- **And** the end of a background or information-only check does not change the phase.

## Plan

1. **Info.plist.** Remove `SUAutomaticallyUpdate`. Add `SUAllowsAutomaticUpdates = NO`. Sparkle then reports `automaticallyDownloadsUpdates = NO` whatever the stored preference, and hides its own checkbox. Keep `SUEnableAutomaticChecks` and `SUScheduledCheckInterval`.
2. **Gate in `UpdateCoordinator`.** Implement `updater(_:mayPerformUpdateCheck:error:)`. Return `false` with a Filbert-owned error for `.updatesInBackground`, and `true` for the other checks. In `updater(_:didFinishUpdateCycleFor:error:)`, when the check is `.updatesInBackground` and the error is the Filbert one, call `checkForUpdateInformation()`. Sparkle clears the session before it calls this delegate method and does not reschedule while a new session runs (`SPUUpdater.m`, `abortUpdateDriver`). The information check then schedules the next one. `updater(_:didAbortWithError:)` ignores the Filbert error.
3. **Coordinator cleanup.** Remove `automaticallyDownloadsUpdates`, `allowsAutomaticUpdates`, `setAutomaticDownloadsUpdates`, and their observations. The `downloading` and `preparing` phases stay, because the user-initiated flow reports them through `willDownloadUpdate`, `didDownloadUpdate`, and `willExtractUpdate`.
4. **Settings.** Remove the toggle and its catalog entry.
5. **Docs.** Change `docs/automatic-updates.md` to describe information-only background checks and the one-click update, and change the "automatic downloads enabled" step in the clean-account test.
6. **Tests.** Add gate tests and keep the existing phase tests.
7. **Remove install-on-quit.** Remove the `readyToInstall` and `installing` phases, `PopoverUpdate.Action.restartToUpdate`, `installNow`, `immediateInstallHandler`, `recordReadyToInstall`, and the `willInstallUpdateOnQuit` delegate method. In `QuotaView+Footer.swift`, remove the "Restart to Update" button and the two status cases. Remove the four strings and their translations from the catalog. Remove or rewrite the tests that drive those phases. `testRefusalNeverReachesPopoverPhase` changes to start from `downloading`.
8. **Interrupted user check.** In `updater(_:didFinishUpdateCycleFor:error:)`, every check that does not start the information check goes to `recordUpdateCycleEnd(_:)`. For a `.updates` check, that method turns `downloading` or `preparing` back into `available` with the same version. Other checks leave the phase alone. The method ignores the error: after `didAbortWithError`, the phase is already `available`, so the second call changes nothing.
9. **Docs.** In `docs/automatic-updates.md`, remove "not **Restart to Update**" from step 8 of the clean-account test. Wrap the long line in the Sparkle-interface paragraph.

Refusing Sparkle's check reuses Sparkle's scheduler and its stored preference. A Filbert timer would copy the interval, the last-check persistence, and the toggle storage, which (updates 01 AC3) rules out.

## Risks

- The gate depends on Sparkle 2.9.6 calling `didFinishUpdateCycleFor` after it clears the session. A Sparkle upgrade can change this order. Then background checks stop with no error, and manual checks still work. Repeat the AC7 manual check after each Sparkle upgrade.
- Sparkle logs the refused check as an error in Console every four hours. The error message must say that this is intended.
- Users lose silent downloads. After the click, Sparkle's window shows the release notes and a download of about 9 MB.
- If the user closes Sparkle's window after the download, the update stays staged and can go stale. The user made this choice, so it is acceptable. The row returns to `available` (AC9). The next `Update` resumes the staged update and does not download it again. The next background check also reports the staged version, not the newest one in the feed.
- If automatic downloads come back one day, the popover will have no "Restart to Update" path. Bring back the phases from (updates 03 AC3) together with them.
- Releases before this change still stage updates silently. A user on one of them makes one more stale jump. After that, every update goes to the newest release.
- A release published after the last background check makes the popover show an older version than Sparkle offers on click. The user-initiated check reports the newer version, and the row updates.

## Findings

- 2026-10-22: AC4 to AC6 landed with unit tests. AC1 to AC3 are in code. They stay open until the manual check in AC7 passes on a packaged release.
- AC7 automated part done: format, lint, debug and release builds, all Swift tests, `scripts/test-automatic-updates.py`, and `scripts/test-local-signing.py` pass. The packaged-app manual check is open.
- A misspelled Sparkle delegate method still compiles, because Sparkle's delegate methods are optional. `testCoordinatorImplementsSparkleGateSelectors` checks the exact Objective-C selectors.
- Refusing a scheduled check shows nothing to the user. `SPUScheduledUpdateDriver` passes `showErrorToUser: NO` until it has shown an update, and the refusal comes before that.
- `didFinishUpdateCycleFor` starts the information check synchronously. Sparkle has already cleared the session, and it skips its own reschedule while the new session runs. The information check reschedules when it ends, and it respects "Check for updates automatically".
- The "Download updates automatically" string and its nine translations are removed from the catalog.
- 2026-10-22 review: Sparkle calls `willInstallUpdateOnQuit` only from `SPUAutomaticUpdateDriver`, so the "Restart to Update" path can never run (AC8). Closing Sparkle's "Ready to Install" window ends the user check with no error, so the row stayed on the `preparing` spinner until the next background check (AC9).
- 2026-10-22: AC1 to AC3 and the manual part of AC7 are marked plausible (`[~]`). They need a published release to verify. The long line in `docs/automatic-updates.md` is wrapped.
- 2026-10-22: AC8 and AC9 landed with unit tests. The full gate passes: format, lint, debug and release builds, 368 Swift tests, `scripts/test-automatic-updates.py`, and `scripts/test-local-signing.py`. The four strings came out of the catalog, which still parses as valid JSON.
- `recordUpdateCycleEnd` does not check the error. Sparkle also skips `didAbortWithError` for `SUInstallationAuthorizeLaterError` (`SPUUpdater.m`, `notifyDelegateOfDriverCompletion`). If the method required a nil error, that ending would leave the spinner too.
- `testCoordinatorImplementsSparkleGateSelectors` also checks that the coordinator no longer answers `updater:willInstallUpdateOnQuit:immediateInstallationBlock:`.

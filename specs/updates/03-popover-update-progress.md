## Objective

Make the popover update row show what Sparkle is doing and offer only actions that take effect on the first click.

## Context

- `packaging/Info.plist` — ships `SUAutomaticallyUpdate = YES`, so a scheduled check runs Sparkle's silent automatic driver: find, download, extract, then install on quit.
- `Sources/App/UpdateCoordinator.swift` — publishes the available version from `didFindValidUpdate`, which fires at the *start* of the silent download, not when the update is ready.
- `Sources/App/QuotaView+Footer.swift` — renders the row and disables `Update` while `canCheckForUpdates` is `false`. That holds for the whole background session.
- `.build/checkouts/Sparkle/Sparkle/SPUUpdater.m` — `checkForUpdates` returns silently while `sessionInProgress` is `YES` and the automatic driver reports `showingUpdate == NO`. Clicks during the download are dropped.
- `Sources/App/Resources/Localizable.xcstrings` — new status and action strings.
- `Tests/AppTests/UpdateCoordinatorTests.swift` — phase transitions without the live appcast.
- Builds on (updates 01) and replaces the action behavior in (updates 02 AC2, updates 02 AC3).

### Root cause

The row appears when the silent download starts. The `.small` disabled button looks almost the same as an enabled one in the vibrant popover. Sparkle drops every click until download and extraction finish. Then the session ends, `canCheckForUpdates` turns `YES`, and the next click opens Sparkle's "ready to install" window. The user sees no change between those states.

## Acceptance Criteria

### [x] AC1: The coordinator tracks the update phase

- **Given** Sparkle reports update-cycle events
- **When** it finds an update, starts or finishes the download, starts or finishes extraction, schedules install-on-quit, or fails
- **Then** `UpdateCoordinator` publishes one phase: `available`, `downloading`, `preparing`, `readyToInstall`, or `installing`
- **And** each phase carries the release version
- **And** a download or extraction failure returns the phase to `available`.

### [x] AC2: Background work shows progress, not a dead button

- **Given** the phase is `downloading` or `preparing`
- **When** the user opens the popover
- **Then** the row shows a small indeterminate spinner and "Downloading Filbert 0.18.0…" or "Preparing Filbert 0.18.0…"
- **And** the row shows no button.

### [x] AC3: A ready update installs in one click

- **Given** Sparkle has downloaded and prepared the update and called `willInstallUpdateOnQuit`
- **When** the user selects "Restart to Update"
- **Then** Filbert calls Sparkle's immediate installation handler once
- **And** the row changes to `installing` with a spinner and "Installing…" before the app relaunches
- **And** Sparkle still installs the update on a normal quit if the user never clicks.

### [x] AC4: An update that was not downloaded uses Sparkle's standard flow

- **Given** the phase is `available` because automatic downloads are off, the update needs user attention, or the download failed
- **When** the user selects `Update`
- **Then** Filbert calls `checkForUpdates` and Sparkle shows its own window with download progress
- **And** the button shows only when `canCheckForUpdates` is `YES`; otherwise the row shows the spinner state.

### [x] AC5: The row stays accessible

- **Given** any phase is visible
- **When** VoiceOver reads the row
- **Then** it announces the status text, and the button label names the version
- **And** long localized text does not push the button off the 280 pt popover.

### [x] AC6: Tests cover the phases

- **Given** deterministic delegate events with no network access
- **When** the App test suite runs
- **Then** tests cover each phase transition, failure fallback, and the one-shot use of the install handler
- **And** the full format, lint, build, and test gate passes.

## Plan

Replace `availableUpdateVersion` with an `UpdatePhase` enum on `UpdateCoordinator`. Implement the Sparkle delegate hooks `willDownloadUpdate`, `didDownloadUpdate`, `failedToDownloadUpdate`, `willExtractUpdate`, `didExtractUpdate`, and `willInstallUpdateOnQuit`. Route each hook through a testable `record(_:)` method, as `recordUpdateCheckResult` does today. Return `YES` from `willInstallUpdateOnQuit` and keep the handler. `installNow()` calls it and clears it. `PopoverUpdate` maps the phase and `canCheckForUpdates` to status text, spinner visibility, and an optional action. The footer renders that model.

```swift
enum UpdatePhase: Equatable {
    case available(version: String)
    case downloading(version: String)
    case preparing(version: String)
    case readyToInstall(version: String)
    case installing(version: String)
}
```

## Risks

- Returning `YES` from `willInstallUpdateOnQuit` stops later update cycles in this process. A newer release published while 0.18.0 waits is found only after relaunch. Install-on-quit still applies.
- Sparkle has no byte-level progress for silent downloads. The spinner is indeterminate.
- A crash between "Restart to Update" and relaunch leaves Sparkle's installer to finish on the next launch. This is Sparkle's normal behavior.
- Spinner plus text in a second row can clip long localizations at 280 pt.
- While the popover holds a ready update, Sparkle keeps the session open. Settings → About → "Check for Updates…" stays disabled until relaunch. The popover row is the only install action in that state.

## Findings

- `didDownloadUpdate` also maps to `preparing`. Sparkle's installer prepares the update between download and `willInstallUpdateOnQuit`, and extraction alone does not cover that gap.
- `userDidCancelDownload` maps to an interruption. A user who cancels in Sparkle's standard window gets the `Update` button back.

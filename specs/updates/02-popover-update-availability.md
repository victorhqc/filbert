## Objective

Show a persistent, actionable update notice in the menu-bar popover when Sparkle discovers a newer Filbert release.

## Context

- `Sources/App/UpdateCoordinator.swift` — owns Sparkle and must expose discovered-update state without duplicating Sparkle's version comparison, download, or installation logic.
- `Sources/App/AppMain.swift` — shares the application-lifetime update coordinator with the menu-bar popover.
- `Sources/App/QuotaView.swift` — renders the footer that contains Settings, the installed version, and Quit.
- `Sources/App/Resources/Localizable.xcstrings` — supplies localized notice, action, and accessibility text.
- `Tests/AppTests/UpdateCoordinatorTests.swift` — covers updater state independently of the live feed.
- This extends the secure discovery and installation flow from (updates 01) and keeps the version presentation from (ui 20).

## Acceptance Criteria

### [x] AC1: A discovered update becomes observable application state

- **Given** Sparkle completes an automatic or manual check
- **When** it reports a valid release newer than the running version
- **Then** `UpdateCoordinator` publishes the available release version for SwiftUI
- **And** Sparkle remains the source of truth for update eligibility and version comparison
- **And** a later failed check does not erase a previously discovered valid update.

### [x] AC2: The popover presents the available update

- **Given** `UpdateCoordinator` reports an available release
- **When** the user opens the menu-bar popover
- **Then** a compact row appears below the Settings, installed-version, and Quit row
- **And** the row identifies the available version
- **And** the row contains a localized `Update` button
- **And** the notice remains visible across popover dismissals while the current app process is running.

### [x] AC3: The update action uses Sparkle's standard flow

- **Given** the popover displays an available update
- **When** the user selects `Update`
- **Then** Filbert asks Sparkle to present its standard user-initiated update flow
- **And** Sparkle remains responsible for release notes, download progress, signature verification, installation, cancellation, and relaunch
- **And** Filbert does not download or install the release through a second implementation.

### [x] AC4: The footer remains unchanged when no update is known

- **Given** the updater is unavailable, has not completed a check, or reports no newer release
- **When** the user opens the menu-bar popover
- **Then** no update row is shown
- **And** the existing Settings, installed-version, and Quit controls keep their current placement and behavior
- **And** development and test hosts perform no update-network activity.

### [x] AC5: The notice is accessible and resilient

- **Given** the update row is visible
- **When** it is used with keyboard navigation, VoiceOver, light mode, dark mode, or Increased Contrast
- **Then** the available version and update action remain legible and operable
- **And** long localized text does not overlap the existing footer controls or expand the popover beyond its fixed width
- **And** a background check failure does not block provider data or other popover actions.

### AC6: Update availability is covered by focused tests

- **Given** deterministic updater events are supplied without contacting the live appcast
- **When** the App test suite runs
- **Then** tests cover discovery, no-update, and failure-after-discovery state transitions
- **And** tests cover update-row visibility and action availability
- **And** the full formatting, lint, build, and test validation gate passes.

## Plan

Make `UpdateCoordinator` Sparkle's retained delegate and publish only the available version and the action needed by SwiftUI. Pass the existing coordinator into `QuotaView`, extract a compact footer notice whose visibility is driven by that state, and route its button back through Sparkle's standard user-initiated check and installation presentation. Keep state-transition and presentation logic independently testable without a packaged application or live network request.

## Risks

- Sparkle retains its updater delegate weakly; the application-lifetime coordinator must remain alive for update state to reach the UI.
- Replacing Sparkle's standard user driver or implementing installation in Filbert would create competing update flows and weaken the existing security boundary.
- A second footer row can clip localized or accessibility-sized text in the fixed-width popover.
- Local package builds are currently blocked before App compilation because `Sources/Providers/Cursor/Resources/Localizable.xcstrings` contains the existing `%@ / %@` key, from which Xcode cannot generate a Swift symbol.

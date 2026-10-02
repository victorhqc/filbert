## Objective

Let users configure Filbert to start automatically when they log in to macOS.

## Context

- `Sources/App/AppMain.swift` — owns app-lifetime state and creates the Settings window.
- `Sources/App/SettingsView.swift` — adds a General tab for app behavior that is independent of providers.
- `Sources/App/GeneralSettingsView.swift` — new view for the launch-at-login control.
- `Sources/App/LaunchAtLoginController.swift` — new app-layer controller for login-item status and explicit user actions.
- `Sources/App/Resources/Localizable.xcstrings` — contains the new interface text.
- `Tests/AppTests/LaunchAtLoginControllerTests.swift` — new tests with an injected login-item client.
- `scripts/build-dmg.sh` and `scripts/test-local-signing.py` — compile and verify string catalogs in packaged resource bundles.
- `Package.swift` — requires macOS 14, which supports `SMAppService.mainApp`.
- `packaging/Info.plist` — supplies the installed app's bundle identifier and `LSUIElement` menu-bar behavior.
- The Settings layout uses the existing cards and scroll column (ui 15). The feature does not change providers, refresh schedules, networking, or Keychain access.
- Apple documents `SMAppService.mainApp` as the main application login item. Its registration starts the app on subsequent logins, not before a user signs in.

## Acceptance Criteria

### AC1: Users can find the control in Settings
- **Given** the user opens Filbert Settings
- **When** the General tab appears
- **Then** a Startup card contains a "Launch at login" toggle
- **And** its description explains that Filbert starts in the menu bar after the user signs in
- **And** the control is available even when no provider is configured

### AC2: Automatic launch requires an explicit choice
- **Given** macOS has no login-item registration for Filbert
- **When** Filbert starts or Settings opens
- **Then** the toggle is off
- **And** Filbert does not register itself until the user enables the toggle
- **And** an existing enabled registration appears as on without a new registration request

### AC3: Users can enable and disable automatic launch
- **Given** the user runs an installed Filbert app bundle
- **When** the user changes the toggle
- **Then** enabling calls `SMAppService.mainApp.register()` and disabling calls `SMAppService.mainApp.unregister()`
- **And** the controller reads the resulting macOS status rather than assuming that the request succeeded
- **And** disabling does not quit the current Filbert process
- **And** repeated requests for the current state do not repeat registration or removal
- **And** quitting Filbert does not remove its login-item registration

### AC4: Approval status is visible and actionable
- **Given** macOS reports `requiresApproval`, including after the user revokes consent in System Settings
- **When** the Startup card appears
- **Then** it explains that Filbert is registered but cannot start at login until macOS approval is restored
- **And** the toggle remains on to represent the registration, not approval
- **And** an "Open Login Items Settings" button calls `SMAppService.openSystemSettingsLoginItems()`
- **And** the user can turn the toggle off to remove the pending registration
- **And** Filbert does not repeatedly register or override the user's macOS decision

### AC5: macOS is the source of truth
- **Given** the user changes Filbert's login item in System Settings
- **When** Filbert becomes active again or the General tab appears
- **Then** the controller reads the current macOS status and updates the control
- **And** no separate UserDefaults boolean can override or contradict that status
- **And** the controller distinguishes enabled, unregistered, approval-required, and unavailable states

### AC6: Errors and unsupported execution modes are safe
- **Given** registration or removal fails
- **When** the controller completes the request
- **Then** the Startup card shows a localized error and the actual macOS status
- **And** the user can retry an applicable action without restarting Filbert
- **And** Filbert continues to display provider data and refresh normally
- **Given** Filbert runs as a bare SwiftPM executable rather than an app bundle, or macOS reports `notFound`
- **When** the Startup card appears
- **Then** it disables the toggle and explains that launch at login requires an installed Filbert app
- **And** it does not create a LaunchAgent, invoke a shell command, or attempt a fallback registration

### AC7: Login launch preserves normal menu-bar behavior
- **Given** the installed Filbert app has an enabled login item
- **When** the user logs out and logs in, or restarts the Mac and signs in
- **Then** Filbert starts automatically in the menu bar
- **And** Filbert does not open Settings or the quota panel automatically
- **And** normal provider initialization and refresh remain unchanged
- **And** after the user disables the login item, subsequent logins do not start Filbert through that registration
- **And** manual launch still works with the login item disabled

### AC8: The behavior is accessible, localized, and verified
- **Given** the user uses a non-English locale, a keyboard, or VoiceOver
- **When** the General tab appears
- **Then** all new interface text uses `String(localized:)` and appears in `Localizable.xcstrings`
- **And** the toggle, status, error, and System Settings button have meaningful accessible labels
- **Given** an injected fake login-item client
- **When** the App test suite runs
- **Then** tests cover initial status, registration, removal, no-op requests, approval-required status, external status changes, both operation failures, and unavailable execution modes
- **And** tests never change the real user's login items

## Plan

1. [x] Add a small app-layer login-item client that wraps `SMAppService.mainApp`, its status, and the System Settings action. Keep macOS side effects behind this boundary.
2. [x] Add an observable, main-actor `LaunchAtLoginController`. Inject the client for tests. Read status on initialization, after every operation, when General appears, and when Filbert becomes active again. Do not store a duplicate preference. The controller observes app activation; the General view calls `refreshStatus()` on appearance.
3. [x] Detect bare-executable execution before offering registration. Map unavailable and unknown framework states to a safe disabled control. The client requires an `.app` bundle with package type `APPL` and a nonempty identifier before it accesses `SMAppService.mainApp`.
4. [x] Own one controller in `AppMain` and pass it explicitly to `SettingsView`. Keep startup state separate from `QuotaViewModel`.
5. [x] Add General as the first Settings tab. Use `SettingsScrollColumn` and `SettingsCard` for the Startup card, toggle, approval guidance, and operation errors.
6. [x] Add localized text and focused App tests. Run the repository's required code validation. Resolve new text through `Bundle.module`. Compile string catalogs in packaged resource bundles before signing.
7. [ ] Validate with an installed, signed Filbert app on macOS. Confirm registration in System Settings, automatic launch after login, external approval changes, removal, and manual launch. Confirm that an in-place app update preserves the login item.

The user approved this spec before production implementation began.

Implementation finding: Native SwiftPM builds copy `.xcstrings` files without compilation. Filbert packages those resource bundles separately from `Bundle.main`. New text therefore requires `Bundle.module` lookup and compiled localization tables in the packaged bundles. Packaging tests verify translated tables and a failure for an invalid catalog.

Automated validation covers 18 controller tests and 5 eligibility tests. The full validation gate includes format, lint, debug and release builds, all Swift tests, and both Python suites.

Manual validation remains pending. This agent did not change the user's login items, install an app, restart the Mac, or perform an in-place app update.

## Risks

- Login-item registration depends on a real app bundle. Bare `swift run` execution cannot prove that automatic launch works.
- macOS can require approval or revoke consent. An on toggle must not imply approval when the status is `requiresApproval`.
- Login-item behavior can depend on the app's location and signing identity. Manual validation must use the installed app rather than a temporary executable.
- macOS can restore apps from a previous session independently of login items. Disable session restoration during the removal validation to isolate Filbert's registration.
- A General tab changes the initial Settings tab. Existing provider controls remain on the Providers tab.

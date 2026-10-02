## Objective

Allow an installed Filbert app to attempt login-item registration when macOS cannot find its login-item service.

## Context

- `Sources/App/LaunchAtLoginClient.swift` — maps `SMAppService.mainApp.status` and checks the app bundle before access to Service Management.
- `Sources/App/LaunchAtLoginController.swift` — controls whether the toggle can request registration.
- `Sources/App/GeneralSettingsView.swift` — explains the current state.
- `Sources/App/Resources/Localizable.xcstrings` — contains the new state message.
- `Tests/AppTests/LaunchAtLoginClientTests.swift` — verifies native status conversion and safe rejection of bare-executable requests.
- `Tests/AppTests/LaunchAtLoginControllerTests.swift` — verifies explicit registration, native status changes, and failures through a fake client.
- `Tests/AppTests/LaunchAtLoginEligibilityTests.swift` — preserves the restriction on bare SwiftPM executables.
- The native status conversion needs direct tests. The existing controller tests supply app-layer states and do not exercise that conversion.
- This correction supersedes the rule that `notFound` must disable the control and imply a missing installed app (ui 26 AC6).
- Read-only inspection confirms that `/Applications/Filbert.app` v0.16.0 has valid app metadata, a Developer ID signature, and a stapled notarization ticket.
- A separate, ad-hoc-signed diagnostic app on the same host reports `SMAppService.mainApp.status == .notFound` despite valid `Bundle.main` metadata. The diagnostic app does not register a login item.
- The diagnostic confirms that `notFound` is not sufficient evidence that the app bundle is missing. It does not prove that registration will succeed.
- [Apple DTS explains](https://developer.apple.com/forums/thread/719862) that `notFound` can mean the system has never seen a login-item service. That example concerns a helper login item, not `mainApp`. The local diagnostic supplies evidence for `mainApp` on this host.

## Acceptance Criteria

### AC1: A missing service does not disable registration for an eligible app
- **Given** Filbert runs from an eligible app bundle and macOS reports `notFound`
- **When** the General tab appears
- **Then** the toggle is off but remains available
- **And** the state remains distinct from an unavailable app bundle
- **And** the message describes the missing login-item service without claiming that Filbert is not installed

### AC2: Registration requires an explicit user action
- **Given** an eligible app has a `notFound` login-item service
- **When** the user enables "Launch at login"
- **Then** Filbert attempts `SMAppService.mainApp.register()` once and reads the resulting status
- **And** an enabled result shows an on toggle
- **And** an approval-required result shows the existing approval guidance
- **And** a failed request shows a localized registration error and permits another explicit attempt
- **And** Filbert does not register during initialization, status refresh, or app activation

### AC3: An unresolved service does not imply a successful registration
- **Given** a registration attempt returns without an error but macOS still reports `notFound`
- **When** Filbert reads the resulting status
- **Then** the toggle remains off and available
- **And** Filbert does not claim that it will start at login
- **And** Filbert does not repeat the request automatically

### AC4: Unsupported execution modes remain safe
- **Given** Filbert runs as a bare executable or fails the existing bundle eligibility checks
- **When** Settings appears or code requests registration
- **Then** the control remains unavailable and no native registration occurs
- **And** unknown native statuses remain unavailable rather than implying an enabled registration
- **And** no shell command, LaunchAgent, or duplicate UserDefaults preference is introduced

### AC5: Regression coverage includes native status conversion
- **Given** direct tests of every known `SMAppService.Status` value and a fake login-item client
- **When** the App test suite runs
- **Then** native `notFound` maps to the distinct service-not-found state rather than unavailable
- **And** tests cover explicit registration from that state, approval-required results, failures, retries, and unresolved results
- **And** tests confirm that a missing service does not cause an unnecessary removal request
- **And** automated tests do not change the user's real login items

## Plan

1. [x] Preserve native `notFound` as a distinct app-layer state. Keep app-bundle eligibility separate from service existence. Allow explicit registration from the new state. Update and localize its Settings message.
2. [x] Add direct native-status conversion tests and controller regression tests. Run the complete repository validation gate.
3. [ ] Validate an installed, signed build with the user's consent. Confirm that the initial toggle permits registration and that macOS reports the result. Confirm automatic launch after login and removal after the user disables the toggle.

The user approved this correction before production implementation began.

Validation: The full repository gate passes. All 30 launch-at-login tests pass, including native status conversion, registration failures, retries, and unresolved service results.

A read-only, ad-hoc-signed app fixture compiled with the production client reports native status `3` and app-layer state `notFound`. The fixture confirms that the client no longer reports an eligible app as unavailable in this case.

Independent review found no issues. Installed Developer ID registration and login-session validation remain pending. This implementation did not change the user's installed app or real login items.

## Risks

- A native registration attempt can still fail because of a platform or signature error. Filbert must show failure rather than assume success.
- An ad-hoc diagnostic app does not replace validation of the installed Developer ID build.
- Automatic launch after login still requires a manual session test. Status queries and unit tests cannot prove that behavior.

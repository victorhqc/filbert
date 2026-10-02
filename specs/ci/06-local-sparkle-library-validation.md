## Objective
Make local ad-hoc Filbert builds load bundled Sparkle without weakening Developer ID release protection.

## Context
- `scripts/build-dmg.sh` signs both local and release artifacts with Hardened Runtime.
- `packaging/Filbert.entitlements` is the shared release baseline and must not contain a library-validation exception.
- Ad-hoc signatures have no Team ID. The local app rejected its ad-hoc Sparkle framework at launch.
- App and framework signatures passed on-disk verification before that failure.
- A private copy exited with a loader failure under the current signing policy.
- The same copy stayed alive after only the host app received the library-validation exception.
- This repairs a runtime failure found during fresh-install verification (providers 13).
- Developer ID identity, Hardened Runtime, notarization, and release checks remain unchanged (ci 05, updates 01).
- Sparkle recommends a development certificate or a development-only library-validation exception for ad-hoc hosts.

## Acceptance Criteria

### AC1: Local signing uses a narrow exception
- **Given** an explicit local ad-hoc build
- **When** the script signs the app
- **Then** the app retains Hardened Runtime and receives `com.apple.security.cs.disable-library-validation = true`.
- Local entitlements derive from the shared baseline.
- The shared baseline file remains unchanged.
- The exception applies to the host executable, not to every nested component.

### AC2: Release protection remains strict
- **Given** the Developer ID lane
- **When** the script signs and verifies the release
- **Then** the app uses the existing release entitlements without the local exception.
- Identity selection, Team ID validation, timestamps, notarization, stapling, and Gatekeeper checks remain unchanged.
- Tests verify that local signing settings cannot enter the release lane.

### AC3: Startup checks detect runtime failures
- **Given** a packaged app with valid on-disk signatures
- **When** the launch smoke test runs
- **Then** the actual launched process must remain alive through a bounded startup interval.
- An immediate loader crash fails the check.
- The test does not accept an unrelated process that matches the executable path.
- Provider and automatic-refresh overrides prevent credential access and provider requests during this check.
- The overrides do not change persistent user preferences.

### AC4: Local policy has regression coverage
- **Given** repository validation without Apple signing credentials
- **When** signing-policy tests run
- **Then** tests verify the local exception, retained runtime flags, and strict release separation.
- A real local packaged launch verifies that Sparkle loads successfully.
- Unit checks do not claim that Developer ID notarization was exercised.

### AC5: Installed recovery preserves user data
- **Given** explicit permission to repair the installed local app
- **When** the developer replaces or re-signs it
- **Then** a private app-bundle backup exists before the operation.
- The repaired installed app remains running.
- Provider settings, Claude Code configuration, credentials, and project data are not reset.
- Local recovery does not publish an artifact or modify Git state.

## Plan
- [x] Reproduce the loader failure in a private copy with providers disabled.
- [x] Verify that the host-only exception permits startup while retaining Hardened Runtime.
- [x] Back up and repair the installed local app with user permission.
- [x] Derive local-only entitlements in the ad-hoc signing path.
- [x] Keep the Developer ID path and shared baseline unchanged.
- [x] Add signing-policy regression checks.
- [x] Strengthen the bounded launch check and isolate provider preferences.
- [x] Run the full validation gate and a real packaged local launch.

## Verification
- The full gate passed formatting, lint, debug and release builds, and all 560 Swift tests.
- All 11 update-workflow tests and 26 signing/startup tests passed.
- Signing tests execute the actual functions with a stubbed signer.
- The local host retains Hardened Runtime and receives the exception. Nested components do not receive it.
- Release-policy tests retain Developer ID identity, timestamps, team checks, and the shared baseline.
- Parent-only TERM, HUP, and INT tests stop blocked local signers and remove temporary entitlements.
- Startup tests reject immediate exits and delayed crashes. They preserve unrelated processes with the same executable path.
- Provider discovery binds literal metadata to the conforming type and rejects ambiguous or unsupported source shapes.
- A native macOS fixture verifies the XML argument-domain bridge and Sparkle boolean overrides.
- The native fixture uses conflicting volatile registered defaults, not an existing user preference domain.
- The completed local DMG passed nested signatures, helper execution, and the actual five-second launch check.
- The verification copy retains its `.app` suffix.
- A second real launch from the DMG copy left selected persistent provider, refresh, and updater preferences unchanged.
- The final DMG completed normal Finder decoration. Developer ID signing and notarization were not performed.
- CI and developer validation instructions now include the signing/startup regression suite.
- Static review found no blockers in the final implementation.

## Risks
- Disabling library validation permits additional libraries in the local app process.
- Applying the exception to releases would weaken the production trust policy.
- Changing a local signature can cause macOS to request Keychain authorization again.
- A successful signature check does not prove that the loader accepts a framework.
- Developer ID and notarization verification still require the separate release environment.

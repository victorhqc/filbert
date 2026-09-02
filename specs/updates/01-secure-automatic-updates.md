## Objective

Let installed Filbert releases securely discover, download, and apply stable updates through Sparkle and GitHub without operating a dedicated update server or interrupting the user unexpectedly.

## Context

- `Package.swift` — adds Sparkle 2 as an App-only runtime dependency; `Core` and provider targets remain independent.
- `Sources/App/AppMain.swift` — owns application startup and the lifetime of the updater controller.
- `Sources/App/AboutSettingsView.swift` and `Sources/App/SettingsView.swift` — expose manual update checks and user-controlled automatic update preferences beside the installed version from (ui 20).
- `Sources/App/AboutAcknowledgements.swift` — must disclose Sparkle as a shipped MIT-licensed runtime library, replacing the no-runtime-library claim from (ui 20 AC7).
- `Sources/App/Resources/Localizable.xcstrings` — supplies localized update settings, actions, status, and accessibility text.
- `packaging/Info.plist` — supplies the installed version, Sparkle feed URL, embedded EdDSA public key, and default scheduling policy.
- `scripts/build-dmg.sh` — assembles the custom app bundle and must embed Sparkle with a valid runtime search path, preserve framework symlinks, sign nested code correctly, and retain the existing notarization guarantees.
- `.github/workflows/release.yml` — signs the update artifact, uploads it to the exact GitHub Release, and publishes the stable appcast only after the release artifact passes verification.
- New `docs/automatic-updates.md` — documents GitHub Pages setup, the Sparkle signing key, the release sequence, end-to-end verification, recovery, and key rotation.
- This feature extends the signed and notarized direct-distribution pipeline from (ci 05) and does not replace Apple Developer ID signing, notarization, stapling, or Gatekeeper verification.
- Sparkle is an MIT-licensed macOS update framework whose appcast and publishing contracts are documented at `https://sparkle-project.org/documentation/` and `https://sparkle-project.org/documentation/publishing/`.

## Acceptance Criteria

### AC1: Sparkle is isolated to the application

- **Given** the package dependencies are resolved
- **When** the SwiftPM target graph is inspected
- **Then** a pinned Sparkle 2 release is a direct dependency of `App`
- **And** `Core` and every provider target have no Sparkle dependency or update-service knowledge
- **And** Sparkle appears in Filbert's About acknowledgements with its canonical project URL and MIT license
- **And** the acknowledgement no longer claims that Filbert has no third-party runtime libraries.

### AC2: Only installed release bundles start the updater

- **Given** Filbert launches from a packaged `.app` with a valid, non-placeholder version and Sparkle configuration
- **When** application startup completes
- **Then** one main-actor updater controller starts and remains alive for the application lifetime
- **And** the updater uses the main application bundle as its host
- **And** startup performs no GitHub API request and reads no provider credential or Keychain item
- **But Given** Filbert runs through `swift run`, a unit test host, or a malformed development bundle
- **When** startup completes
- **Then** automatic update activity is disabled without a crash, alert, or development-only network request.

### AC3: Automatic checks are rate-limited and user-controlled

- **Given** the user has not changed update preferences
- **When** an installed release runs
- **Then** automatic update checks and automatic update downloads are enabled by default
- **And** a background check becomes due no more than once every four hours, including across application relaunches
- **And** merely reopening Filbert within four hours of the last check does not make another request
- **And** Sparkle persists the last-check time and preferences rather than Filbert implementing a competing timer or scheduler
- **And** the user can independently disable automatic checks and automatic downloads using native controls in Settings.

### AC4: GitHub hosts update discovery without an application credential

- **Given** a stable Filbert release has completed the publication workflow
- **When** an installed release checks for updates
- **Then** it fetches a static HTTPS appcast from a stable GitHub Pages URL
- **And** the appcast references the versioned DMG asset on the exact GitHub Release tag rather than a mutable `latest` download URL
- **And** neither the application nor the feed URL contains a GitHub token, Apple credential, Sparkle private key, or repository write credential
- **And** update discovery does not depend on GitHub API availability or API rate limits
- **And** no separately operated application server, database, or update service is required.

### AC5: Every downloaded update has independent trust checks

- **Given** the appcast advertises a newer release
- **When** Sparkle downloads its DMG
- **Then** Sparkle verifies the artifact with the EdDSA public key embedded in the installed Filbert bundle
- **And** the corresponding private key exists only as a protected secret in the `release-signing` GitHub Environment
- **And** Sparkle also requires the replacement application to retain Filbert's valid Apple code-signing identity
- **And** a missing, malformed, unsigned, incorrectly signed, or tampered artifact is rejected before installation
- **And** the published SHA-256 file remains available for human verification but is not treated as a substitute for Sparkle's authenticated signature.

### AC6: Updates download quietly and install at a safe boundary

- **Given** automatic downloads are enabled and Sparkle finds a valid newer release
- **When** the download completes
- **Then** Filbert presents the standard update availability and release-note experience without stealing focus during a background check
- **And** the user can choose `Install and Relaunch` to apply it immediately
- **And** a downloaded update may install when Filbert next quits using Sparkle's supported installation flow
- **And** Filbert never terminates or relaunches itself unexpectedly merely because a scheduled check found an update
- **And** installation preserves the user's settings, provider configuration, and Keychain credentials
- **And** a successful immediate installation relaunches the new version and the running bundle reports the advertised version.

### AC7: Manual checking remains available and accessible

- **Given** the user opens the About settings
- **When** the updater is ready
- **Then** a localized `Check for Updates…` action starts Sparkle's user-initiated check even if automatic checks are disabled or not yet due
- **And** the action is disabled while Sparkle cannot check or another check is in progress
- **And** automatic-check and automatic-download controls accurately reflect Sparkle's persisted settings and constraints
- **And** all update controls support keyboard navigation, VoiceOver, light mode, dark mode, Increased Contrast, and the minimum Settings window size
- **And** the existing version, project, license, and acknowledgement content from (ui 20) remains available.

### AC8: Background failures do not disrupt Filbert

- **Given** the Mac is offline, GitHub is unavailable, the feed returns an HTTP error, or the appcast is malformed
- **When** a scheduled background check fails
- **Then** Filbert continues running with its current version and provider data
- **And** it does not show a blank popover, crash, repeatedly retry outside Sparkle's scheduling policy, or report an update as installed
- **And** a later scheduled or manual check can recover without clearing application state
- **But Given** the user explicitly requests a manual check
- **When** that check fails
- **Then** Sparkle's standard user-facing failure presentation explains that the check could not complete.

### AC9: The packaged app embeds valid updater components

- **Given** the custom SwiftPM release assembly runs
- **When** it creates `Filbert.app`
- **Then** the bundle contains the Sparkle framework and required helper services in their documented macOS locations
- **And** the copy operation preserves Sparkle's framework symlinks
- **And** the Filbert executable resolves Sparkle from `Contents/Frameworks` without referring to a checkout or `.build` path
- **And** nested executable code is signed inside-out with the same Developer ID team before the outer app is sealed
- **And** the exact mounted-DMG app passes strict code-signature verification, Gatekeeper assessment, stapler validation, framework linkage inspection, and a launch smoke test
- **And** local ad-hoc packaging remains available for development without gaining access to release secrets.

### AC10: Feed publication is ordered and stable-only

- **Given** a non-draft, non-prerelease `v<version>` GitHub Release triggers the release workflow
- **When** the signed and notarized DMG has passed all existing release checks
- **Then** the workflow signs the exact DMG with Sparkle's EdDSA private key
- **And** it uploads the DMG, SHA-256 file, and generated release notes before generating the appcast entry
- **And** the appcast entry contains the bare installed version, exact-tag download URL, artifact length, EdDSA signature, publication date, and release notes
- **And** a separate GitHub Pages deployment publishes the appcast only after every preceding release and update-signing step succeeds
- **And** a failed build, notarization, upload, signature, appcast validation, or Pages deployment leaves the previously published valid appcast available
- **But Given** a draft or prerelease is created
- **When** its workflow runs
- **Then** it does not replace or add an entry to the stable appcast.

### AC11: The first updater-capable release has an explicit bootstrap

- **Given** an installed Filbert version predates Sparkle integration
- **When** the first updater-capable release is published
- **Then** existing users are told that this one release still requires manual installation from GitHub
- **And** the release notes explain that automatic updates begin with that installed version
- **And** no claim implies that a binary without updater code can discover the new feed
- **And** all later supported installed releases can reach the newest compatible stable release through the appcast even if one or more intermediate versions were skipped.

### AC12: Update publication and installation are verifiable

- **Given** the implementation is ready for review
- **When** repository validation runs
- **Then** formatting, lint, debug build, release build, and all unit tests pass
- **And** focused tests cover installed-versus-development updater eligibility, update-settings presentation, canonical feed and acknowledgement data, and disabled manual actions
- **And** workflow validation checks stable/prerelease gating, exact-tag artifact URLs, required appcast fields, and refusal to publish without the Sparkle private key
- **And** an ad-hoc packaged build proves that framework linkage contains no build-machine path and that the app launches
- **But Given** two consecutively signed and notarized test or public versions are available
- **When** the older version discovers and installs the newer version through the published feed
- **Then** EdDSA verification, download, replacement, relaunch, reported version, settings preservation, and Keychain preservation are checked on a clean macOS user account before the feature is declared complete.

## Plan

1. Add a pinned Sparkle 2 package dependency to the App target only. Introduce one small App-layer update coordinator that owns `SPUStandardUpdaterController`, determines whether the host is an installed release bundle, and exposes only the state and actions needed by SwiftUI.
2. Configure the feed URL, EdDSA public key, four-hour interval, automatic checks, and automatic downloads through `packaging/Info.plist`, using Sparkle's settings as the single scheduling and preference source. Keep development and test hosts offline by declining to start the updater when installed-bundle metadata is invalid.
3. Extend About settings with a manual check action and native automatic-check and automatic-download controls. Bind them to Sparkle's updater settings, localize all new prose, and update acknowledgements for the shipped Sparkle framework and MIT license.
4. Update the custom bundle assembly to copy Sparkle with symlinks intact, add the portable executable runtime search path, and sign nested Sparkle code inside-out according to Sparkle's packaging guidance. Extend release verification to inspect linkage and launch the mounted-DMG app while preserving all checks from (ci 05).
5. Generate a dedicated Sparkle EdDSA key pair. Embed only the public key; store the private key as a new protected `release-signing` environment secret and ensure it is scoped to the signing/appcast step, never logged, persisted as an artifact, or committed.
6. Extend the release workflow to sign the verified DMG, generate and validate a stable appcast entry with an exact-tag asset URL, and pass the static site as a workflow artifact to a dependent GitHub Pages deployment job. Gate feed publication on stable releases and successful artifact upload so release failures cannot overwrite the previous feed.
7. Add focused unit and workflow tests plus packaging assertions for updater eligibility, settings state, acknowledgements, release gating, appcast contents, symlink preservation, portable linkage, and nested signatures. Do not make unit tests depend on live GitHub or Apple services.
8. Add `docs/automatic-updates.md` with one-time GitHub Pages and secret setup, the normal release sequence, the first-release bootstrap, independent appcast and artifact checks, failed-release recovery, private-key backup and rotation, Developer ID rotation interaction, and the two-version end-to-end test procedure.

## Risks

- Sparkle contains nested frameworks and helper executables. The current hand-built bundle and broad `codesign --deep` call are not enough evidence of correct inside-out signing; a bad copy or signing order can break linkage, notarization, or installation.
- The Sparkle private key becomes a release credential. Disclosure would let an attacker sign a malicious update feed artifact, while loss without backup could block updates from existing installations.
- Rotating the embedded EdDSA key or Developer ID identity can strand older clients if the transition is not shipped and tested in the supported order. The maintainer guide must treat rotation as a release migration rather than a secret replacement.
- GitHub Pages is externally hosted infrastructure even though Filbert operates no server. An outage must degrade to the installed version, and feed authenticity must rely on EdDSA rather than hosting trust alone.
- GitHub Pages deployment permissions and the existing `release-signing` environment have different trust purposes. A dependent deployment job must receive only the generated static artifact, not signing or notarization secrets.
- The GitHub Release becomes public before the current workflow finishes building its assets. Keeping the old Pages feed until the workflow succeeds avoids breaking installed clients, but the release page can still temporarily lack its DMG as described in (ci 05).
- Enabling background checks by default makes a periodic HTTPS request that reveals normal connection metadata to GitHub. The controls must be visible and must stop scheduled checks when disabled.
- Automatic installation can require authorization when the app is in a protected location or can be delayed while Filbert remains open. The UI must not promise a specific install time and must rely on Sparkle's supported authorization flow.
- A malformed version or prerelease entry could send stable users to the wrong build. Feed generation must use the stamped bundle version, reject placeholders and mismatches, and gate on GitHub release metadata rather than tag shape alone.
- The first Sparkle-enabled release cannot update clients that do not yet contain Sparkle. That one-time manual installation must be communicated clearly.
- Live update replacement cannot be proven by unit tests or an ad-hoc build alone. Completion depends on a clean-account test using two artifacts signed by the same release trust chain.

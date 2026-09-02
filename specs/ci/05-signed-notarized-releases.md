## Objective

Publish every Filbert GitHub Release as a Developer ID-signed and Apple-notarized DMG that opens normally under Gatekeeper without an unsigned-build workaround.

## Context

- `.github/workflows/release.yml` — currently publishes a release without providing the signing credentials already recognized by the build script.
- `scripts/build-dmg.sh` — contains a dormant Developer ID lane, but it silently falls back to an ad-hoc-signed release when credentials are missing and tries to submit a bare `.app` to a service that requires a ZIP, DMG, or signed installer package.
- `README.md` — currently tells users how to bypass Gatekeeper for unsigned releases.
- `docs/signing-and-notarization.md` — new maintainer guide for creating, storing, rotating, and using the Apple credentials.
- Extends the direct-distribution pipeline from (ci 02) and preserves the resource-bundle repair from (ci 03).
- Filbert is distributed in a DMG rather than a package, so it needs one **Developer ID Application** certificate. It does not need a Developer ID Installer certificate or a provisioning profile for its current entitlements.

## Acceptance Criteria

### AC1 [x]: Public releases require signing

- **Given** a GitHub Release on a `v*` tag is published
- **When** the release workflow starts
- **Then** it explicitly requires the complete Developer ID and notarization credential set
- **And** a missing or empty credential fails the job before the DMG is built or uploaded
- **And** the public release workflow cannot silently select the ad-hoc signing lane
- **And** local maintainers can still request an ad-hoc build explicitly for development without gaining access to release credentials

### AC2 [x]: The app has a valid Developer ID signature

- **Given** the release workflow has imported the password-protected PKCS#12 certificate into a temporary keychain
- **When** it signs `Filbert.app`
- **Then** it uses the `Developer ID Application` identity for the configured Apple Developer team
- **And** it enables the hardened runtime, applies `packaging/Filbert.entitlements`, and requests Apple's trusted timestamp
- **And** strict deep signature verification passes before notarization
- **And** the resolved certificate identity and Team ID are checked so a different valid identity cannot be selected accidentally

### AC3 [x]: The app and DMG are notarized and stapled

- **Given** `Filbert.app` has passed Developer ID signature verification
- **When** the release pipeline submits it to Apple's notary service
- **Then** it first wraps the app in a temporary ZIP that preserves the bundle and submits that supported container with `notarytool --wait`
- **And** an accepted ticket is stapled to and validated on `Filbert.app` before the DMG is created
- **And** the DMG containing that app is submitted separately, accepted, stapled, and validated
- **And** a rejected, invalid, or interrupted submission prints the corresponding notary log when an ID is available and fails the job
- **And** no unnotarized DMG is uploaded to GitHub

### AC4 [x]: The published artifact passes Gatekeeper checks

- **Given** the signed and notarized DMG has been created
- **When** the workflow verifies the exact artifact that it will upload
- **Then** the app copied from the mounted DMG passes `codesign --verify --deep --strict`
- **And** the app passes `spctl --assess --type execute`
- **And** the app and DMG stapled tickets pass `stapler validate`
- **And** the DMG, its SHA-256 checksum, and signed-release notes are uploaded only after all checks pass

### AC5 [x]: CI credentials are scoped and cleaned up

- **Given** the maintainer has configured the `release-signing` GitHub Environment
- **When** the release job runs in that environment
- **Then** the workflow maps the six documented environment secrets to the build process without printing their values
- **And** the certificate and private key exist only in a randomly passworded temporary keychain on the ephemeral runner
- **And** temporary certificate files, archives, and the keychain are removed on success or failure
- **And** the `.p12`, its password, the app-specific password, and decoded private-key material are never committed or uploaded as build artifacts

### AC6 [x]: User-facing installation text assumes a notarized release

- **Given** a user reads `README.md` or the generated notes on a GitHub Release
- **When** they follow the installation instructions
- **Then** they are told to mount the DMG, drag Filbert to `/Applications`, and launch it normally
- **And** they are not told to run `xattr`, bypass Gatekeeper, or use the unsigned-app right-click workaround
- **And** the text does not promise that macOS shows no dialog, because the normal downloaded-app confirmation may still appear
- **And** local ad-hoc builds remain clearly distinguished from official GitHub Release artifacts

### AC7 [x]: A beginner can configure Apple and GitHub from the maintainer guide

- **Given** the maintainer has an active Apple Developer Program membership but no signing experience
- **When** they follow `docs/signing-and-notarization.md` from the beginning
- **Then** the guide gives exact navigation and field choices for creating a certificate signing request, issuing a Developer ID Application certificate, installing it with its private key, and exporting a password-protected `.p12`
- **And** it explains how to find the Team ID and full signing identity
- **And** it gives exact navigation for enabling two-factor authentication and creating a dedicated app-specific password for `notarytool`
- **And** it gives exact GitHub navigation for creating the `release-signing` Environment and all six required secrets
- **And** it includes a table that distinguishes the certificate, private key, `.p12`, `.p12` password, Team ID, identity name, Apple Account email, and app-specific password
- **And** it explicitly states that Base64 encoding is transport encoding rather than encryption, that no provisioning profile or Developer ID Installer certificate is needed, and that the Apple Account's normal password must never be stored in GitHub
- **And** it covers secure backup, certificate expiration, credential rotation, app-specific-password revocation, and the response to a suspected private-key leak

### AC8: The first notarized release has an end-to-end checklist

- **Given** the implementation and GitHub Environment configuration are complete
- **When** the maintainer follows the guide's first-release checklist
- **Then** they publish a `v*` GitHub Release, watch the `Release` workflow complete, and find the versioned DMG and checksum attached
- **And** they test a fresh browser download on a Mac, confirm Filbert launches from `/Applications` without a bypass, and verify the displayed Developer ID
- **And** the guide includes diagnostic steps for a missing secret, failed certificate import, invalid app-specific password, rejected notarization, failed stapling, and failed Gatekeeper assessment

## Plan

1. Add an explicit release-signing requirement to `scripts/build-dmg.sh`. Keep `--no-sign` for local development, but make the release workflow call a mode that fails closed when any of these values is absent: `APPLE_DEVELOPER_ID_P12`, `APPLE_DEVELOPER_ID_P12_PASSWORD`, `APPLE_DEVELOPER_ID_TEAM_ID`, `APPLE_DEVELOPER_ID_NAME`, `APP_NOTARY_APPLE_ID`, and `APP_NOTARY_APP_SPECIFIC_PASSWORD`.
2. Attach the release job to a `release-signing` GitHub Environment and map its six secrets only into the DMG build step. Preserve the existing `GITHUB_TOKEN` use for release uploads.
3. Harden temporary-keychain import and identity selection. Confirm that the selected `Developer ID Application` identity belongs to the configured Team ID before signing.
4. Replace bare-app submission with the supported sequence: sign app, verify app, create a temporary `ditto` ZIP, notarize ZIP, staple app, create DMG, notarize DMG, staple DMG, then verify the mounted release artifact. Reuse one notarization function and one authentication path for both submissions.
5. Make `notarytool` status handling explicit. Capture the submission ID, require an `Accepted` result, fetch the log on every non-accepted result, and do not treat a successful `stapler` call as proof that submission succeeded.
6. Update generated release notes and `README.md` to describe normal installation. Keep local ad-hoc builds available, but prevent their notes or artifacts from reaching the official release workflow.
7. Add `docs/signing-and-notarization.md` with an artifact inventory, click-by-click Apple Developer and GitHub setup, local credential checks, first-release procedure, independent verification, troubleshooting, backup, and rotation. Link only to Apple's and GitHub's official documentation for steps that can change.

## Risks

- The existing signed lane has not produced a public artifact. Certificate import, identity matching, hardened-runtime compatibility, and notarization must be proven by a real CI run.
- Publishing the GitHub Release triggers the job, so a credential or Apple-service failure can temporarily leave a public release without its DMG. The workflow must fail before upload and the guide must explain how to rerun after correction.
- App-specific passwords are revoked when the Apple Account password is changed or reset. The release then fails closed until the GitHub secret is replaced.
- A Developer ID private key is a high-value release credential. Base64 does not protect it; access to GitHub Environment administration and secure offline backup must stay limited.
- Notarizing both the app ZIP and DMG makes offline ticket validation stronger but adds a second Apple submission and increases release time.
- A normal first-open confirmation can still appear for software downloaded from the internet. Success means Gatekeeper identifies the developer and permits normal launch, not that macOS is completely silent.

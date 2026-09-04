# Automatic updates

Filbert uses Sparkle 2 to discover and install stable releases. The appcast is
a static file served by GitHub Pages, and each DMG is also signed with Sparkle's
EdDSA key. Apple Developer ID signing and notarization remain separate trust
checks. The application never needs a GitHub token or an update server.

## One-time setup

### Enable GitHub Pages

1. Open the repository's **Settings → Pages**.
2. Select **GitHub Actions** as the source.
3. Keep the Pages environment name as `github-pages`.
4. Confirm that the public URL is
   `https://victorhqc.github.io/filbert/appcast.xml`.

The `publish-pages` job has Pages write and OIDC permissions only. It receives
the generated appcast as an Actions artifact after the release job succeeds; it
does not receive Apple or Sparkle signing credentials.

### Create and protect the Sparkle key

Download the Sparkle package that matches the pinned `2.9.6` dependency. Its
`bin` directory contains `generate_keys`, `sign_update`, and
`generate_appcast`.

On a trusted Mac, generate one key for Filbert and keep the private export
outside the repository:

```sh
umask 077
SPARKLE_BIN=/path/to/Sparkle/bin
PRIVATE_KEY="$(mktemp)"
trap 'rm -f "$PRIVATE_KEY"' EXIT

"$SPARKLE_BIN/generate_keys" --account filbert
"$SPARKLE_BIN/generate_keys" --account filbert -p
"$SPARKLE_BIN/generate_keys" --account filbert -x "$PRIVATE_KEY"
```

Save the public value printed by `-p` as the `SPARKLE_PUBLIC_ED_KEY` **Actions
environment variable** in `release-signing`. Store the exported private value
as the `SPARKLE_PRIVATE_KEY` **environment secret** in the same environment.
For example, with GitHub CLI:

```sh
gh variable set SPARKLE_PUBLIC_ED_KEY --env release-signing --body "$PUBLIC_KEY"
gh secret set SPARKLE_PRIVATE_KEY --env release-signing < "$PRIVATE_KEY"
```

Generate both values from a single `generate_keys` run. They are a matched
pair: the workflow verifies the generated enclosure and feed signatures
against `SPARKLE_PUBLIC_ED_KEY` — the same key embedded in shipped apps — so a
private key from a different generation fails the release instead of
publishing a feed no installed client trusts.

Do not commit either value. The public key is embedded in the release
`Info.plist`; the private key is read through standard input by
`generate_appcast`, is never written by the workflow, and is never included in
an artifact or log. Keep an encrypted offline backup of the private key. Losing
it prevents existing installations from accepting future updates.

The same `release-signing` environment must also contain the six Apple secrets
listed in [Signing and notarization](signing-and-notarization.md). Limit who can
edit this environment and require an approval for its deployments.

## How a release is published

Only a published, non-draft, non-prerelease release with a plain `vX.Y.Z`
tag (no prerelease or build suffix) can publish the stable appcast.

1. Create a draft release with a `v<version>` tag.
2. Before the first updater-capable release, set
   `BOOTSTRAP_UPDATE_RELEASE` to `true` in the `release-signing` environment.
   Its generated notes tell users of older Filbert versions to install this
   release manually:

   ```sh
   gh variable set BOOTSTRAP_UPDATE_RELEASE --env release-signing --body true
   ```
3. Publish the release. Publishing, rather than pushing a bare tag, starts the
   workflow.
4. The workflow builds the arm64 app, embeds the public key and feed URL, and
   runs the existing Developer ID signing, notarization, stapling, and mounted
   DMG verification checks.
5. After those checks pass, it uploads the exact DMG, its SHA-256 file, and
   generated release notes to that exact GitHub Release tag.
6. It generates an appcast entry whose enclosure points to the versioned
   `releases/download/<tag>/...dmg` URL. It does not use the mutable `latest`
   URL.
7. The appcast validator checks the installed version, release version, asset
   URL, byte length, MIME type, publication date, release notes, and EdDSA
   signature — including verifying the enclosure and feed signatures against
   the public key embedded in shipped apps.
8. A dependent job uploads only the static appcast directory to GitHub Pages.

After the first updater-capable release has been manually installed and
verified, remove the `BOOTSTRAP_UPDATE_RELEASE` environment variable. Do not claim that a
pre-Sparkle binary can update itself: it has no updater code or trusted feed
configuration. Every later Sparkle-capable release can skip intermediate
versions because Sparkle compares the advertised version with the installed
version.

The feed advertises only the newest stable release. Older releases stay
attached to their exact GitHub Release tags, so a client that cannot run the
newest release (for example, after a minimum-macOS increase) keeps its current
version and can always install any older build manually.

## User behavior

Installed release bundles start one `SPUStandardUpdaterController` for the
application lifetime. Sparkle owns the persisted last-check date, four-hour
interval, automatic-check setting, and automatic-download setting. Reopening
Filbert does not create a second timer or reset that schedule.

The **About → Updates** card provides:

- **Check for Updates…**, which starts a user-initiated Sparkle check even when
  automatic checks are disabled or not yet due.
- **Check for updates automatically**, independent of downloads.
- **Download updates automatically**, enabled only when Sparkle allows that
  setting.

The standard Sparkle interface shows release notes and offers **Install and
Relaunch**. A background check never quits or relaunches Filbert by itself. If
installation is deferred, Sparkle can apply it at its supported safe quit
boundary. Settings, provider configuration, and Keychain items live outside
the application bundle and are preserved.

Development executables, test hosts, and bundles with a missing or placeholder
version, feed URL, or EdDSA key do not start Sparkle. This keeps `swift run`,
unit tests, and local unbundled launches offline from the updater path.

## Independent verification

Check the published feed without relying on the application:

```sh
curl --fail --location \
  https://victorhqc.github.io/filbert/appcast.xml
curl --fail --location --remote-name \
  https://github.com/victorhqc/filbert/releases/download/v<version>/Filbert-<version>-arm64.dmg
curl --fail --location --remote-name \
  https://github.com/victorhqc/filbert/releases/download/v<version>/Filbert-<version>-arm64.dmg.sha256
shasum -a 256 -c Filbert-<version>-arm64.dmg.sha256
```

The appcast's `enclosure` URL must be the exact versioned asset URL, and its
`length` must equal the downloaded DMG's byte count. The `sparkle:edSignature`
attribute is the authenticated update check; SHA-256 is useful for a human
transport check but cannot replace EdDSA authentication.

For a downloaded release, mount the DMG and run:

```sh
codesign --verify --deep --strict --verbose=4 /Volumes/Filbert\ */Filbert.app
spctl --assess --type execute -vv /Volumes/Filbert\ */Filbert.app
xcrun stapler validate /Volumes/Filbert\ */Filbert.app
otool -L /Volumes/Filbert\ */Filbert.app/Contents/MacOS/Filbert
```

The linkage output must reference `@rpath/Sparkle.framework`, never a checkout
or `.build` path. The framework must contain its version and binary symlinks,
the XPC services, `Autoupdate`, and `Updater.app`.

## Recovery

If a release build, notarization, artifact upload, signature, appcast
validation, or Pages deployment fails, the Pages job does not run. The
previous valid appcast remains available. Fix the cause and rerun the complete
release workflow. The release asset upload is idempotent and uses `--clobber`.

If the appcast host is unavailable, Sparkle leaves Filbert running with its
current version and data. A later scheduled check or an explicit manual check
can recover. If a malformed feed is published, restore the previous
`appcast.xml` from the successful workflow artifact or publish a corrected
stable release; never replace the feed with an unsigned hand edit.

## Key rotation

### Sparkle EdDSA key

An installed bundle trusts the public key embedded in that bundle. Replacing
the GitHub secret alone strands all installed versions that contain the old
public key. Use a two-release migration:

1. Keep the old key in the appcast and publish an updater-capable bridge release
   signed with the old key.
2. Ship the new public key in that bridge release and verify that it can still
   install an update signed by the old key.
3. For the following release, switch the appcast signing secret to the new
   private key and verify the bridge installs it.
4. Keep both private-key backups until every supported release has crossed the
   migration boundary.

If an EdDSA private key may have leaked, stop publishing, preserve the last
known-good feed, generate a new pair, and plan the bridge migration. Treat the
old key as compromised rather than trying to hide the incident in a workflow
log.

### Developer ID identity

Renewing or rotating the Developer ID certificate does not replace the Sparkle
key. Keep the same Sparkle key while the new Apple identity is introduced, and
verify that both the old and new signed apps pass Gatekeeper and Sparkle
installation. Do not revoke an uncompromised old Developer ID certificate
until supported previously published releases no longer need to launch or
install.

## Two-version end-to-end test

After two consecutive signed and notarized releases exist:

1. Create a clean macOS user account with no Filbert preferences or Keychain
   items.
2. Download and manually install the older release from its exact GitHub
   Release asset.
3. Add a provider configuration and a harmless test Keychain item, then record
   the settings.
4. Launch the older release from `/Applications`, wait for or manually start a
   check, and confirm that the feed finds the newer stable release.
5. Confirm the standard release-note UI, EdDSA verification, download, and
   **Install and Relaunch** flow.
6. Verify that the relaunched app reports the newer advertised version.
7. Verify the provider settings, preferences, and Keychain items survived.
8. Repeat with automatic downloads enabled and confirm that a background
   discovery does not terminate or relaunch Filbert without user action.

This clean-account test is the evidence for live replacement. Unit tests,
workflow tests, and ad-hoc packaging checks cannot prove the complete
download, authorization, replacement, relaunch, and settings-preservation
path.

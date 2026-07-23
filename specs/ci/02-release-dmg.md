## Objective

Ship the app as an unsigned arm64 `.dmg` generated automatically when a
maintainer publishes a GitHub Release — with the Claude Code helper install
remaining an in-app action and signing/notarization deferred to a future
spec pending legal review.

## Context

- `Package.swift` — the app is an SPM `executableTarget` named `App`. There
  is no `.xcodeproj` and no existing packaging step, so the entire build-to-
  DMG pipeline is new.
- `Sources/Providers/ClaudeCode/Resources/statusline_helper.swift` — the
  helper **source** is shipped inside the app bundle and compiled to a native
  binary on demand by `swiftc` at "Install Helper" time (providers 02 Plan
  §5). This means the DMG must preserve `Bundle.module` resource discovery;
  it rules out a flat-binary distribution and rules in a packaged `.app`.
- `Sources/App/AppMain.swift` + `LSUIElement` menu-bar lifecycle (per
  `README.md` §"What it is") — the app is a menu-bar-only `LSUIElement`
  with no Dock icon, which affects how `create-dmg` presentation but not the
  build itself.
- `scripts/build-dmg.sh` — the single entry point for both local and CI
  builds. Implements the full unsigned pipeline (build → assemble → ad-hoc
  sign → DMG → verify → release notes). It also contains a dormant
  Developer ID signing + notarization lane (see Future Work) that activates
  automatically when six named env vars are present; this spec does not
  exercise that lane.
- `packaging/Info.plist`, `packaging/Filbert.entitlements` — build metadata
  consumed by `scripts/build-dmg.sh`. Lives outside `Sources/` because SPM
  would otherwise bundle them inside the shipped app.
- Builds on (ci 01): the release pipeline runs **after** a green `validate`
  job. The same `macos-14` runner and toolchain baseline apply.
- Builds on (providers 02 AC8, AC11): the `~/.claude/settings.json` mutate
  path is owned by the app at runtime. The installer **must not** touch
  `~/.claude` — that is the user's opt-in decision, made in Settings (ui 05).

## Why a DMG and not a PKG / installer

- The Claude Code integration has no system-level prerequisites an installer
  could satisfy: the `claude` CLI is installed by the user via Anthropic's
  install script, `swiftc` is the user's Xcode CLT, and `~/.claude/...` is
  written lazily when the user clicks "Install Helper". An installer that
  ran any of these at install time would (a) race against user intent, (b)
  need elevated privileges the app otherwise never needs, and (c) duplicate
  state between the installer and the in-app Install Helper button.
- The remaining distribution concerns — the drag-to-/Applications affordance
  and a clean container for the unsigned-build workaround instructions — are
  fully addressed by a DMG. A `.pkg` would add complexity (postinstall
  scripts, receipt tracking) for no gain.

## Architecture scope (locked by this spec)

- **arm64 only, for now.** The first release targets Apple Silicon. The DMG
  filename suffix is `-arm64`. A future universal build (arm64 + x86_64)
  is a separate spec; this one does not block on it. The README's Intel note
  ("capable of running Sonoma are supported but not the primary target")
  already documents this stance to users.
- **Release-triggered generation.** Publishing a GitHub Release on a `v*`
  tag automatically builds and uploads the DMG. A bare `git push --tags`
  does nothing — the maintainer must publish a release (via GitHub's UI or
  `gh release create`) to fire the pipeline. This is deliberate: it makes
  releases opt-in and avoids accidental cuts from routine tag pushes.
- **Unsigned, for now.** The first releases are ad-hoc signed only — they
  run on the maintainer's own machine without re-signing, but they trip
  Gatekeeper for end users, who must use the right-click → Open workaround
  (documented in AC10 and the release body). Signed + notarized builds
  require a paid Apple Developer Program membership, which is itself blocked
  on a legal review (see Future Work). The conditional signing lane in
  `scripts/build-dmg.sh` is dormant code, retained so the future signing
  spec is a config change rather than a rewrite.
- The Mac App Store is explicitly out of scope: the app spawns
  subprocesses (`claude`, `swiftc`), writes outside its container
  (`~/.claude/`), and reads Keychain items it creates at runtime — all of
  which are incompatible with the App Sandbox as currently designed.

## Acceptance Criteria

### AC0: The pipeline produces a working unsigned DMG

- **Given** a maintainer publishes a GitHub Release on a `v*` tag (see
  AC7)
- **When** the release workflow runs
- **Then** the build job produces `Filbert-<version>-arm64.dmg` containing
  a launchable `Filbert.app` (per AC1, AC4)
- **And** the bundle is ad-hoc signed
  (`codesign -s - --force --deep --options runtime`) so it runs on the
  maintainer's own machine without re-signing
- **And** the DMG is uploaded to the GitHub Release as an asset, with a
  clear note in the release body that this is an **unsigned** build and
  users must right-click → Open (or
  `xattr -cr '/Applications/Filbert.app'`) on first launch

### AC1: Release produces a runnable `.app` bundle

- **Given** a tagged release triggers the release workflow
- **When** the build job finishes
- **Then** the runner has produced `Filbert.app` with the standard macOS
  bundle layout (`Contents/MacOS/Filbert`, `Contents/Resources/`, an
  `Info.plist` declaring `LSUIElement=true`, `CFBundleIdentifier`, and the
  macOS 14 deployment target)
- **And** the bundle is built **arm64 only**
  (`swift build -c release --arch arm64`), matching the architecture scope
  above
- **And** the helper source `statusline_helper.swift` is present under
  `Contents/Resources/` so `Bundle.module.url(forResource:withExtension:)`
  resolves at "Install Helper" time (providers 02 Plan §5)
- **And** the bundle launches without a Swift toolchain installed on the
  end-user machine (no `swift run` dependency at runtime — the binary is
  statically self-contained for its own code; only the *helper* compile
  needs `swiftc`)

### AC4: The `.app` is packaged into an arm64 `.dmg`

- **Given** the ad-hoc-signed bundle from AC1
- **When** the DMG step runs
- **Then** a read-only DMG named `Filbert-<version>-arm64.dmg` is
  produced via `create-dmg` (a hard dependency — see Plan §3)
- **And** the DMG presents the conventional "drag to /Applications"
  layout: `Filbert.app` alongside an `/Applications` symlink
- **And** the GitHub Release body notes the first-launch workaround (see
  AC10)

### AC5: The DMG is published as a release asset and verified

- **Given** the DMG from AC4
- **When** the release job uploads it
- **Then** the DMG is attached to the GitHub Release for the triggering
  tag, with a SHA-256 checksum file alongside
  (`Filbert-<version>-<arch>.dmg.sha256`)
- **And** a verification step mounts the DMG, copies the `.app` to a temp
  dir, and runs `codesign --verify --verbose=4` against the copy. The job
  fails if `codesign` errors. (`spctl --assess` is **not** invoked — it
  cannot pass for ad-hoc-signed binaries and would always fail this step.
  It returns in the future signing spec.)

### AC7: Release generation is fully automatic on GitHub Release publish

- **Given** the release workflow file
- **When** a maintainer publishes a GitHub Release whose tag matches `v*`
- **Then** the release job runs automatically, with **no further manual
  step** — it builds the DMG and uploads the assets to that GitHub Release
- **And** on any other event (push to branch, PR, bare tag push, draft
  release) the workflow does not run
- **And** re-running the workflow on the same release overwrites the
  existing assets (`gh release upload --clobber`) and refreshes the
  release body (`gh release edit --notes-file`), so re-publishing a
  release does not produce duplicate or stale assets

### AC8: Local reproducibility — a maintainer can produce an equivalent DMG

- **Given** a maintainer wants to test the release pipeline locally
- **When** they run the documented build script (`scripts/build-dmg.sh`,
  checked into the repo; requires `brew install create-dmg`)
- **Then** the same sequence — `swift build -c release`, `assemble-bundle`,
  `codesign -s -` (ad-hoc), `create-dmg` — runs end-to-end
- **And** CI runs the same script, so a green local run predicts a green
  release (mirrors the (ci 01) philosophy)

### AC10: The README documents installation and the unsigned-build workaround

- **Given** a user downloads the DMG from a GitHub Release
- **When** they open `README.md` looking for install instructions
- **Then** there is an "Installation" section that explains the
  drag-to-`/Applications` step from the mounted DMG
- **And** it documents the first-launch workaround: right-click → Open,
  or `xattr -cr '/Applications/Filbert.app'`
- **And** the section notes that signed + notarized builds are planned
  (see Future Work) and will not need the workaround
- **And** the section links to the GitHub Releases page rather than
  hard-coding a download URL, so it survives moving repos or renaming

### AC9: The Claude Code in-app flow is unchanged by distribution

- **Given** the user has installed Filbert from the DMG and opened it
- **When** they go to Settings → Claude Code → Install Helper
- **Then** the same installer path from (providers 02 AC7, AC8) runs:
  `Bundle.module.url(forResource: "statusline_helper",
  withExtension: "swift")` resolves against `Contents/Resources/`,
  `swiftc` is invoked to compile it to `~/.claude/filbert-statusline`,
  and `~/.claude/settings.json` is chained
- **And** no part of the DMG or its install step writes to `~/.claude/`
  — the distribution and the Claude Code integration remain orthogonal
- **And** a user who never opens Settings → Claude Code never has their
  `~/.claude/settings.json` touched, even after running Filbert

## Plan

Plan §1–4 are implemented in `scripts/build-dmg.sh`; §5 (release workflow)
is implemented in `.github/workflows/release.yml`; §6 (README) is
implemented in `README.md`'s Installation section. §7 is a guard, not a
work item.

1. **Bundle assembly.** Implemented in `scripts/build-dmg.sh` (function
   `assemble_bundle`). The script copies the SPM-built `App` executable
   into `Filbert.app/Contents/MacOS/Filbert`, copies the SPM-generated
   resource bundles (`filbert_App.bundle`,
   `filbert_ClaudeCodeProvider.bundle`, `filbert_Core.bundle`,
   `filbert_DeepSeekProvider.bundle`, `filbert_ZAIProvider.bundle`)
   verbatim into `Contents/Resources/`, copies `AppIcon.icns` to the top
   of `Contents/Resources/`, and generates `Contents/Info.plist` from
   `packaging/Info.plist` (substituting `@VERSION@`). Flattening the
   resources would break `Bundle.module` `forResource:withExtension:`
   lookups (providers 02 §5, AC9). This path (hand-assembled from
   `swift build -c release --arch arm64`) was chosen over generating an
   `.xcodeproj` because the app is small, SPM's `Bundle.module` layout
   is already correct, and a second Xcode project would violate (ci 01)'s
   "SPM is the source of truth" stance.
2. **Entitlements and Info.plist.** Both live under `packaging/`, not
   `Sources/App/Resources/`, because they are build metadata rather than
   app resources — keeping them out of `Sources/App/Resources/` prevents
   SPM from bundling the entitlements file inside the shipped app and
   keeps the Info.plist template from confusing SPM's resource
   processing. `packaging/Info.plist` is a template with an `@VERSION@`
   placeholder that `scripts/build-dmg.sh` substitutes; it declares
   `LSUIElement=true`, `CFBundleIdentifier`, and the macOS 14 deployment
   target (AC1). `packaging/Filbert.entitlements` is currently an empty
   `<dict>` — ad-hoc signing (`codesign -s -`) does not require any
   entitlements, and the app needs no special entitlements for its
   current behavior (Keychain access via
   `kSecAttrService`/`kSecAttrAccount` works without an access group;
   subprocess spawn and file writes outside the bundle are unrestricted
   without the App Sandbox).
3. **DMG packaging.** `create-dmg` (create-dmg/create-dmg on GitHub,
   `brew install create-dmg`) is a **hard dependency** for both local and
   CI builds. It produces the conventional drag-to-/Applications DMG that
   AC4 calls for — fixed window size, icon positioning, Applications
   drop-link — via a `.DS_Store` it synthesizes. There is no `hdiutil`
   fallback: reimplementing the `.DS_Store`/AppleScript layout logic by
   hand is not worth the maintenance, and `create-dmg` is the community
   standard. Output filename is always `Filbert-<version>-arm64.dmg`.
4. **Build script.** `scripts/build-dmg.sh` runs the entire pipeline.
   Flags in scope: `--version <semver>`, `--output <dir>`. The script
   also recognizes `--no-sign` and six signing env vars, but those are
   dormant (see Future Work). This script is the single entry point for
   both local and CI builds (AC8).
5. **GitHub Actions release workflow.** New file
   `.github/workflows/release.yml`, separate from (ci 01)'s `ci.yml`.
   - **Trigger.** `release: types: [published]` only. The release event
     has no tag-name filter, so the job is gated with
     `if: startsWith(github.event.release.tag_name, 'v')`. Bare tag
     pushes do nothing — the maintainer must publish a release to fire
     the pipeline (AC7). This avoids the double-fire problem
     (`push: tags` + `release: published` both firing when a release is
     created on a pushed tag) and the create-vs-upload ambiguity
     (`release: published` guarantees the release already exists when
     the workflow runs).
   - **Permissions.** `contents: write` (required by
     `gh release upload` and `gh release edit`).
   - **Concurrency.** One in-flight run per release; later runs cancel
     earlier ones (`cancel-in-progress: true`), mirroring (ci 01).
   - **Steps.** Checkout; install `create-dmg` via Homebrew; derive
     version from `${{ github.event.release.tag_name }}` (tag already
     exists by definition on a `release` event); run
     `scripts/build-dmg.sh --version <version> --output <dir>`; upload
     assets (`<dmg>`, `<dmg>.sha256`) via `gh release upload --clobber`;
     set the release body via
     `gh release edit --notes-file <dmg>.release-notes.md`. No
     `gh release create` — the trigger guarantees the release exists.
   - **No SwiftFormat/SwiftLint install.** `build-dmg.sh` runs
     `swift build -c release --arch arm64` only; it does not invoke
     `swift run` on any tool. Linting belongs to (ci 01)'s `validate`
     job, not this release job.
   - **No secrets wired** in this spec. The script's signing lane stays
     dormant (see Future Work).
6. **README and release body.**
   - **`README.md`** gets an "Installation" section (AC10) covering the
     unsigned-build workaround (right-click → Open, or
     `xattr -cr '/Applications/Filbert.app'`). The README is the
     durable, release-independent reference.
   - The **release body** is written by the script to
     `<dmg>.release-notes.md` and attached to the GitHub Release by the
     workflow (Plan §5). The note explains the unsigned-build state, the
     first-launch workaround, and that signed builds are planned. The
     note text is checked into the script, not generated by an LLM at
     release time.
7. **No changes to the Claude Code provider.** AC9 is a guard, not a
   work item: the spec asserts the distribution does not regress the
   in-app Install Helper flow. If during implementation we discover the
   bundle layout breaks `Bundle.module` resource discovery, that is a
   build-script bug (fix it in `scripts/build-dmg.sh`), not a provider
   change.

The remaining work (release.yml, README Installation section) waits for
spec review before implementation.

## Risks

- **Unsigned builds will trip Gatekeeper on end-user machines (AC0).**
  This is the explicit cost of shipping before an Apple Developer
  Program membership is acquired. The release-body note (Plan §6) and
  README (AC10) document the workaround, but some users will still
  bounce. Mitigation: accept this as the current state; the path to
  signed + notarized builds is described in Future Work.
- **The unsigned lane is the default until a legal review of paid
  distribution completes.** A paid Apple Developer Program membership in
  the maintainer's name, tied to a product that *may* eventually accept
  payment, creates a paper trail (tax/Gewerbe, visa-permitted economic
  activity in Germany) that should be reviewed with a lawyer/accountant
  before purchase. The unsigned lane lets us ship now without that
  commitment. There is **no cheaper in-between state worth pursuing**: a
  free Apple ID cannot sign for distribution, and ad-hoc signing
  (`codesign -s -`) produces the exact same user experience as no signing
  at all.
- **arm64-only excludes Intel Macs.** The README already documents Intel
  as secondary. A future universal build is a separate spec. If an Intel
  user lands before that spec ships, the answer is "build from source" —
  which CI already supports via (ci 01).
- **Bundle.module resource path drift.** (providers 02 Plan §5) relies on
  `Bundle.module` finding `statusline_helper.swift`. If the
  hand-assembled bundle (Plan §1) places resources under a different
  path than SPM does, the "Install Helper" button will fail at runtime
  with `InstallerError.helperSourceNotFound`. AC1 and AC9 both cover
  this; the verification step in AC5 catches it before release, not in
  production.
- **Translocation.** If a user double-clicks the DMG and runs the app
  from the mounted volume without dragging to `/Applications`, macOS runs
  it in a read-only random path ("App Translocation"), which can break
  the helper install (it writes to `~/.claude/`, which still works, but
  the bundle identity can be reported as "damaged" on some macOS
  versions). The drag-to-/Applications DMG layout (AC4) is the standard
  mitigation; we do not need a postinstall step.
- **Release workflow scope vs (ci 01).** (ci 01) owns the `validate` job
  on every push; this spec owns the `release` job on tags. They must not
  share a workflow file (different triggers, different permissions). If
  a maintainer later merges them, the triggers and permissions must
  remain isolated per job.

## Future Work

Signing and notarization are intentionally deferred from this spec. The
reasons and the path back are recorded here so the future spec has a
starting point.

- **Blocker.** A paid Apple Developer Program membership ($99/year) in
  the maintainer's name, tied to a product that may eventually accept
  payment, creates a paper trail (tax/Gewerbe, visa-permitted economic
  activity in Germany) that should be reviewed with a lawyer/accountant
  before purchase. Until that review completes, the unsigned lane is the
  only shipping path.
- **Implementation is already staged.** `scripts/build-dmg.sh` contains
  the full conditional signing + notarization + stapling lane, dormant.
  The lane activates automatically when six environment variables are
  all present: `APPLE_DEVELOPER_ID_P12` (base64),
  `APPLE_DEVELOPER_ID_P12_PASSWORD`, `APPLE_DEVELOPER_ID_TEAM_ID`,
  `APPLE_DEVELOPER_ID_NAME` (e.g. `"Developer ID Application: Victor
  Quiroz Castro"`), `APP_NOTARY_APPLE_ID`,
  `APP_NOTARY_APP_SPECIFIC_PASSWORD`. The flag `--no-sign` forces the
  unsigned lane regardless. The p12 is imported into a fresh keychain on
  the runner, used for signing, and the keychain is deleted on script
  exit. `notarytool submit` is invoked with `--apple-id`/`--team-id`/
  `--password` from env vars (we deliberately do **not** use create-dmg's
  `--codesign`/`--notarize` flags, which rely on a stored keychain
  profile and would mean two auth flows in one pipeline).
- **The future spec's work** is therefore mostly ops, not code:
  - Acquire the Apple Developer Program membership after legal review.
  - Add the six secrets to the repository (or a dedicated GitHub Actions
    Environment).
  - Wire the secrets into `.github/workflows/release.yml`'s `env:` block
    on the build job.
  - Add the `spctl --assess --type execute -vv` check to the AC5
    verification step (it is omitted in this spec because ad-hoc-signed
    binaries cannot pass it).
  - Update `README.md`'s Installation section to drop the
    unsigned-build workaround.
- **Risks the future spec must revisit:**
  - **Signing cert custody.** Anyone with write access to the repo can
    extract the p12 via a workflow change. Mitigation: restrict the
    release workflow to `main`; require PR review on
    `.github/workflows/release.yml`; rotate the cert if a maintainer
    leaves.
  - **`notarytool` can reject code we don't control.** If a future Swift
    runtime bundles a dylib that trips a notarization rule, the signed
    release lane blocks until we either update the toolchain or change
    the embedding strategy. The unsigned lane keeps shipping in the
    meantime.
  - **Keychain access group transition.** The Core Keychain wrapper uses
    `kSecAttrService`/`kSecAttrAccount` only — it does **not** pass
    `kSecAttrAccessGroup`. macOS therefore assigns items to whatever
    default access group the signing identity provides: none for ad-hoc
    signed builds (the current lane and all `swift run` development),
    `<TEAM_ID>.com.victorhqc.filbert` for Developer ID signed builds.
    The first signed release WILL make existing Keychain items
    invisible — users will need to re-enter their API keys. Mitigation
    options if this becomes a real pain: (a) document the one-time
    re-entry in the first signed release notes; (b) add a migration
    step that reads old items via a broad query (no group filter) and
    re-saves them; (c) pin `kSecAttrAccessGroup` explicitly in the
    Keychain wrapper and add a matching `application-groups` entitlement
    — but this requires the paid membership, so it cannot be done in the
    unsigned lane. The current stance accepts (a) as the cost of the
    unsigned → signed transition.

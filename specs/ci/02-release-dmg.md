## Objective

Ship the app as an arm64 `.dmg` generated automatically when a maintainer
pushes a tag or creates a GitHub Release, with Developer-ID signing and
notarization enabled automatically once those secrets are present — and
with the Claude Code helper install remaining an in-app action, not an
installer step.

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
- The remaining distribution concerns — Gatekeeper trust and the
  drag-to-/Applications affordance — are fully addressed by a signed,
  notarized DMG. A `.pkg` would add complexity (postinstall scripts, receipt
  tracking) for no gain.

## Architecture scope (locked by this spec)

- **arm64 only, for now.** The first release targets Apple Silicon. The DMG
  filename suffix is `-arm64`. A future universal build (arm64 + x86_64)
  is a separate spec; this one does not block on it. The README's Intel note
  ("capable of running Sonoma are supported but not the primary target")
  already documents this stance to users.
- **Tag-triggered release generation.** Pushing a `v*` tag (or creating a
  GitHub Release on such a tag) automatically builds and uploads the DMG.
  There is no manual release step beyond `git tag` + `git push --tags`.
- **Conditional signing lane.** The pipeline produces a usable DMG with zero
  Apple Developer Program membership, and **auto-upgrades** to signed +
  notarized output the moment the required secrets are present in the
  repository. This lets us cut releases today and flip the signing bit once
  an Apple Developer Program membership ($99/year) is acquired.
- The Mac App Store is explicitly out of scope: the app spawns
  subprocesses (`claude`, `swiftc`), writes outside its container
  (`~/.claude/`), and reads Keychain items it creates at runtime — all of
  which are incompatible with the App Sandbox as currently designed.

## Acceptance Criteria

### AC0: The pipeline produces a working unsigned DMG with no secrets set

- **Given** the repository has **no** signing/notarization secrets
  configured
- **When** a tag is pushed (see AC7)
- **Then** the build job still produces `AI-Usage-<version>-arm64.dmg`
  containing a launchable `AI Usage.app` (per AC1, AC4)
- **And** the bundle is ad-hoc signed
  (`codesign -s - --force --deep --options runtime`) so it runs on the
  maintainer's own machine without re-signing
- **And** the DMG is uploaded to the GitHub Release as an asset, with a
  clear note in the release body that this is an **unsigned** build and
  users must right-click → Open (or
  `xattr -cr '/Applications/AI Usage.app'`) on first launch
- **And** the signing/notarization steps (AC2, AC3, AC4's signing bullets)
  are **skipped**, not failed — the pipeline detects absence of secrets
  and takes the unsigned path

### AC1: Release produces a runnable `.app` bundle

- **Given** a tagged release triggers the release workflow
- **When** the build job finishes
- **Then** the runner has produced `AI Usage.app` with the standard macOS
  bundle layout (`Contents/MacOS/AI Usage`, `Contents/Resources/`, an
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

### AC2: When signing secrets are present, the `.app` is signed with a Developer ID Application certificate

- **Given** the bundle from AC1 **and** repository secrets
  `APPLE_DEVELOPER_ID_P12`, `APPLE_DEVELOPER_ID_P12_PASSWORD`,
  `APPLE_DEVELOPER_ID_TEAM_ID` are all set
- **When** the signing step runs
- **Then** the p12 is imported into a fresh keychain on the runner, and
  `codesign --deep --options runtime --entitlements <file> -s "Developer
  ID Application: <Name>"` is invoked against the bundle
- **And** `codesign --verify --verbose=4 "AI Usage.app"` succeeds
- **And** an entitlements file is checked in (e.g.
  `Sources/App/Resources/AIUsage.entitlements`) listing only what the app
  actually needs (Keychain access via
  `com.apple.security.application-groups` or per-item access groups; no
  App Sandbox entitlement — this is direct distribution, not MAS)
- **And** the Keychain access group matches the one used by the Core
  Keychain wrapper so existing keys continue to read after an upgrade
- **And** if any of the three signing secrets is **missing**, this step is
  skipped and the pipeline falls through to AC0's ad-hoc signing

### AC3: When notarization secrets are present, the signed `.app` is notarized and the ticket is stapled

- **Given** the signed bundle from AC2 **and** secrets
  `APP_NOTARY_APPLE_ID`, `APP_NOTARY_APP_SPECIFIC_PASSWORD`,
  `APPLE_DEVELOPER_ID_TEAM_ID` are all set
- **When** the notarization step runs
- **Then** the bundle is zipped and submitted via
  `xcrun notarytool submit --apple-id ... --team-id ... --password ...`
  with `--wait`
- **And** on success `xcrun stapler staple "AI Usage.app"` is invoked and
  `xcrun stapler validate "AI Usage.app"` exits zero
- **And** on notarization failure the job fails and surfaces the JSON log
  via `xcrun notarytool log` (no silent success on a rejection)
- **And** if AC2 was skipped (no signing secrets) or any notarization
  secret is missing, this step is skipped and the pipeline falls through
  to AC0's unsigned path

### AC4: The `.app` is packaged into an arm64 `.dmg`, signed and notarized when secrets allow

- **Given** the bundle from AC3 (signed + notarized) or AC0 (ad-hoc signed)
- **When** the DMG step runs
- **Then** a read-only DMG named `AI-Usage-<version>-arm64.dmg` is
  produced via `create-dmg` (or `hdiutil` with equivalent presentation)
- **And** the DMG presents the conventional "drag to /Applications"
  layout: `AI Usage.app` alongside an `/Applications` symlink
- **And** when signing + notarization secrets are present, the DMG itself
  is signed (`codesign -s "Developer ID Application: ..."`), notarized
  (`xcrun notarytool submit` on the `.dmg`), and stapled
  (`xcrun stapler staple`) so the downloaded DMG passes Gatekeeper before
  the user even mounts it
- **And** when secrets are absent, the DMG is produced without signing
  (AC0 path) and the GitHub Release body notes the first-launch
  workaround (see AC10)

### AC5: The DMG is published as a release asset and verified

- **Given** the DMG from AC4
- **When** the release job uploads it
- **Then** the DMG is attached to the GitHub Release for the triggering
  tag, with a SHA-256 checksum file alongside
  (`AI-Usage-<version>-<arch>.dmg.sha256`)
- **And** a verification step in CI mounts the DMG, copies the `.app` to a
  temp dir, runs `codesign --verify` and `spctl --assess --type execute
  -vv` against the copy, and fails the job if either errors

### AC6: Secrets are scoped to the release workflow, not pushed into the build

- **Given** signing and notarization require a certificate, an API key,
  and a team ID
- **When** the release workflow runs
- **Then** the Developer ID Application certificate (`base64`-encoded p12)
  is imported into a fresh macOS keychain in the runner, used for signing,
  and the keychain is deleted at job end
- **And** `notarytool` credentials come from repository secrets, never
  from the commit
- **And** no secret value is echoed to logs (the workflow uses
  `::add-mask::` or named secret inputs only)

### AC7: Release generation is fully automatic on tag push or GitHub Release creation

- **Given** the release workflow file
- **When** a maintainer pushes a tag matching `v*` OR creates a GitHub
  Release on such a tag (which implicitly pushes the tag if missing)
- **Then** the release job runs automatically, with **no further manual
  step** — it builds the DMG, signs/notarizes if secrets are present
  (AC2/AC3/AC4), and uploads the assets to the GitHub Release that
  triggered it
- **And** on any other event (push to branch, PR) the workflow does not
  run
- **And** re-running the workflow on the same tag updates the existing
  GitHub Release (it calls `gh release upload --clobber` rather than
  `gh release create`), so re-cutting a release does not produce
  duplicates

### AC8: Local reproducibility — a maintainer can produce an equivalent DMG

- **Given** the signing/notarization secrets are available locally (or
  `--skip-signing` is documented for unsigned local builds)
- **When** the maintainer runs the documented build script
  (`scripts/build-dmg.sh` or equivalent, checked into the repo)
- **Then** the same sequence — `swift build -c release`, `assemble-bundle`,
  `codesign`, `notarytool submit`, `stapler staple`, `create-dmg` — runs
  end-to-end
- **And** CI runs the same script, so a green local run predicts a green
  release (mirrors the (ci 01) philosophy)

### AC10: The README documents installation and the unsigned-build workaround

- **Given** a user downloads the DMG from a GitHub Release
- **When** they open `README.md` looking for install instructions
- **Then** there is an "Installation" section that explains the
  drag-to-`/Applications` step from the mounted DMG
- **And** for unsigned builds (the current state, per AC0), it documents
  the first-launch workaround: right-click → Open, or
  `xattr -cr '/Applications/AI Usage.app'`
- **And** the same section notes that signed + notarized builds (once the
  six secrets from Plan §8 are configured) launch with no workaround
- **And** the section links to the GitHub Releases page rather than
  hard-coding a download URL, so it survives moving repos or renaming

### AC9: The Claude Code in-app flow is unchanged by distribution

- **Given** the user has installed AI Usage from the DMG and opened it
- **When** they go to Settings → Claude Code → Install Helper
- **Then** the same installer path from (providers 02 AC7, AC8) runs:
  `Bundle.module.url(forResource: "statusline_helper",
  withExtension: "swift")` resolves against `Contents/Resources/`,
  `swiftc` is invoked to compile it to `~/.claude/ai-usage-statusline`,
  and `~/.claude/settings.json` is chained
- **And** no part of the DMG or its install step writes to `~/.claude/`
  — the distribution and the Claude Code integration remain orthogonal
- **And** a user who never opens Settings → Claude Code never has their
  `~/.claude/settings.json` touched, even after running AI Usage

## Plan

1. **Bundle assembly.** Decide between two viable paths and pick one:
   - **(A) Xcode project for release only.** Generate a minimal
     `AIUsage.xcodeproj` (or `.xcconfig`-driven `xcodebuild` invocation)
     that wraps the SPM `Package.swift`, sets `PRODUCT_BUNDLE_IDENTIFIER`,
     `LSUIElement`, the deployment target, and embeds
     `Sources/App/Resources/` plus the per-provider `Resources/` trees.
     This is the path most macOS menu-bar apps take because `xcodebuild`
     handles `Info.plist` synthesis, code signing, and bundle layout in
     one tool.
   - **(B) Hand-assembled bundle from `swift build -c release --arch
     arm64`.** Copy the release executable into
     `AI Usage.app/Contents/MacOS/AI Usage`, copy resources into
     `Contents/Resources/`, hand-write `Info.plist`. More transparent, no
     Xcode project file, but every bundle detail
     (`LSApplicationCategoryType`, embedded Swift runtime on older OSes,
     helper source discovery via `Bundle.module`) must be wired by hand.
   - **Recommendation: start with (B).** The app is small, the SPM
     `Bundle.module` resource layout is already correct, and avoiding a
     second Xcode project keeps (ci 01)'s "SPM is the source of truth"
     stance intact. Move to (A) only if (B) blocks notarization or hits a
     runtime issue we can't fix in shell.
2. **Entitlements.** Author `Sources/App/Resources/AIUsage.entitlements`
   with the minimal set — `com.apple.security.cs.allow-unsigned-executable-memory`
   only if Swift's runtime demands it; no sandbox. The Claude Code
   subprocess spawn and Keychain access are unrestricted on direct
   distribution, which is why we are not on the MAS. The same file is
   used for ad-hoc-signed local builds (AC0) and Developer ID builds
   (AC2).
3. **Conditional signing + notarization.** The release script probes for
   the secrets documented in Risks §8. **All six present** → full path:
   `codesign --deep --options runtime --entitlements ... -s "Developer
   ID Application: ..."`, then `notarytool submit --wait`, then
   `stapler staple`, applied to both the `.app` and the final `.dmg`.
   **Any missing** → ad-hoc sign (`codesign -s -`) and skip
   notarization, per AC0. The probe is a single `if` in the script, not
   duplicated per step.
4. **DMG packaging.** `create-dmg` (Homebrew) with a background image
   and the standard `/Applications` symlink. Output filename is always
   `AI-Usage-<version>-arm64.dmg` (arm64-only, per the architecture
   scope above). Sign + notarize + staple the DMG only on the signed
   lane.
5. **Build script.** `scripts/build-dmg.sh` runs the entire pipeline.
   Flags: `--version <semver>`, `--output <dir>`, `--no-sign` (forces
   the AC0 path even when secrets are present, useful for local test
   builds). The script **auto-detects** signing availability from the
   environment — CI never passes `--sign` explicitly; it just sets the
   secrets and the script picks the lane. This script is the single
   entry point for both local and CI builds (AC8).
6. **GitHub Actions release workflow.** New file
   `.github/workflows/release.yml`, separate from (ci 01)'s `ci.yml`.
   Triggers: `push: tags: ['v*']` and `release: types: [published]`
   (covers both the tag-push path and the GitHub-Release-UI path).
   Steps: checkout, install SwiftFormat/SwiftLint (for any build-time
   `swift run` deps), install `create-dmg` via Homebrew, run
   `scripts/build-dmg.sh --version <tag>`, upload artifacts to the
   triggering GitHub Release via `gh release upload --clobber`, run the
   AC5 verification step. **No conditionals in the workflow file** — the
   script owns the sign/no-sign lane decision, keeping the workflow
   declarative.
7. **Two surfaces carry install instructions: README and release body.**
   - **`README.md`** gets an "Installation" section (AC10) covering both
     lanes: the unsigned-build workaround (right-click → Open, or
     `xattr -cr '/Applications/AI Usage.app'`) and the note that signed +
     notarized builds need no workaround. The README is the durable,
     release-independent reference.
   - The **release body** is written by the workflow (see `scripts/build-dmg.sh`).
     **Signed lane:** one-line note that the DMG is signed + notarized,
     plus the SHA-256 checksum. **Unsigned lane:** a clear first-launch
     workaround block repeating the same `xattr -cr` command so a user
     who never opens the README still sees it. The note text is checked
     into the script, not generated by an LLM at release time.
8. **Secrets.** Required repository secrets, all optional until a
   Developer Program membership is acquired:
   `APPLE_DEVELOPER_ID_P12` (base64),
   `APPLE_DEVELOPER_ID_P12_PASSWORD`, `APPLE_DEVELOPER_ID_TEAM_ID`,
   `APP_NOTARY_APPLE_ID`, `APP_NOTARY_APP_SPECIFIC_PASSWORD`. A sixth
   key — `APPLE_DEVELOPER_ID_NAME` (e.g. `"Developer ID Application:
   Victor Quiroz Castro"`) — drives the `-s` argument. The presence of
   **all six** is the single condition that flips the script into the
   signed lane. Never document values; only document names.
9. **No changes to the Claude Code provider.** AC9 is a guard, not a
   work item: the spec asserts the distribution does not regress the
   in-app Install Helper flow. If during implementation we discover the
   bundle layout breaks `Bundle.module` resource discovery, that is a
   build-script bug (fix it in `scripts/build-dmg.sh`), not a provider
   change.

No code is written until this spec is reviewed.

## Risks

- **Unsigned builds will trip Gatekeeper on first launch (AC0).** This is
  the explicit cost of shipping before an Apple Developer Program
  membership is acquired. The release-body note (Plan §7) documents the
  workaround, but some users will still bounce. Mitigation: accept this as
  a transitional state; the moment all six secrets are set, the pipeline
  flips to signed + notarized with no code change.
- **The unsigned lane is the default until a legal review of paid
  distribution completes.** A paid Apple Developer Program membership in
  the maintainer's name, tied to a product that *may* eventually accept
  payment, creates a paper trail (tax/Gewerbe, visa-permitted economic
  activity in Germany) that should be reviewed with a lawyer/accountant
  before purchase. The unsigned lane lets us ship now without that
  commitment; the conditional flip (AC0 → AC2/AC3/AC4) means no rework
  is needed once the review completes. There is **no cheaper in-between
  state worth pursuing**: a free Apple ID cannot sign for distribution,
  and ad-hoc signing (`codesign -s -`) produces the exact same user
  experience as no signing at all.
- **arm64-only excludes Intel Macs.** The README already documents Intel
  as secondary. A future universal build is a separate spec. If an Intel
  user lands before that spec ships, the answer is "build from source" —
  which CI already supports via (ci 01).
- **Signing cert custody (signed lane only).** The Developer ID
  Application certificate is a high-value secret. Storing its `p12` in
  GitHub Actions secrets is the documented-acceptable approach, but
  anyone with write access to the repo can extract it via a workflow
  change. Mitigation: only `main` can run the release workflow; require
  PR review on `.github/workflows/release.yml`; rotate the cert if a
  maintainer leaves.
- **`notarytool` can reject code we don't control (signed lane).** If a
  future Swift runtime bundles a dylib that trips a notarization rule,
  the signed release lane blocks until we either update the toolchain or
  change the embedding strategy. The unsigned lane (AC0) keeps shipping
  in the meantime. Low probability, high blast radius — accepted.
- **Bundle.module resource path drift.** (providers 02 Plan §5) relies on
  `Bundle.module` finding `statusline_helper.swift`. If the hand-assembled
  bundle (Plan §1B) places resources under a different path than SPM does,
  the "Install Helper" button will fail at runtime with
  `InstallerError.helperSourceNotFound`. AC1 and AC9 both cover this; the
  verification step in AC5 catches it before release, not in production.
- **Translocation.** If a user double-clicks the DMG and runs the app
  from the mounted volume without dragging to `/Applications`, macOS runs
  it in a read-only random path ("App Translocation"), which can break
  the helper install (it writes to `~/.claude/`, which still works, but
  the signed-and-stapled bundle identity can be reported as "damaged" on
  some macOS versions). The drag-to-/Applications DMG layout (AC4) is
  the standard mitigation; we do not need a postinstall step.
- **Keychain access group stability.** AC2 requires the release
  entitlements' Keychain access group to match what the app used in
  development. If a user already stored a ZAI API key under the dev group
  and the release build uses a different group, the key becomes
  invisible. Mitigation: pin the access group string in the spec's
  implementation note and reuse the same entitlements file for dev and
  release.
- **Release workflow scope vs (ci 01).** (ci 01) owns the `validate` job
  on every push; this spec owns the `release` job on tags. They must not
  share a workflow file (different triggers, different secrets). If a
  maintainer later merges them, the triggers and secret exposure must
  remain isolated per job.

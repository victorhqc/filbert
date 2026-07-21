# Fix: patch SPM's `resource_bundle_accessor` to load bundles from `Contents/Resources/`

## Objective

Patch SPM's generated `resource_bundle_accessor.swift` in the release build so
`Bundle.module` resolves each module's resource bundle from the assembled
`.app`'s `Contents/Resources/`, where macOS code sealing allows them to live.

## Context

- `scripts/build-dmg.sh` (`assemble_bundle`) places `ai-usage_*.bundle` at
  `AI Usage.app/Contents/Resources/` — see (ci 02 Plan §1). This layout is the
  one macOS code sealing accepts: the `.app` root contains only `Contents/`.
- SPM's generated accessor (`.build/<config>/<Module>.build/DerivedSources/
  resource_bundle_accessor.swift`) looks up the resource bundle at
  `Bundle.main.bundleURL.appendingPathComponent("<module>.bundle")`, i.e. the
  **top level of the host `.app`**, with a hardcoded absolute `buildPath`
  fallback used only inside the build tree. It does **not** consult
  `Contents/Resources/`.
- Symptom (v0.1.0, installed from the GitHub release): launches, runs provider
  init, then aborts at the first real `Bundle.module` access:
  ```
  App/resource_bundle_accessor.swift:12: Fatal error: could not load resource bundle:
    from /Applications/AI Usage.app/ai-usage_App.bundle
     or /Users/runner/work/ai-usage/ai-usage/.build/arm64-apple-macosx/release/ai-usage_App.bundle
  ```
  Reproduced by invoking `/Applications/AI Usage.app/Contents/MacOS/AI Usage`
  directly.
- `AppIcon.icns` must remain at `Contents/Resources/AppIcon.icns` for Finder/Dock
  `CFBundleIconFile` resolution; the runtime icon set by `AppDelegate` reads
  from `ai-usage_App.bundle` (untouched, SPM-placed).
- Earlier draft of this spec proposed moving bundles to the `.app` top level.
  That layout makes the app run, but `codesign` rejects it with
  `unsealed contents present in the bundle root` — modern macOS requires the
  `.app` root to contain only `Contents/`. The rejection breaks `sign_adhoc`,
  `verify_release` (`codesign --verify`), notarization, and Gatekeeper. That
  approach is abandoned; the signable layout (bundles at `Contents/Resources/`)
  is kept, and SPM's accessor is patched to match it.

## Acceptance Criteria

### AC1: `build_release` patches every generated accessor after the release build
- **Given** `scripts/build-dmg.sh --version <v>` runs end-to-end
- **When** `build_release` finishes
- **Then** every `resource_bundle_accessor.swift` under
  `.build/arm64-apple-macosx/release/` has its `mainPath` line rewritten so the
  lookup is `(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent("<module>.bundle")`
- **And** the executable is relinked against the patched accessors
- **And** no original-form `Bundle.main.bundleURL.appendingPathComponent` line
  remains in any release-tree accessor

### AC2: `assemble_bundle` keeps bundles under `Contents/Resources/`
- **Given** the build script runs
- **When** `assemble_bundle` finishes
- **Then** every `ai-usage_*.bundle` from `$BUILD_DIR` lives at
  `<stage>/AI Usage.app/Contents/Resources/<name>.bundle`
- **And** no `ai-usage_*.bundle` exists at the `.app` top level
- **And** `AppIcon.icns` is at `AI Usage.app/Contents/Resources/AppIcon.icns`

### AC3: The assembled `.app` signs and verifies
- **Given** the assembled `.app` with bundles at `Contents/Resources/`
- **When** `sign_adhoc` (or the Developer ID lane) runs `codesign`
- **Then** codesign exits 0 (no `unsealed contents` error)
- **And** `codesign --verify --verbose` reports `valid on disk` and
  `satisfies its Designated Requirement`

### AC4: The assembled `.app` launches without `Bundle.module` fatal errors
- **Given** the assembled `.app` is copied to a clean path
- **When** its executable is invoked directly
- **Then** the process does not abort with
  `Fatal error: could not load resource bundle`
- **And** `AppDelegate.applicationDidFinishLaunching` resolves
  `Bundle.module.url(forResource: "AppIcon", withExtension: "icns")` successfully

### AC5: The Claude Code provider still resolves `statusline_helper.swift`
- **Given** the fixed `.app` is launched
- **When** `Bundle.module.url(forResource: "statusline_helper", withExtension: "swift")`
  is evaluated from `ClaudeCodeProvider`
- **Then** it resolves to the file inside
  `AI Usage.app/Contents/Resources/ai-usage_ClaudeCodeProvider.bundle/statusline_helper.swift`
- **And** the in-app "Install Helper" flow from (providers 02) is unaffected

### AC6: `swift run` and `swift test` remain unaffected
- **Given** a developer runs `swift run App` or `swift test` (no build script)
- **When** `Bundle.module` is accessed
- **Then** the patched accessor is **not** in effect (SPM regenerates the
  accessor from its template on a clean build), and the original `buildPath`
  fallback resolves the bundle in the build tree
- **And** the app launches and tests pass as before

### AC7: The build-script comment matches the actual mechanism
- **Given** the build script
- **When** a reviewer reads the `assemble_bundle` resource-bundle comment
- **Then** the comment describes bundles living at `Contents/Resources/` and
  SPM's accessor being patched to look there via `Bundle.main.resourceURL`
- **And** no claim that `Bundle.module` natively resolves against
  `Contents/Resources/` remains (it does not — the patch is what makes it work)

## Plan

Single-file change to `scripts/build-dmg.sh`:

1. **`build_release`** — after the existing `swift build -c release --arch arm64`
   succeeds, add a `patch_resource_bundle_accessors` step that:
   - Finds every `resource_bundle_accessor.swift` under
     `.build/arm64-apple-macosx/release/` (one per module with resources:
     `App`, `Core`, `ClaudeCodeProvider`, `DeepSeekProvider`, `ZAIProvider`).
   - Rewrites the `mainPath` line, replacing
     `Bundle.main.bundleURL.appendingPathComponent` with
     `(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent`.
     The `?? bundleURL` fallback preserves the dev-tree lookup when
     `resourceURL` is nil (e.g. running tests against the test runner bundle).
   - **Replays** SPM's recorded compile + link commands instead of re-running
     `swift build`. SPM regenerates the accessor from its template during the
     "Write sources" plan phase of *every* `swift build`, so a second build
     reverts the patch before swiftc reads it; blocking the regeneration
     (immutable/read-only file) is not portable — it makes llbuild's "Write
     sources" fail on some runners (observed as an I/O error on GitHub's macOS
     runner). Instead, `replay_release_relink` parses `.build/release.yaml`
     (llbuild's manifest), extracts the exact `swiftc` compile command for each
     patched module and the `swiftc` link command for `App`, and runs them
     directly. Those commands read the patched accessor and never regenerate
     it, so the patch lands in the linked executable deterministically.
   - Asserts the patch took effect on every accessor (grep for the original
     form must return zero hits) and `fatal`s if any accessor is unpatched or
     missing, or if the manifest lacks a compile/link command for a module.

2. **`assemble_bundle`** — unchanged in behavior (bundles still go to
   `Contents/Resources/`, `AppIcon.icns` still at `Contents/Resources/`).
   Update the comment block to describe the patched-accessor mechanism and
   cite (ci 03).

3. No code in `Sources/` changes. No `Package.swift` changes. The layout that
   (ci 02) specifies (bundles under `Contents/Resources/`) is the signable
   layout this spec adopts; (ci 02)'s narrative is correct and is not edited.

The accessor patch is anchored on the literal string
`Bundle.main.bundleURL.appendingPathComponent`, which is stable across SPM
versions (it's the generated accessor's documented shape since Swift 5.3). If
SPM changes the template, the patch step's assertion fails loudly at build
time rather than silently producing a broken app.

## Risks

- **SPM template drift.** If a future Swift version changes the generated
  accessor's shape, the sed patch may no longer match. Mitigation: AC1's
  post-patch assertion fails the build loudly if any accessor is unpatched;
  the fix is a one-line update to the sed pattern.
- **Manifest format drift.** `replay_release_relink` parses `.build/release.yaml`
  and assumes each command node's `args` is a JSON array on one line, that the
  patched modules' compile nodes carry `-emit-module` + `-module-name`, and that
  the `App` link node carries `-emit-executable` + `-o <exe>`. If a future SPM
  changes this manifest shape, the replay `fatal`s (missing compile/link
  command) rather than shipping a broken app. Requires `python3` (present on the
  macOS runners and in dev).
- **Double compile.** The release path compiles the resource modules twice: once
  during the initial `swift build`, once during the replay after the patch. The
  replay recompiles only the ~5 patched modules and relinks `App` (a few seconds).
  Acceptable for a release-only path.
- **Existing v0.1.0 installers/users.** Anyone who downloaded v0.1.0 has a
  crashing `.app`. The fix ships in the next release; recommend cutting
  `v0.1.1` once this lands and pointing users at it.
- **Finder/Dock icon.** Unchanged — `CFBundleIconFile` still resolves from
  `Contents/Resources/AppIcon.icns`, and the runtime icon still reads from
  `ai-usage_App.bundle`.
- **`verify_release` coverage gap.** It runs `codesign --verify` (which AC3
  now satisfies) but does not launch the app, so it cannot on its own catch a
  `Bundle.module` regression. AC4 is verified manually during release
  assembly. A follow-up (out of scope here) could add a smoke launch to
  verification, but that requires a GUI session on the runner.
- **`(ci 02) Plan §1` is still accurate.** Unlike the earlier draft of this
  spec, this version does not contradict (ci 02); both agree that bundles
  live at `Contents/Resources/`. No spec drift.

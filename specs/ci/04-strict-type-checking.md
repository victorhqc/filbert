## Objective

Tighten the project's type-checking so the compiler and linter reject unsafe
type usage at the gate, treating `Any`, force-unwraps, force-casts, and
implicitly-unwrapped optionals as errors everywhere except `Tests/`.

## Context

- `Package.swift` — add per-target `swiftSettings` so the strict flags apply to
  every `Sources/` target without touching `Tests/`.
- `.swiftlint.yml` — currently only disables `trailing_comma`. This is where
  the new strict rules and the `Any`-ban custom rule live.
- `.github/workflows/ci.yml` — runs the gate defined in (ci 01); no new step is
  needed, but every existing step must still pass under the stricter settings.
- `Sources/Core/KeychainStorage.swift` — uses `[String: Any]` for `SecItem*`
  queries. The Security framework API requires this; it is the **sole
  documented boundary exception**, not a violation (see Plan).
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher+Parse.swift` and
  `Sources/Providers/ClaudeCode/Resources/statusline_helper.swift` — use
  `JSONSerialization` returning `Any`. These must move to `Codable` so the
  `Any` ban is achievable without special-casing them.
- `Sources/Providers/ClaudeCode/StatuslineHelperInstaller.swift` — reads and
  rewrites the user's `~/.claude/settings.json` via `[String: Any]` and
  `JSONSerialization`. The schema is **open**: Claude Code lets users add
  arbitrary sibling keys alongside `statusLine` (`padding`,
  `refreshInterval`, theme, …) and (providers 02 AC8) requires those unknown
  keys to round-trip. A plain `Codable` struct would drop them, so this site
  needs a small `AnyJSON`/`singleValueContainer` wrapper that preserves
  unknown keys while still removing every `Any`.
- `Sources/Providers/Cursor/CursorTokenStore.swift` — `jwtExpiry(_:)` decodes a
  JWT `exp` claim via `JSONSerialization.jsonObject as? [String: Any]`. Trivial
  to migrate to a one-field `Codable` struct + `JSONDecoder`; covered by
  `Tests/CursorProviderTests`.
- Builds on (ci 01) AC2 (the gate runs `swiftformat`, `swiftlint`, debug and
  release builds, and tests). This spec tightens what "passing" means for the
  `swiftlint` and `swift build` steps; it does not add steps.
- The orthogonal provider architecture in `AGENTS.md` §1 relies on
  `any AIProvider` existentials in `Sources/Core/ProviderRegistry.swift`. These
  are the Swift 6 existential keyword (`any Protocol`), **not** the `Any` type,
  and are out of scope for the ban.
- `-strict-concurrency=complete` + `-warnings-as-errors` (AC2 × AC1) surface
  Swift 6 diagnostics across `Sources/`. The Core + provider fixes are small
  annotations; the App-layer fixes are larger and are explicitly in scope for
  this spec (see Plan §4):
  - `Sources/Core/ProviderRegistry.swift` is a non-`Sendable` `final class`
    mutated only in `AppMain.init()` before any `Task` runs, then read-only. It
    needs a `Sendable` conformance so `QuotaViewModel` can capture it across
    `Task` boundaries.
  - `Sources/App/QuotaViewModel.swift` (8 sites) passes `self.registry` into
    `Task`s; green once `ProviderRegistry` is `Sendable`.
  - `Sources/App/SettingsWindowActivation.swift` touches `NSApp` (MainActor)
    from a nonisolated `ViewModifier`; needs `@MainActor`.
  - `Sources/App/MenuBarStatusIcon.swift` holds two lazily-populated static
    image caches mutated at render time; same `nonisolated(unsafe)` treatment
    as the Core `UserDefaults` statics.

## Acceptance Criteria

### AC1: Warnings are errors for every source target
- **Given** `Package.swift` is configured
- **When** any `Sources/` target emits a warning during `swift build` or
  `swift build -c release`
- **Then** the build fails
- **And** `Tests/` targets are exempt (a warning in a test does not fail the
  build)

### AC2: Strict concurrency checking is on for source targets
- **Given** `Package.swift` is configured
- **When** the compiler analyses `Sources/` code
- **Then** it runs with `-strict-concurrency=complete`
- **And** `Tests/` targets are exempt

### AC3: Force-unwrap, force-cast, and force-try are lint errors
- **Given** `.swiftlint.yml` is updated
- **When** `swiftlint` runs
- **Then** `force_unwrapping`, `force_cast`, and `force_try` are configured at
  `severity: error`
- **And** any occurrence in `Sources/` fails the gate

### AC4: Implicitly-unwrapped optionals are banned in sources
- **Given** `.swiftlint.yml` is updated
- **When** `swiftlint` runs
- **Then** the `implicitly_unwrapped_optional` rule is configured at
  `severity: error`
- **And** a declaration like `var x: Int!` in `Sources/` fails the gate

### AC5: `Any` (the type) is banned in `Sources/`, allowed in `Tests/`
- **Given** the custom SwiftLint rule is installed
- **When** `swiftlint` runs
- **Then** any use of the `Any` type — `Any`, `[Any]`, `[String: Any]`,
  `[String: [Any]]`, etc. — in a file under `Sources/` fails the gate
- **And** the same usage in a file under `Tests/` does not trigger the rule
- **And** the rule does **not** match the `any Protocol` existential keyword
  (e.g. `any AIProvider`, `any KeychainStorage`)

### AC6: The Security-framework boundary is the only documented `Any` exception
- **Given** the `Any`-ban rule is in force and AC7's `Codable` migrations have
  landed
- **When** `swiftlint` inspects `Sources/Core/KeychainStorage.swift`
- **Then** the `[String: Any]` dictionaries passed to `SecItemCopyMatching`,
  `SecItemAdd`, `SecItemUpdate`, and `SecItemDelete` are exempt via a targeted
  `swiftlint:disable` line
- **And** the disable line carries a comment naming the framework requirement
  (e.g. `// swiftlint:disable:next no_any_type — Security framework API`)
- **And** `Sources/Core/KeychainStorage.swift` is the **only** file in
  `Sources/` that still contains an `Any` type — every other former `Any` site
  (`ClaudeCodeRefresher+Parse.swift`, `statusline_helper.swift`,
  `StatuslineHelperInstaller.swift`, `CursorTokenStore.jwtExpiry`) has been
  migrated to `Codable` per AC7

### AC7: `JSONSerialization` is replaced by `Codable` at every `Any` site in `Sources/`
- **Given** AC5 and AC6
- **When** the four `Any` sites identified in Context are migrated
- **Then** `Sources/Providers/ClaudeCode/ClaudeCodeRefresher+Parse.swift` uses
  a `Codable` struct and `JSONDecoder`, not `JSONSerialization.jsonObject`
- **And** the bundled `Sources/Providers/ClaudeCode/Resources/statusline_helper.swift`
  reads stdin and writes its cache via `JSONDecoder`/`JSONEncoder` and `Codable`
  structs, not `JSONSerialization` with `[String: Any]`
- **And** `Sources/Providers/ClaudeCode/StatuslineHelperInstaller.swift` reads
  and writes `~/.claude/settings.json` via `JSONDecoder`/`JSONEncoder` and a
  `Codable` model backed by an `AnyJSON` value that preserves arbitrary sibling
  keys, with no `Any` type remaining in the file
- **And** `Sources/Providers/Cursor/CursorTokenStore.swift` decodes the JWT
  `exp` claim via a `Codable` struct + `JSONDecoder`, not
  `JSONSerialization.jsonObject`
- **And** the parsed output is byte-equivalent to the previous implementation
  for the inputs covered by `Tests/ClaudeCodeProviderTests`,
  `Tests/ClaudeCodeProviderTests/StatuslineHelperInstallerTests` (including
  `testInstall_preservesStatusLineSiblingKeys`), and `Tests/CursorProviderTests`

### AC8: The full validation gate still passes
- **Given** all of AC1–AC7 are implemented
- **When** the contributor runs the gate from (ci 01): `swiftformat --lint .`,
  `swiftlint`, `swift build`, `swift build -c release`, `swift test`
- **Then** every step is green
- **And** CI on `main` is green

## Plan

Four changes. §1–§3 are the original spec; §4 is the App-layer concurrency
work the strict flags force into scope (owner-approved scope creep).

**1. `Package.swift` strict flags.** Add `swiftSettings:` to every non-test
target (Core, each provider, App). Tests get the default settings.

```swift
.target(
    name: "Core",
    swiftSettings: [
        .unsafeFlags([
            "-warnings-as-errors",
            "-strict-concurrency=complete",
        ]),
    ]
),
```

`.unsafeFlags` is the only SPM-supported knob for these flags at
`swift-tools-version: 5.9`; the flags are pinned at the build-config level so
no contributor can opt out by accident.

**2. `.swiftlint.yml` strict rules and `Any` ban.** Opt into the force-rules
at `error` severity and add one custom regex rule for the `Any` type, scoped to
`Sources/`:

```yaml
opt_in_rules:
  - force_unwrapping
  - implicitly_unwrapped_optional

force_unwrapping: error
force_cast: error
force_try: error
implicitly_unwrapped_optional: error

custom_rules:
  no_any_type:
    name: "No Any type"
    regex: '(?<![A-Za-z_])Any(?![A-Za-z0-9_])'
    match_kinds: [keyword]
    message: "Do not use the Any type in Sources/. Use a concrete type, a generic, or Codable."
    severity: error
    included: [Sources/]
```

`match_kinds` is `[keyword]` (not `[typeidentifier]` as an earlier draft had)
because SwiftLint 0.65 classifies `Any` as a keyword; see the note below this
snippet.

`match_kinds: [typeidentifier]` plus the word-boundary anchors were intended
 to hit the `Any` **type** and skip the `any Protocol` keyword, identifiers like
`hasAnyConfiguredProvider`, and the word `Any` inside comments and strings.
**Implementation note:** SwiftLint 0.65 (the `Mintfile` pin) classifies `Any`
as a `keyword`, not a `typeidentifier`, so the rule as shipped uses
`match_kinds: [keyword]` instead — verified empirically and documented in the
rule's inline comment. The effect is identical: the rule matches the `Any`
type and skips `any Protocol`, identifiers, comments, and strings.

The four strict rules (`force_unwrapping`, `force_cast`, `force_try`,
`implicitly_unwrapped_optional`) apply repo-wide at `error` severity, but
`Tests/` is exempt via a nested `Tests/.swiftlint.yml` that disables them for
the test subtree — SwiftLint 0.65 does not support per-rule path scoping for
built-in rules, so the nested config is the exemption mechanism (ci 04 AC1/AC5
exempt Tests from the gate). All other rules still lint `Tests/`.

**3. Boundary handling and JSON migration.**
- `KeychainStorage.swift` keeps its `[String: Any]` Security-framework queries
  and silences the rule locally with a per-line disable that names the
  framework (AC6). It is the only file in `Sources/` that retains `Any`.
- The ClaudeCode JSON parsers move from `JSONSerialization.jsonObject(as:
  [String: Any])` to a small `Codable` payload struct + `JSONDecoder`. The
  helper script moves from building a `[String: Any]` to a `Codable` cache
  struct + `JSONEncoder`. These refactors stay inside the ClaudeCode module —
  no provider-orthogonality violation.
- `StatuslineHelperInstaller.swift` introduces a small `AnyJSON` enum (backed
  by a `singleValueContainer` decoder that accepts `String`/`Double`/`Bool`/
  `null`/`[String: AnyJSON]`/`[AnyJSON]`) so the open-schema `settings.json`
  round-trips unknown sibling keys without exposing the `Any` type. The
  installer's `Codable` model holds `statusLine` as a typed struct plus an
  `extraKeys: [String: AnyJSON]` sink so user keys like `padding` survive
  install/uninstall. `AnyJSON` lives in `Core` from day one: it is a general
  open-schema JSON value and `KeychainStorage` is already in `Core`, so future
  providers that hit open-schema JSON don't reinvent it.
- `CursorTokenStore.jwtExpiry` moves to a one-field `Codable` struct
  (`{ exp: NSNumber }` equivalent) + `JSONDecoder`.

**4. App-layer concurrency fixes (required to make AC1 + AC2 green).** These
are the minimal annotations and conformances that satisfy the strict-
concurrency checker without changing runtime behavior. They are in scope for
this spec (scope creep explicitly accepted by the owner) rather than deferred
to a Swift 6 spec.
- `Sources/Core/ProviderRegistry.swift` becomes `@MainActor final class`. The
  only writer is `register()`, called synchronously in `AppMain.init()` on the
  MainActor; every reader is `QuotaViewModel`, which is already `@MainActor`.
  MainActor isolation implies `Sendable` (SE-0306/SE-0338), so the class becomes
  `Sendable` with **compiler enforcement** — strictly stronger than an escape
  hatch and the honest model for the access pattern. A header comment records
  that all access is MainActor-bound. This is near-zero ripple: `QuotaViewModel`
  and the registry tests compile unchanged because they are already
  `@MainActor` / synchronous.
- `Sources/App/SettingsWindowActivation.swift`: mark
  `OpenAndRaiseSettingsModifier` (or its mutation methods) `@MainActor` so the
  `NSApp` / `windows` / `styleMask` touches are isolated correctly. SwiftUI
  invokes `ViewModifier.body` on the main actor, so this matches reality.
- `Sources/App/MenuBarStatusIcon.swift`: the two private cache enums
  (`MenuBarRingImageCache`, `MenuBarMacFaceCache`) get `nonisolated(unsafe)`
  on their `static var cache`, matching the Core `UserDefaults` statics.
  SwiftUI renders on the main actor, so the lazy populate is single-threaded in
  practice.
- `Sources/Core/{ProviderOrder,ProviderOverrides,BalanceThresholds,
  ProviderCollapseState,VintageMacIcon}.swift`: each `private static var
  defaults: UserDefaults` becomes `nonisolated(unsafe)` (production never
  mutates after startup; only the test-injection API writes, and XCTest runs
  serially).
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift`: the stored
  `workingDirectoryProvider: () -> URL?` becomes `@Sendable () -> URL?`, and
  the two init sites wrap `makeDefaultWorkingDirectory` in an explicit
  `{ @Sendable in … }` closure so the detached spawn `Task` can't race the
  actor.

A follow-up spec should tackle the full Swift 6 language mode (turning strict
concurrency *on by default* and dropping the `@unchecked`/`nonisolated(unsafe)`
escape hatches in favour of `actor`/`Sendable` conformances enforced by the
compiler). The escape hatches landed here are the minimum required to make
`-strict-concurrency=complete` + `-warnings-as-errors` green; they are not the
final word.

## Risks

- **Strict concurrency noise.** `-strict-concurrency=complete` may surface new
  warnings in existing code; combined with `-warnings-as-errors` (AC1) any such
  warning blocks the gate. Budget time to fix them before merging. This is now
  fully in scope per Plan §4.
- **`@unchecked Sendable` / `nonisolated(unsafe)` escape hatches.** Plan §4
  still relies on these for the `UserDefaults` statics, the two render caches,
  and the spawn closure (`ProviderRegistry` uses `@MainActor`, which is
  compiler-enforced, not an escape hatch). Each escape hatch is documented with
  the invariant that makes it safe (serial test injection; main-actor
  rendering; setup-then-read). The correctness rests on conventions, not
  compiler enforcement — a future change that violates the invariant will
  compile silently. The follow-up Swift 6 spec removes the remaining hatches
  in favour of `actor`/`Sendable`.
- **`ProviderRegistry`: `@MainActor`, not `actor` or `@unchecked Sendable`.**
  The earlier draft of this spec named `actor` as the fix; a literal `actor`
  was rejected after tracing ~18 call sites in `QuotaViewModel` and ~15 in
  tests: every access is MainActor-to-MainActor, so an `actor` would force
  `await` through synchronous code (init, computed properties, sync action
  methods) for zero correctness gain and real regression risk. `@unchecked
  Sendable` was rejected as too weak — it relies on convention, not the
  compiler. `@MainActor final class` is the honest model: the registry is
  touched only from the main thread, MainActor isolation implies `Sendable`,
  and the compiler enforces the invariant going forward.
- **`Package.swift` toolchain coupling.** `.unsafeFlags` are stripped when the
  package is imported as a dependency. This project is an app, not a library,
  so the trade-off is acceptable, but worth noting.
- **Custom regex brittleness.** The `Any`-ban regex relies on SwiftLint's
  `typeidentifier` syntax kind. If SwiftLint changes how it classifies
  `Any`, the rule could false-positive or miss cases. Mitigation: pin SwiftLint
  via the existing `Mintfile` (ci 01 AC3) so behaviour does not drift between
  contributor machines and CI.
- **`Codable` migration risk.** Rewriting the ClaudeCode JSON path changes the
  parser at a network boundary. The existing `Tests/ClaudeCodeProviderTests`
  fixtures are the regression net; if they do not cover edge cases (missing
  fields, unexpected types), bugs can slip through. Re-read those fixtures
  before deleting the old parser.
- **`settings.json` round-trip risk.** The installer migration is the highest-
  risk piece: `settings.json` is user-owned and open-schema, and
  `testInstall_preservesStatusLineSiblingKeys` is the only guard against
  silently dropping keys. The `AnyJSON` wrapper must handle nested objects and
  arrays (not just top-level scalars) or unknown nested user keys will vanish.
  Verify the wrapper round-trips the `StatuslineHelperInstallerTests` fixtures
  byte-for-byte before considering AC7 done.
- **`AnyJSON` API surface.** `AnyJSON` lives in `Core` and is therefore
  `public`. Keep it minimal — just `Codable` + `Equatable` + the cases the
  `singleValueContainer` needs. Do not add convenience initializers, query
  helpers, or `ExpressibleBy*Literal` conformances in this spec; each addition
  broadens the public API surface of `Core` and belongs in its own decision.
- **Scope creep into Swift 6.** This spec now includes the App-layer
  concurrency annotations (Plan §4) that the earlier draft deferred. The line
  to hold is: escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`) are
  allowed here only because each is backed by a documented setup-then-read or
  main-actor-rendering invariant. The *full* Swift 6 language-mode upgrade —
  removing those hatches in favour of `actor`/`Sendable` enforced by the
  compiler — still belongs in its own spec. Don't add new escape hatches beyond
  the ones Plan §4 enumerates.

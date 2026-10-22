---
name: writing-code
description: Write or change production code in this repo — the coding standards, the validation gate, and the self-review checklist. Use this whenever you implement a spec item, add or edit Swift in Sources/, add a dependency, or are about to hand a code change back to the user. Covers naming, guard clauses, side-effect boundaries, DRY, idiomatic Swift, commenting rules (the minimal-comments skill, no spec citations in code), the validation gate, and what to re-check before notifying the user.
---

# Writing code

This is a macOS menu-bar app that makes network calls to AI provider APIs and
stores credentials in the Keychain. Be **methodical and safety-obsessed** —
verify every change. No quick fixes or temporary hacks unless the user
explicitly asks. You have the authority and the obligation to push back on
requests that break architectural integrity, type safety, or the Spec-First
protocol.

Code follows a spec. If there is no spec for the change, stop and use the
[`writing-specs`](../writing-specs/SKILL.md) skill first.

## 1. Where code lives

- **`Sources/App`** — the macOS app target: menu bar (`MenuBarExtra`),
  popover, widgets, app lifecycle (`LSUIElement`).
- **`Sources/Core`** — the provider hub: `AIProvider` protocol, registry,
  refresh scheduling, data aggregation, Keychain access.
- **`Sources/Providers/<Name>`** — one module per provider. Depends only on
  `Core`. Implements `AIProvider`.
- **`Tests/`** — mirrors the `Sources/` layout. Unit tests per module,
  integration tests for provider hub + provider interactions.

## 2. Coding standards

1. **Naming** — intention-revealing. No hidden "magic".
2. **Guard clauses** — prefer `guard` + early return over deep nesting.
3. **Side effects at the boundaries** — each function does one thing. Network
   calls and Keychain access happen at well-defined edges.
4. **DRY, but no premature abstraction** — explicit beats implicit.
5. **Idiomatic Swift** — follow the language's conventional patterns. Use
   `async/await`, `Result` types, and SwiftUI idioms where appropriate.
6. **Protocol-oriented** — the provider architecture depends on it. Each
   provider is a struct or actor conforming to `AIProvider`. The hub talks to
   the protocol, never to a concrete provider.
7. **Comments** — follow the
   [`minimal-comments`](https://github.com/victorhqc/skills.sh/tree/main/skills/minimal-comments)
   skill. If it is not installed, tell the user to run
   `npx skills add victorhqc/skills.sh --skill minimal-comments`. This repo
   adds two rules:
   - **No spec or AC citations in code.** No `(providers 02)`, `AC1`,
     `// ── AC3 ──`, or "implements spec". Specs cite each other; code does
     not cite specs. If a spec shapes a non-obvious decision, state the
     reason in plain words. Delete existing citations on sight.
   - **`///` vs `//`** — SwiftFormat's `docComments` rule (default-on, no
     `.swiftformat` opt-out in this repo) decides the syntax. A comment
     directly above a declaration **must** be `///`; any other comment
     **must** be `//`. Never downgrade a surviving *why* to `//` to make it
     "less official".

8. **Dependencies** — if a package is not in `Package.swift`, add it before
   using it. Prefer Apple frameworks over third-party packages.
9. **Concurrency** — use Swift's structured concurrency (`async/await`,
   `Task`, `@MainActor`). No bare `DispatchQueue` unless interfacing with a
   callback-based API.

### Provider rules

When writing a provider module:

- Implement `AIProvider` and nothing else public. Internal helpers are fine.
- One `URLSession` per provider, configured with the provider's base URL and
  default headers.
- Parse the provider's response into the shared `ProviderQuota` model. Map
  provider-specific fields don't leak into the core.
- Handle auth errors (401), rate limits (429), and network errors distinctly.
- Log only failed operations with safe identifiers and numeric error codes.
  **Never log API keys, auth headers, or raw response bodies**.

## 3. The implementation loop

For each spec item, in order:

1. **Sync** — re-read the spec file; the user may have edited it.
2. **Execute** — perform the next unchecked item, only that item.
3. **Record** — mark the item `[x]` in the spec and log any new findings.
4. **Validate** — run the **full** validation gate (below), every step, in
   order. Do not subset it. Build + test alone is not enough — CI runs
   `swiftformat --lint .`, `swiftlint`, a release build, and tests; so must
   you. If any step fails, fix and restart from step 1.
5. **Self-review** — after the gate passes, review your own work (below).

Do not commit, push, or otherwise touch git on your own. Hand the git commands
to the user to run.

## 4. Validation gate

**This is the single most important step in the loop.** The commands below are
the *exact* gate CI runs in `.github/workflows/ci.yml`. Run all of them, in
order, from the workspace root — **every one must pass before you notify the
user.** Running only `swift build` + `swift test` is not enough: CI also
runs the SwiftFormat lint and a release build, so any of those failing on CI is
a regression you shipped. Keep the gate in sync with `ci.yml` — if a step is
added there, add it here.

SwiftFormat and SwiftLint versions are pinned in `Mintfile`. CI downloads the
pinned prebuilt binaries from GitHub releases and runs them directly
(`swiftformat` / `swiftlint`). Locally you can use Homebrew (`swiftformat` /
`swiftlint` directly), but your installed versions **must match** the `Mintfile`
pins — otherwise a green local run will not predict a green CI run. If your
versions drift, grab the pinned prebuilt binaries (see `DEVELOPMENT.md`).

Treat the gate as a literal checklist. Run each command, read its full output,
and only move to the next when the previous is green. If any step fails, fix
the code and **restart the gate from step 1** — earlier steps can regress
when you edit to fix a later one.

```sh
# 1. Format — CI step "SwiftFormat (lint)" (version pinned in Mintfile;
#    locally: swiftformat matching the pin, via Homebrew or prebuilt download)
swiftformat --lint .

# 2. Lint — CI step "SwiftLint" (version pinned in Mintfile)
swiftlint

# 3. Build — CI step "Build (debug)"
swift build

# 4. Build — CI step "Build (release)" — catches optimizer-only failures
swift build -c release

# 5. Tests — CI step "Test"
swift test

# 6. Workflow tests — CI step "Workflow tests"
python3 scripts/test-automatic-updates.py

# 7. Cask tests — CI step "Homebrew cask tests"
python3 scripts/test-homebrew-cask.py

# 8. Packaging tests — CI step "Local signing and startup tests"
python3 scripts/test-local-signing.py
```

### What counts as "passing"

- **`swiftformat --lint .`** must print `0/N files require formatting`. Any
  `error:` line is a failure — fix the formatting in the file, do not silence
  the rule.
- **`swiftlint`** must report `0 serious` violations. **Warnings** are not
  failures, but if a warning appears in a file you changed, fix it. Pre-existing
  warnings in untouched files are out of scope — note them but don't fix.
- **`swift build`** and **`swift build -c release`** must end with
  `Build complete!`.
- **`swift test`** must show `0 failures`.
- **All three Python test scripts** must report `OK` and exit with status `0`.

### When a tool isn't installed

- If `swiftformat` or `swiftlint` is not installed, tell the user to install
  the version pinned in `Mintfile`. Either match it with Homebrew
  (`brew install swiftformat swiftlint`, then verify the version matches the
  pin) or download the pinned prebuilt binaries (see `DEVELOPMENT.md`). Do
  not skip the gate — tell the user the gate is blocked.
- If Swift itself is not available (`swift build` fails with "command not
  found"), tell the user to install Xcode Command Line Tools with
  `xcode-select --install`.

## 5. Self-review checklist

After the gate passes but before handing off, re-read **every file you
changed** and verify:

- [ ] **Acceptance-criteria alignment** — re-read the ACs from the spec; does
  the code satisfy them, or has it drifted?
- [ ] **Naming & readability** — are new functions, types, and files named with
  intention? Would someone understand them without context?
- [ ] **Side effects** — did you change behavior in code paths you didn't
  intend to touch?
- [ ] **Provider isolation** — did any change to one provider leak into another
  provider or into the core?
- [ ] **Test quality** — do the tests assert the right things, or are they just
  "tests to pass"?
- [ ] **Scope creep** — did you change anything beyond the spec?
- [ ] **Comments** — every remaining comment passes the `minimal-comments`
  skill. No spec citations and no AC markers anywhere.
- [ ] **No secrets in logs** — no API keys, tokens, or auth headers in
  `print()`, `os_log`, or debug output.

If self-review turns up issues, **fix them and re-run the validation gate**
before proceeding. When self-review is clean, **notify the user** for review.

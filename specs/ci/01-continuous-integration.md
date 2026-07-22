## Objective

Run the project's validation gate on every push and pull request to `main` so
the "the gate mirrors CI" claim in the coding standards is true.

## Context

- `.github/workflows/ci.yml` — the GitHub Actions workflow (new)
- The gate steps are defined by the `writing-code` skill (validation gate) and
  must match it command-for-command, so a green local run predicts a green CI
  run.
- Builds on (core 01): CI runs `swift build`, which needs the `Package.swift`
  and targets that (core 01) creates. Until (core 01) lands, CI is expected to
  be red — there is nothing to build yet.
- Deployment target is macOS 14 (Sonoma), Swift 5.9+. The runner must provide a
  Swift toolchain that satisfies that baseline.

## Acceptance Criteria

### AC1: CI triggers on pushes and pull requests to `main`
- **Given** the workflow is installed
- **When** a commit is pushed to `main` or a pull request targets `main`
- **Then** the `CI` workflow runs automatically

### AC2: The workflow runs the full validation gate, in order
- **Given** a CI run starts
- **When** the job executes
- **Then** it runs, as separate steps: the SwiftFormat lint, the SwiftLint lint,
  `swift build`, `swift build -c release`, and `swift test`
- **And** the two lint steps invoke the pinned prebuilt binaries (versions read
  from `Mintfile`), so CI never drifts from the intended tool versions even when
  Homebrew publishes newer ones
- **And** each step is functionally identical to the `writing-code` validation
  gate (same tool, same version, same arguments), so a green local run predicts
  a green CI run

### AC3: Required tools are installed before use, at pinned versions
- **Given** a fresh runner
- **When** the gate needs SwiftFormat and SwiftLint
- **Then** the workflow downloads the prebuilt SwiftFormat and SwiftLint
  binaries for the exact versions pinned in `Mintfile` before the lint steps run
- **And** those binaries are cached under `~/.swift-tools`, keyed on the
  `Mintfile` hash, so repeat runs do not re-download the tools

### AC4: The runner satisfies the macOS 14 / Swift 5.9 baseline
- **Given** the job configuration
- **When** it selects a runner
- **Then** it uses a Sonoma-capable macOS runner whose default toolchain is
  Swift 5.9 or newer, and it prints `swift --version` for the record

### AC5: Any failed step fails the check
- **Given** any gate step exits non-zero
- **When** the job runs
- **Then** the workflow reports failure — no step is allowed to swallow its
  error

## Plan

One workflow, one job (`validate`) on a `macos-14` runner. Steps in gate order.
Concurrency is grouped by ref with `cancel-in-progress` so a new push supersedes
an in-flight run. No matrix; the only third-party actions are `actions/checkout`
and `actions/cache`.

SwiftFormat and SwiftLint are pinned by version in a `Mintfile`, which acts as
the single source of version truth. CI reads those versions and downloads the
matching prebuilt release binaries (`swiftformat.zip` and
`portable_swiftlint.zip`), rather than `brew install` (which drifts to the
latest release) or building from source via Mint (slow, and can break against
the runner's Swift toolchain). The downloaded binaries are cached under
`~/.swift-tools` (keyed on the `Mintfile` hash), and the two lint steps run them
directly from `PATH`.

## Risks

- CI is red until (core 01) lands a buildable `Package.swift`. Expected, not a
  regression.
- `macos-14` default Xcode may advance over time. If a future Xcode drops below
  or diverges from the Swift 5.9 baseline, pin the toolchain then — not now.
- Unpinned linters drift: a newer SwiftFormat or SwiftLint can introduce or
  change a rule (e.g. SwiftFormat's `redundantSendable`) that fails on CI but
  not on a contributor's older local install. The `Mintfile` pins both tools to
  a fixed version to keep CI deterministic; bumping a pin is an intentional
  change that local installs should match.

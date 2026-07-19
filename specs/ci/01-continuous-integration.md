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
- **Then** it runs, as separate steps: `swiftformat --lint .`, `swiftlint`,
  `swift build`, `swift build -c release`, and `swift test`
- **And** each command matches the `writing-code` validation gate exactly, so
  local and CI results agree

### AC3: Required tools are installed before use
- **Given** a fresh runner
- **When** the gate needs SwiftFormat and SwiftLint
- **Then** the workflow installs them (`brew install swiftformat swiftlint`)
  before the lint steps run

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
an in-flight run. No caching, no matrix, no third-party actions beyond
`actions/checkout` — keep the first CI minimal and obvious.

## Risks

- CI is red until (core 01) lands a buildable `Package.swift`. Expected, not a
  regression.
- `macos-14` default Xcode may advance over time. If a future Xcode drops below
  or diverges from the Swift 5.9 baseline, pin the toolchain then — not now.

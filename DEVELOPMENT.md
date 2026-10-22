# Development

This guide covers how to build, run, and check Filbert on your Mac. For how we
work — specs, coding standards, commits, and pull requests — read
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Prerequisites

- **macOS 14 (Sonoma)** or newer.
- **Swift 5.9+** from the Xcode Command Line Tools:

  ```sh
  xcode-select --install
  ```

- **Python 3** for the script tests in the validation gate.
- **SwiftFormat** and **SwiftLint** at the versions pinned in `Mintfile`. See
  [Install the code-quality tools](#install-the-code-quality-tools).
- **create-dmg**, only if you build a DMG: `brew install create-dmg`.

## Build and run

```sh
git clone https://github.com/victorhqc/filbert.git
cd filbert
swift run
```

Filbert appears in the menu bar, not the Dock. macOS may ask for your login
password the first time the app reads the Keychain. See
[Why macOS asks for your password](SETUP.md#why-macos-asks-for-your-password).

## Install the code-quality tools

SwiftFormat and SwiftLint are version-pinned in `Mintfile` so CI and local
runs agree. CI downloads the pinned prebuilt binaries. Do the same locally for
exact parity:

- **Prebuilt binaries (recommended — identical to CI)** — download the exact
  `Mintfile` versions from GitHub releases and drop them on your PATH:

  ```sh
  SF_VERSION=$(grep -Eo 'SwiftFormat@[0-9.]+' Mintfile | cut -d@ -f2)
  SL_VERSION=$(grep -Eo 'SwiftLint@[0-9.]+' Mintfile | cut -d@ -f2)

  curl -fsSL "https://github.com/nicklockwood/SwiftFormat/releases/download/${SF_VERSION}/swiftformat.zip" -o /tmp/swiftformat.zip
  curl -fsSL "https://github.com/realm/SwiftLint/releases/download/${SL_VERSION}/portable_swiftlint.zip" -o /tmp/swiftlint.zip

  # /usr/local/bin is on your PATH; drop the `sudo` if it's writable
  sudo unzip -oj /tmp/swiftformat.zip swiftformat -d /usr/local/bin
  sudo unzip -oj /tmp/swiftlint.zip swiftlint -d /usr/local/bin
  ```

- **Homebrew (simpler, if you keep the versions in sync)** — install the tools,
  then make sure their versions match the `Mintfile` pins:

  ```sh
  brew install swiftformat swiftlint
  swiftformat --version && swiftlint --version
  ```

- **Mint (builds the pinned versions from source)** — reads the `Mintfile` and
  links the exact versions onto your PATH. Slower on first run (and can fail if
  your local Swift toolchain can't build a pinned tool):

  ```sh
  brew install mint
  mint bootstrap --link
  ```

## Validation gate

Run the gate before you hand off a change. It matches the steps in
`.github/workflows/ci.yml`. If a step fails, fix it and start again from
step 1.

```sh
# 1. Format (SwiftFormat — version pinned in Mintfile)
swiftformat --lint .

# 2. Lint (SwiftLint — version pinned in Mintfile)
swiftlint

# 3. Build (debug)
swift build

# 4. Build (release) — catches optimizer-only failures
swift build -c release

# 5. Tests
swift test

# 6. Workflow tests
python3 scripts/test-automatic-updates.py

# 7. Homebrew cask tests
python3 scripts/test-homebrew-cask.py

# 8. Local signing and startup tests
python3 scripts/test-local-signing.py
```

## Build a DMG

```sh
scripts/build-dmg.sh --version 0.1.0 --no-sign
# → dist/Filbert-0.1.0-arm64.dmg
```

Local builds are **ad-hoc signed for development only**. macOS asks you to
confirm the first launch, and they are not the same artifact as the signed,
notarized official releases.

## Architecture

Filbert uses an **orthogonal provider architecture**. Each provider is its own
module behind a shared protocol. You can add or remove any provider without
touching the others or the core app.

```
┌────────────────────────────────────────────┐
│                  App Layer                   │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ Menu Bar │  │ Popover  │  │ Widgets  │  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  │
│       └──────────────┼──────────────┘       │
│                      │                      │
│  ┌───────────────────▼───────────────────┐  │
│  │            Provider Hub               │  │
│  │   (registry, refresh, aggregation)    │  │
│  └───────────────────┬───────────────────┘  │
│                      │                      │
│     ┌────────────────┼────────────────┐     │
│     ▼                ▼                ▼     │
│  ┌──────┐  ┌──────┐  ┌──────┐  ┌──────────┐│
│  │ z.ai │  │DeepSk│  │Claude│  │ OpenAI … ││
│  └──────┘  └──────┘  └──────┘  └──────────┘│
│           Provider implementations          │
└────────────────────────────────────────────┘
```

- **Provider protocol** — one Swift protocol (`AIProvider`) that every provider
  implements. It defines quota fetching, authentication, and display metadata.
- **Provider hub** — owns the registry of active providers, runs the refresh
  cadence, and hands aggregated data to the UI.
- **UI layer** — the menu bar, popover, and widgets read the hub's published
  state. They know nothing about a provider's API.

### Project layout

The project uses Swift Package Manager:

- `Sources/App` — the macOS app target: menu bar, popover, widgets, app
  lifecycle.
- `Sources/Core` — the provider hub: the `AIProvider` protocol, the registry,
  refresh scheduling, and data aggregation.
- `Sources/Providers/<Name>` — one module per provider. Each implements
  `AIProvider`.
- `Tests/` — unit and integration tests that mirror the `Sources/` layout.
- `specs/` — the specs that drive the work.
- `site/` — the [website](https://victorhqc.github.io/filbert/), built by
  `scripts/build-site.sh`.

A provider module depends only on `Core`. The app depends only on `Core` and on
the providers it links. **Providers know nothing about each other.**

## Agent skills

The repo ships skills for AI coding agents in `.agents/skills/`:

- `writing-specs` — the spec format and the citation rules.
- `writing-code` — the coding standards, the validation gate, and the
  self-review checklist.
- `release-notes` — the body text for a GitHub release.

The `pr-description` skill is not in the repo. To install it, see
[Pull requests](CONTRIBUTING.md#pull-requests).

## Maintainer docs

- [`docs/signing-and-notarization.md`](docs/signing-and-notarization.md) —
  produce or verify a signed, notarized release locally.
- [`docs/automatic-updates.md`](docs/automatic-updates.md) — Sparkle updates,
  the appcast, and its signing key.
- [`docs/homebrew-tap.md`](docs/homebrew-tap.md) — the Homebrew tap and cask.
- [`docs/localization-glossary.md`](docs/localization-glossary.md) — the
  translation glossary.

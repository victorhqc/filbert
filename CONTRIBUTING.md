# Contributing to ai-usage

Thanks for helping build ai-usage. This guide covers how we work: the
spec-first workflow, the project layout, the coding standards, and the
validation gate you must pass before you hand off a change.

This is a macOS menu-bar app. It makes network calls to AI provider APIs and
stores API keys in the macOS Keychain. Be methodical. Network and Keychain code
deserves extra care. No quick fixes or temporary hacks unless someone asks for
one.

## Spec-first

Every feature starts as a spec. Write no code until a spec exists and the owner
has reviewed it. If there is no spec for your change, stop and write one first.

The spec format lives in
[`.agents/skills/writing-specs/SKILL.md`](.agents/skills/writing-specs/SKILL.md).

## Project layout

The project uses Swift Package Manager:

- `Sources/App` — the macOS app target: menu bar, popover, widgets, app
  lifecycle.
- `Sources/Core` — the provider hub: the `AIProvider` protocol, the registry,
  refresh scheduling, and data aggregation.
- `Sources/Providers/<Name>` — one module per provider. Each implements
  `AIProvider`.
- `Tests/` — unit and integration tests that mirror the `Sources/` layout.

A provider module depends only on `Core`. The app depends only on `Core` and on
the providers it links. **Providers know nothing about each other.**

## Keep providers orthogonal

The provider architecture is orthogonal. Adding a provider must not force a
change in another provider or in the core app. To add one, you implement
`AIProvider` and register it. Nothing else changes.

When you write a provider module:

- Make only `AIProvider` public. Keep helpers internal.
- Use one `URLSession`, set up with the provider's base URL and headers.
- Map the response into the shared `ProviderQuota` model. Provider-specific
  fields stay out of the core.
- Handle auth errors (401), rate limits (429), and network errors on their own.
- Log status and latency for debugging. **Never log API keys or auth headers.**

## Network rules

This app makes outbound HTTPS calls to provider APIs. Follow these rules:

- **One request shape per provider.** Use `URLSession` directly. No third-party
  networking libraries unless the owner adds one.
- **Handle network errors gracefully.** A failed refresh must not crash the
  app. Show stale data with a timestamp, not a blank panel.
- **Rate-limit refreshes.** Default: one refresh every 5 minutes. Providers
  with tighter limits may need longer intervals.
- **Respect provider rate limits.** On a 429, back off.
- **Keep keys in the Keychain.** Read a key at request time. Never hold it in
  memory longer than you need.

## Coding standards

1. **Naming** — say what you mean. No hidden magic.
2. **Guard clauses** — prefer `guard` and an early return over deep nesting.
3. **Side effects at the edges** — each function does one thing. Network calls
   and Keychain access happen at clear boundaries.
4. **DRY, but no premature abstraction** — explicit beats implicit.
5. **Idiomatic Swift** — use `async/await`, `Result` types, and SwiftUI idioms.
6. **Protocol-oriented** — each provider is a struct or actor that conforms to
   `AIProvider`. The hub talks to the protocol, never to a concrete provider.
7. **Comments earn their place** — never restate the code. Comment a business
   decision, a non-obvious "why", or a provider quirk. Never describe past
   behavior or the change itself — no "used to", "previously", or "instead of".
   When a comment cites a spec, use MLA form: `(providers 02)`.
8. **Dependencies** — add a package to `Package.swift` before you use it. Prefer
   Apple frameworks over third-party ones.
9. **Concurrency** — use structured concurrency (`async/await`, `Task`,
   `@MainActor`). No bare `DispatchQueue` unless you bridge a callback API.

## Code Quality

The gate needs three tools: the Swift toolchain, SwiftFormat, and SwiftLint.
Install them once before you run it.

```sh
xcode-select --install
```

SwiftFormat and SwiftLint are version-pinned in a `Mintfile` so CI and local
runs agree. CI downloads the pinned prebuilt binaries; do the same locally for
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

The following commands should show if anything obvious is failing

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
```

## License

By contributing, you agree that your work ships under the project's
[MIT License](./LICENSE).

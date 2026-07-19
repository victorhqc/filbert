# ai-usage

[![Platform: macOS](https://img.shields.io/badge/platform-macOS%2014%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

A macOS menu-bar app that shows your usage and quota across multiple AI
providers at a glance. Add only the platforms you use — the menu bar, popover,
and widgets adapt to whatever providers you configure.

## What it is

**ai-usage** is a native macOS utility that tracks API usage, quota, and spend
across the AI platforms you actually use. It lives in your menu bar (no Dock
icon) and optionally on your desktop as widgets.

- **Menu bar** — glance at your most-used provider's remaining quota.
- **Popover** — click the icon for a detailed breakdown across all your
  configured providers.
- **Widgets** — pin individual provider stats to Notification Center or your
  desktop.

It is a real macOS app:

- No Dock icon, no app switcher entry — only a menu-bar item (`MenuBarExtra` +
  `LSUIElement`).
- No proxy, no Electron — direct native `URLSession` calls to each provider's
  API.
- Your API keys never leave the machine: they live in the **macOS Keychain**.

## Vision

A single pane of glass for your AI usage. Most developers use more than one AI
platform — a coding plan here, an API key there, a subscription somewhere else.
ai-usage brings them all together so you always know how much you have left,
without opening four browser tabs.

## Supported providers

| Provider    | Status      | What it tracks                                    |
|-------------|-------------|---------------------------------------------------|
| z.ai        | Planned     | GLM Coding Plan quota, token window, peak hours   |
| DeepSeek    | Planned     | API usage, token consumption, balance             |
| Claude      | Planned     | Anthropic API usage, token spend, rate limits     |
| OpenAI      | Planned     | API usage, token spend, billing                   |
| Moonshot    | Planned     | API usage, token consumption                      |

Providers are **pluggable**. Each one is an independent module behind a shared
protocol — add or remove any provider without touching the others or the core
app.

## Architecture

ai-usage follows an **orthogonal provider architecture**:

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

- **Provider protocol** — a single Swift protocol (`AIProvider`) that every
  provider implements. Defines quota fetching, authentication, and display
  metadata.
- **Provider hub** — owns the registry of active providers, handles refresh
  cadence, and surfaces aggregated data to the UI layer.
- **UI layer** — menu bar, popover, and widgets consume the hub's published
  state. They know nothing about individual provider APIs.

To add a new provider, you implement one protocol and register it. No other
files change.

## Requirements

- **Apple Silicon** (M1 or newer). Intel Macs capable of running Sonoma are
  supported but not the primary target.
- macOS **14.0 (Sonoma)** or newer.
- To build from source: **Swift 5.9+**. Install the Xcode Command Line Tools
  with `xcode-select --install`.
- API keys for the providers you want to track.

## Status

**Bootstrapping.** This project is in the idea and specification phase. No code
yet — we are writing specs, establishing standards, and setting up the
repository.

See [`specs/`](specs/) for the spec files that will drive implementation.

## Development

We follow a **spec-first** workflow:

1. **Spec** — write acceptance criteria in `specs/<topic>/NN-description.md`.
2. **Implement** — one spec item at a time, in order.
3. **Validate** — run the full validation gate.
4. **Review** — self-review, then hand off for review.

See [`AGENTS.md`](AGENTS.md) for the full workflow and standards.

### Quick start (when we have code)

```bash
git clone https://github.com/victorhqc/ai-usage.git
cd ai-usage
swift run
```

## Security

- API keys are stored as **Keychain generic-password items** — never written to
  disk in plaintext, never logged.
- Keys are **sent only to their respective provider APIs** over HTTPS.
- **No telemetry, no analytics, no remote logging.** Outbound requests are
  strictly the provider API calls needed to fetch usage data.

## License

[MIT](./LICENSE) © 2026 Victor Quiroz Castro.

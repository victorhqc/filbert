## Objective

Define the `AIProvider` protocol, the shared `ProviderQuota` model, and the
Keychain abstraction so every provider module can be built against a stable,
minimal contract.

## Context

- `Sources/Core/ProviderProtocol.swift` — protocol + shared models (new)
- `Sources/Core/Keychain.swift` — generic Keychain wrapper (new)
- `Sources/Core/ProviderRegistry.swift` — registry of active providers (new)
- `Package.swift` — multi-module SPM project (new)
- This is the **first spec in the project**. Nothing exists yet.
- Deployment target: macOS 14.0 (Sonoma). Apple Silicon (M1+) primary;
  Intel Macs that support Sonoma are secondary. No APIs or frameworks
  older than Sonoma are used — `MenuBarExtra`, `@Observable`, and
  Swift 5.9 concurrency are the baseline.
- Providers (z.ai, DeepSeek, Claude, OpenAI, Moonshot) will conform to this
  protocol. Each lives in `Sources/Providers/<Name>/` and depends only on
  `Core`.
- Reference: zai-bar's `Keychain.swift` (line-for-line structure, generalized
  from `service: "zai-bar"` to parameterized service name).
- Providers fall into two plan types. The shared model must represent both
  without leaking provider-specific details:
  - **Coding plan** (z.ai, some DeepSeek tiers) — fixed-window quotas:
    percentage-based, reset dates, per-window allocations (5-hour, weekly,
    monthly).
  - **API plan** (OpenAI, Claude, Moonshot, most DeepSeek tiers) —
    continuous consumption: token usage, dollar spend, remaining balance,
    rate-limit counters. No percentage ceiling; just what you've used so far.

## Acceptance Criteria

### AC1: `ProviderQuota` represents any plan type with no provider-specific fields
- **Given** a provider fetches usage data
- **When** it maps its API response into the shared model
- **Then** the model contains only: provider ID, provider name, headline
  string (free-form — `"42% · resets in 3h"` or `"$18.50 spent"`), list of
  `UsageLine` (each with label, optional used/total, optional percentage,
  optional unit string, optional reset date, optional detail breakdown),
  last-updated timestamp, and optional error string
- **And** a single provider can return a mix of line types: some lines may
  carry `percentage` + `resetDate` (windowed quota), others may carry
  `used` + `unit` (continuous consumption), and some may carry both (a
  capped API plan with a percentage-remaining ceiling)
- **And** no field is named after a specific provider or plan type (no
  `codingPlanTier`, no `balanceCents`, no `rateLimitRPM`)

### AC2: `AIProvider` protocol has static metadata + one async fetch method
- **Given** a new provider module
- **When** its type conforms to `AIProvider`
- **Then** it declares `static var providerId: String` (e.g. `"zai"`),
  `static var providerName: String` (e.g. `"z.ai"`), and an instance method
  `func fetchQuota(apiKey: String) async throws -> ProviderQuota`
- **And** each provider is responsible for formatting its own headline
  string — the Core layer never interprets it

### AC3: Keychain wrapper stores and retrieves API keys by provider
- **Given** a provider ID (e.g. `"zai"`)
- **When** the app calls `Keychain.shared.save("key123", for: "zai")`
- **Then** the key is stored as a generic-password item with service `ai-usage` and account `provider-zai`, retrievable via `Keychain.shared.load(for: "zai")`

### AC4: `ProviderRegistry` holds provider instances and dispatches fetches
- **Given** one or more providers registered
- **When** the registry calls `fetchAll()`
- **Then** each registered provider's `fetchQuota` is called with its stored
  API key, results are aggregated keyed by provider ID, and errors from one
  provider do not affect others

### AC5: Package.swift compiles an executable target that depends on Core
- **Given** a fresh checkout
- **When** running `swift build`
- **Then** the project compiles with zero errors and zero warnings

### AC6: App target launches as a menu-bar-only agent
- **Given** the built executable
- **When** launched
- **Then** it appears only in the menu bar (no Dock icon, no app switcher
  entry), shows a system SF Symbol icon, and clicking it opens a popover
  with a Quit button

## Plan

1. Create `Package.swift` with three targets:
   - `Core` (library) — no dependencies
   - `ZAIProvider` (library) — depends on `Core`
   - `App` (executable) — depends on `Core`
2. Write `Sources/Core/ProviderProtocol.swift` — `ProviderQuota`,
   `UsageLine`, `UsageDetail` structs, and `AIProvider` protocol.
   `UsageLine` replaces the old `QuotaLimit` name to better fit API-plan
   providers that track consumption, not just limits.
3. Write `Sources/Core/Keychain.swift` — adapt zai-bar's pattern: `service`
   is always `"ai-usage"`, `account` is `"provider-<id>"`. Provide
   `save(_:for:)`, `load(for:)`, `delete(for:)`.
4. Write `Sources/Core/ProviderRegistry.swift` — stores `[String: any AIProvider]`,
   loads keys via Keychain, calls `fetchQuota`, collects results.
5. Write `Sources/Providers/ZAI/ZAIProvider.swift` — a stub that conforms
   to `AIProvider` and returns hardcoded placeholder data (real API
   integration comes in a later `providers` spec).
6. Write `Sources/App/AppMain.swift` — `@main` SwiftUI App, `MenuBarExtra`
   with a system image icon, minimal popover with placeholder text and a
   Quit button, `@NSApplicationDelegateAdaptor` for `LSUIElement`.
7. Add `.gitignore` with `.build/`, `DerivedData/`, `.DS_Store`.
8. Run `swift build` to verify AC5.

## Risks

- None. This is the first code in the repository — no regressions possible.

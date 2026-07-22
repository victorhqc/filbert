## Objective

Add an OpenAI Codex provider that displays the signed-in user's Codex rate-limit windows by querying the local Codex CLI app server without reading credentials or calling a private HTTP endpoint.

## Context

- `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` — new provider module that maps Codex rate-limit snapshots into `ProviderQuota` (core 01).
- `Sources/Providers/OpenAICodex/CodexLocator.swift` — locates the user's `codex` executable without invoking a shell.
- `Sources/Providers/OpenAICodex/CodexAppServerClient.swift` — starts `codex app-server --stdio`, performs the protocol handshake, requests `account/rateLimits/read`, and closes the child process.
- `Sources/App/AppMain.swift` — registers the provider alongside the existing orthogonal provider modules (ui 02 AC9).
- `Sources/App/SettingsView.swift` — uses the existing API-key-free setup presentation from (ui 05), with no helper install or base-URL controls.
- `Package.swift` — adds `OpenAICodexProvider` and `OpenAICodexProviderTests` targets; the provider depends only on `Core`.
- Codex is treated as an API-key-free provider under the generalized authentication contract in (core 03); the app never reads Codex's stored login credentials.
- The data source is Codex CLI's app-server method `account/rateLimits/read`. The protocol returns a `RateLimitSnapshot` with optional `primary` and `secondary` windows. Each window carries `usedPercent`, `resetsAt`, and `windowDurationMins`.
- OpenAI documents that Codex usage limits depend on the user's ChatGPT plan. The public documentation does not expose a supported subscription-quota HTTP API, so this provider stays behind the local CLI boundary.

## Acceptance Criteria

### AC1: Locate the Codex CLI without a shell

- **Given** the provider is initialized
- **When** `CodexLocator.resolve()` runs
- **Then** it returns the absolute path to the first executable `codex` binary found through the process environment's `PATH`, followed by known macOS install locations
- **And** the known locations include Homebrew, `/usr/local/bin`, common npm global paths, and the Codex desktop app's bundled CLI when present
- **And** when no executable is found it returns `nil` without throwing

### AC2: Report API-key-free setup state

- **Given** `OpenAICodexProvider` is registered
- **When** Core asks for its authentication shape and setup state
- **Then** `authShape` is `.apiKeyFree`
- **And** `isConfigured()` is `true` when the Codex executable is locatable
- **And** a missing executable produces `.setup("Codex CLI not installed")`
- **And** the provider never reads or writes the app Keychain and never reads Codex credential files directly (core 03 AC4)

### AC3: Query rate limits through a bounded app-server session

- **Given** a Codex executable is available and signed in with ChatGPT
- **When** `fetchQuota(auth:baseURL:)` receives `.apiKeyFree`
- **Then** it starts that executable as `codex app-server --stdio`
- **And** it completes the app-server initialization handshake before sending `account/rateLimits/read` with JSON-RPC request correlation
- **And** it decodes the matching response, ignores unrelated notifications, closes stdin, and terminates the child process after the response
- **And** startup, handshake, and response waits share a bounded timeout of 10 seconds
- **And** `baseURL` is ignored because the provider does not make its own network request

### AC4: Never handle Codex credentials

- **Given** the Codex CLI may store and refresh its own login credentials
- **When** the provider fetches quota
- **Then** authentication and network access remain inside the spawned Codex process
- **And** the app never reads `auth.json`, browser cookies, environment API keys, OAuth tokens, or macOS Keychain entries owned by Codex
- **And** logs and surfaced errors never include app-server payloads that could contain account identifiers

### AC5: Map the Codex quota bucket into usage lines

- **Given** `account/rateLimits/read` returns `rateLimitsByLimitId["codex"]`
- **When** the provider selects a snapshot
- **Then** it prefers that bucket over the backward-compatible top-level `rateLimits` snapshot
- **And** it maps each present `primary` and `secondary` window into one `UsageLine`
- **And** each line uses `usedPercent` as `percentage`, converts `resetsAt` from Unix epoch seconds to `Date`, and does not synthesize `used`, `total`, or `unit`
- **And** the label is derived from `windowDurationMins` using stable user-facing names for known durations and a localized duration label for unknown durations
- **And** a missing window is omitted rather than treated as an error

### AC6: Build a useful headline without assuming window lengths

- **Given** one or more rate-limit windows were decoded
- **When** the headline is built
- **Then** it uses the shortest-duration available window and formats its used percentage with `QuotaFormatting.countdown(to:)` when a reset time exists (providers 01 AC5)
- **And** it does not assume that Codex will always use 5-hour or 7-day windows
- **And** when no windows are present the headline is `"No usage limits reported"`

### AC7: Surface optional credits without enabling purchases

- **Given** the selected snapshot contains a credits balance
- **When** quota details are built
- **Then** a read-only detail row shows the balance when the server supplied one
- **And** `unlimited == true` is displayed as `"Unlimited credits"`
- **And** the provider does not consume reset credits, buy credits, or invoke any mutation method
- **And** absent credit data produces no credit row

### AC8: Fail clearly for unsupported or signed-out CLIs

- **Given** the executable is missing, the app-server method is unsupported, the user is signed out, the child exits, the response is malformed, or the timeout expires
- **When** setup or fetch runs
- **Then** the provider returns a typed error with a short localized recovery message
- **And** unsupported CLI versions instruct the user to update Codex
- **And** signed-out sessions instruct the user to run `codex login`
- **And** the app remains responsive and other providers continue refreshing

### AC9: Refresh only through the normal provider fetch path

- **Given** the provider is configured
- **When** automatic or manual refresh runs
- **Then** each eligible refresh performs one `account/rateLimits/read` session
- **And** it relies on the registry's existing refresh scheduling and does not conform to `ProactiveRefreshable` (providers 03)
- **And** concurrent fetches for this provider are coalesced so only one app-server child is active at a time

### AC10: Keep the provider orthogonal

- **Given** the provider is added
- **When** the package is built and tested
- **Then** the new provider target depends only on `Core`
- **And** no existing provider module is changed
- **And** the App layer contains no quota-rendering branch keyed on `"openai-codex"`
- **And** `swift build` and the full test suite pass

## Plan

1. Add `OpenAICodexProvider` as a provider target with identifier `openai-codex`, API-key-free authentication, and no configurable base URL.
2. Implement `CodexLocator` with injected environment and filesystem dependencies so lookup order and missing installations are unit-testable.
3. Implement a small app-server client around `Foundation.Process`, pipes, newline-delimited JSON-RPC messages, request IDs, and a single shared timeout. Keep process spawning and protocol decoding behind injectable boundaries.
4. Decode only the fields needed from `account/rateLimits/read`. Prefer the `codex` entry in `rateLimitsByLimitId`, then fall back to `rateLimits` for older compatible CLIs. Ignore unknown fields and enum values.
5. Map windows, reset dates, plan metadata, and optional credits into existing `ProviderQuota` fields. Keep all Codex-specific interpretation inside the provider module.
6. Register the provider in `AppMain`, add package and test targets, and reuse the generic API-key-free settings and quota UI from (ui 05).
7. Add tests for locator ordering, handshake/request correlation, interleaved notifications, timeout and process cleanup, signed-out and unsupported responses, multi-bucket selection, partial windows, unknown durations, credits, concurrent fetch coalescing, and redacted errors.

No production code is written until this spec is reviewed.

## Risks

- `codex app-server` is currently marked experimental. Method names or response fields may change between CLI releases; tolerant decoding, typed compatibility errors, and fixture coverage reduce but do not remove this risk.
- Starting a short-lived child process on every eligible refresh adds latency and resource use. Coalescing and the existing refresh interval keep that bounded.
- A CLI installed through an editor-managed or version-manager path may not appear in the menu-bar app's environment. Known-path lookup helps, but some users may still need to expose the binary in a standard location.
- Codex may return multiple metered buckets. Selecting the explicit `codex` bucket first avoids mixing unrelated limits, but future bucket semantics may require a follow-up spec.
- Plan names, window durations, and credit fields are server-controlled and may be absent. The UI must remain useful with only a percentage.

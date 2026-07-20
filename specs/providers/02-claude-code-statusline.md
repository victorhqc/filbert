## Objective

Add a `ClaudeCodeProvider` that surfaces a Claude Pro/Max subscription's
5-hour and 7-day usage windows by reading the JSON `rate_limits` payload
Claude Code already pipes to its `statusLine` command — without an API key,
without OAuth impersonation, and without ever touching Claude Code's
Keychain entry.

## Context

- `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift` — new module. Reads
  a cache file written by the statusline helper, maps the JSON into
  `ProviderQuota` (core 01).
- `Sources/Core/ProviderProtocol.swift` — `fetchQuota` is generalized to take
  a `ProviderAuth` enum (`.apiKey(String)` or `.apiKeyFree`) instead of a raw
  `String`, so providers without an API key have a first-class seat at the
  protocol. Specified in (core 03); landed as part of this slice.
- `Sources/Core/ProviderRegistry.swift` — `isConfigured(_:)` and `fetchAll()`
  stop assuming every provider has a Keychain key. For `.apiKeyFree` providers
  they delegate configuration state to the provider itself (binary found +
  helper installed + cache present).
- `Sources/App/AppMain.swift` — registers `ClaudeCodeProvider` alongside
  `ZAIProvider` (one line, mirroring (ui 02 AC9)).
- `Sources/App/SettingsView.swift` — Claude Code's row is **not** the API-key
  row from (ui 02 AC3). It shows a setup state, an "Install helper…" button,
  and hides the base-URL override (no transport to override). Surfaced in a
  follow-up UI spec, cited from here as (ui 05).
- `Sources/App/QuotaView.swift` — renders Claude Code like any other
  `ProviderQuota`; no provider-specific UI. The "Clear Key" button in the
  popover footer (ui 04) is suppressed for `apiKeyFree` providers.
- Builds on the orthogonal architecture in (core 01) and (ui 02): adding
  Claude Code must not require edits to ZAI, the popover, or the widget.
- **Why statusline and not ACP.** ACP's `claude-agent-acp` adapter does not
  emit `_meta.rate_limits` today (open issues
  [`agentclientprotocol/claude-agent-acp#306`](https://github.com/agentclientprotocol/claude-agent-acp/issues/306)
  and
  [`#625`](https://github.com/agentclientprotocol/claude-agent-acp/issues/625)).
  The statusline stdin JSON is the **only documented, stable channel** that
  carries these numbers, since Claude Code v2.1.80.
- **Why no API key.** The user's Claude Code account uses the browser OAuth
  flow against `claude.ai` — there is no Console key to enter. Reusing
  Claude Code's OAuth tokens ourselves is forbidden by Anthropic's Feb-2026
  ToS update. The statusline listener sidesteps both: we read data Claude
  Code already fetched for itself, at zero inference cost and zero credential
  handling on our side.

## Acceptance Criteria

### AC1: Locate the `claude` binary on the user's PATH or known install dirs
- **Given** the provider is initialized
- **When** `ClaudeCodeLocator.resolve()` runs
- **Then** it returns the absolute path to the first `claude` binary found,
  checking in order: `which claude` (resolved via `FileManager` +
  `/usr/bin/env` lookup, not a shell), then known install locations
  (`~/.local/bin/claude`, `~/.claude/local/claude`,
  `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`,
  `~/.bun/bin/claude`, `~/.npm-global/bin/claude`)
- **And** when none is found it returns `nil` and the provider's setup state
  becomes `claudeNotInstalled` — never throws

### AC2: Provider conforms to the new `ProviderAuth`-based protocol
- **Given** `ClaudeCodeProvider` is registered
- **When** the registry dispatches a fetch via the generalized
  `fetchQuota(auth:baseURL:)` from (core 03)
- **Then** `ClaudeCodeProvider` is called with `auth: .apiKeyFree` and ignores
  the `baseURL` parameter entirely — its data comes from a local cache file,
  not an HTTP endpoint

### AC3: `isConfigured` for an `.apiKeyFree` provider does not consult the Keychain
- **Given** `ClaudeCodeProvider` is registered
- **When** the registry checks `isConfigured("claude-code")`
- **Then** it returns `true` iff (a) the binary is locatable (AC1) **and**
  (b) the helper is installed in `~/.claude/settings.json` (AC7)
- **And** it never calls `Keychain.load(for: "claude-code")`, so no Keychain
  entry is ever created or read for this provider — this is the central
  motivation for the protocol change in (core 03)

### AC4: Fetch reads only the cache file
- **Given** the provider is configured and `auth == .apiKeyFree`
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it reads `~/.cache/ai-usage/claude-code.json` (the cache path),
  decodes the JSON the helper script wrote, and never spawns `claude`, never
  touches the network, and never reads Claude Code's Keychain entry

### AC5: Cache maps to `ProviderQuota` with two window lines
- **Given** a cache file containing
  `rate_limits.five_hour.{used_percentage,resets_at}` and/or
  `rate_limits.seven_day.{used_percentage,resets_at}`
- **When** the provider decodes it
- **Then** it produces one `UsageLine` per window present, with `label`
  ("5-hour window" / "Weekly"), `percentage` set from `used_percentage`, and
  `resetDate` derived from `resets_at` (Unix epoch **seconds** → `Date`)
- **And** absent windows are omitted, not rendered as errors
- **And** no `used`, `total`, or `unit` is synthesized — Claude Code's
  payload carries only percentages and reset timestamps

### AC5b: `ProviderQuota` carries a provider-defined staleness flag
- **Given** a fetched `ProviderQuota` from any provider
- **When** the App layer checks whether the data is fresh enough to show
  without a caveat
- **Then** it reads a single `isStale: Bool` field on `ProviderQuota`,
  defaulting to `false`
- **And** the provider is solely responsible for setting it — the App layer
  never computes staleness itself, never references the cache file path,
  and never branches on provider ID to decide freshness
- **And** for `ClaudeCodeProvider`, `isStale == true` when
  `quota.lastUpdated` is older than the provider's own freshness threshold
  (1 hour default per AC10) — the threshold lives in the provider module,
  not in Core or App

### AC6: Headline reflects the 5-hour window with the shared countdown helper
- **Given** decoded lines
- **When** the headline string is built
- **Then** it follows 5-hour → weekly priority, formatted like `"42% ·
  resets in 3h"` using `QuotaFormatting.countdown(to:)` (providers 01 AC5) —
  never a hand-rolled duration string
- **And** when both windows are absent it reads "No data" localized

### AC7: Helper script writes the cache atomically
- **Given** the user has clicked "Install helper" in Settings (ui 05)
- **When** Claude Code next invokes its `statusLine` command
- **Then** our helper script (installed at
  `~/.claude/ai-usage-statusline.sh`) reads the JSON from stdin, extracts
  `rate_limits`, and writes it to the cache path via a temp file + `rename`
  so a half-written file is never observed by a concurrent reader

### AC8: Helper install merges, never clobbers, the user's existing statusLine
- **Given** `~/.claude/settings.json` may already have a `statusLine`
  configured (ccstatusline, custom script, etc.)
- **When** our installer writes settings
- **Then** it preserves the user's existing command by chaining: the new
  `statusLine.command` runs the user's prior command first, captures its
  stdout, then pipes the original JSON into our helper
- **And** an existing `ai-usage` chain entry is detected and replaced in
  place (no double-wrapping on reinstall)
- **And** if settings.json does not parse as JSON, the install aborts and
  surfaces the error — it never writes a settings file it cannot read back

### AC9: Refresh is click-debounced, not auto-polled
- **Given** the popover is open or the user clicks Refresh
- **When** a refresh is requested for `claude-code`
- **Then** it re-reads the cache file **immediately** — the cache itself is
  the debounce point, not our code
- **And** a second click within 60 seconds of the last read is ignored,
  surfacing "Refreshed 23s ago" instead of re-reading
- **And** there is no background timer for this provider — its data only
  changes when Claude Code updates the cache, which only happens when the
  user is actively prompting Claude Code (Claude Code Docs: statusline
  updates "after each new assistant message" and on `refreshInterval`)

### AC10: Stale cache surfaces honestly, never as fresh data
- **Given** the cache file's `written_at` timestamp is older than a
  freshness threshold (default 1 hour)
- **When** the popover renders Claude Code's section
- **Then** the headline and lines render as usual **and** a muted
  "Last updated by Claude Code: 3h ago" line appears beneath them, followed
  by a secondary hint line "Open Claude Code to refresh"
- **And** a cache file that does not exist renders the section in
  `error("Open Claude Code to populate usage data")`, not as unconfigured —
  the provider is configured, we just have no data yet

### AC11: Uninstall removes helper cleanly
- **Given** the user clicks "Remove helper" in Settings (ui 05) or the
  provider is unconfigured
- **When** uninstall runs
- **Then** the helper script at `~/.claude/ai-usage-statusline.sh` is
  deleted and any `ai-usage` chain entry is unwrapped from
  `~/.claude/settings.json`, restoring the user's prior `statusLine.command`
- **And** the cache file at the cache path is deleted

### AC12: Orthogonality — ZAI is untouched
- **Given** the change lands
- **When** `swift build` and the ZAI test suite run
- **Then** `ZAIProvider` compiles unchanged, its Keychain entry is still
  used as before, its base-URL override (core 02) still applies, and no
  App-layer branch on `providerId == "claude-code"` appears outside the
  settings row (ui 05) — preserving (core 01 AC1) and (ui 02 AC9)

## Plan

1. **Core: protocol change (specified in (core 03)).** `fetchQuota` becomes
   `fetchQuota(auth:baseURL:)` where `auth` is `ProviderAuth`. ZAI is updated
   in lockstep to receive `.apiKey(key)` and ignore the change otherwise.
   This lands in the same PR as the Claude Code provider — no intermediate
   state where the protocol and its consumers disagree.
3. **Core: typed configuration state.** Reuses the `ProviderState.setup(String)`
   case introduced in (core 03 AC6) to carry short setup reasons ("Claude
   Code not found", "Helper not installed"). The popover renders this
   differently from `.unconfigured` (which today implies "enter an API key").
4. **Provider module.** Create `Sources/Providers/ClaudeCode/` with:
   - `ClaudeCodeLocator.swift` — binary resolution per AC1.
   - `StatuslineCacheStore.swift` — read + atomic write the cache file at
     the cache path. Codable mirror of `rate_limits` JSON.
   - `StatuslineHelperInstaller.swift` — install/uninstall the shell helper,
     chain into the existing `statusLine.command` per AC8.
   - `ClaudeCodeProvider.swift` — conform to `AIProvider` with the new
     `fetchQuota(auth:baseURL:)` signature from (core 03); handle
     `.apiKeyFree` and ignore `.apiKey` (it never receives it). Cache reads
     per AC4–AC6.
5. **Helper binary.** A small Swift source file shipped as a resource in
   the `ClaudeCodeProvider` module. At install time we compile it with
   `swiftc -O -o ~/.claude/ai-usage-statusline <source>` so the helper is a
   native binary — fast cold-start (Claude Code spawns it on every status
   line update, debounced ~300ms) and no runtime interpreter dependency.
   Reads stdin JSON via `JSONDecoder`, extracts `rate_limits`, writes the
   cache atomically. No `python3`, no `jq`, no `swift -e` at runtime. If
   `swiftc` is not on the user's PATH at install time the install aborts
   and surfaces the error (Claude Code itself requires Swift on macOS, so
   this is near-always satisfied). The source file and the compiled binary
   path are owned by this provider module; no other provider references
   them.
6. **Package.swift.** Add a `ClaudeCodeProvider` library target depending
   only on `Core`, plus its test target. The `App` target gains the
   dependency and registers the provider in `AppMain.init()` (one line,
   mirroring how ZAI is wired today).
7. **App: Settings row + popover gating.** Implemented under (ui 05). This
   spec's ACs are testable independently of the UI; the UI is a consumer of
   the configuration states surfaced in step 3.
8. **Tests.**
   - `ClaudeCodeLocatorTests` — known dirs searched in order, missing binary
     returns `nil`.
   - `StatuslineCacheStoreTests` — round-trip the JSON shape from the
     Claude Code Docs (including the documented-absent `rate_limits` case),
     atomic write survives a simulated concurrent read.
   - `StatuslineHelperInstallerTests` — install into a settings.json with no
     prior `statusLine`, with a prior `statusLine` (chain preserved), with
     an existing ai-usage chain (replaced in place), with an unparseable
     settings.json (install aborts). Uninstall restores prior state in each
     case.
   - `ClaudeCodeProviderTests` — given a cache fixture, assert the mapped
     `ProviderQuota` (two lines, headline, percentages, reset dates) and
     `isStale == true` when `lastUpdated` is older than the provider's
     freshness threshold. Assert ZAI is unaffected when both providers
     are registered together.
   - `ProviderRegistryTests` — `isConfigured("claude-code")` does not call
     Keychain (verified by injecting a Keychain stub that fails on any
     call); `fetchAll` passes `.apiKeyFree` for `claude-code` and
     `.apiKey(...)` for `zai`.
   - `ClaudeCodeProviderSetupTests` — `currentSetupState()` returns the
     three documented states (binary missing → `setup(...)`, helper
     missing → `setup(...)`, helper installed → `loaded`/equivalent) by
     stubbing the locator and the installer.

No code is written until this spec is reviewed.

## Risks

- **Source-breaking protocol change, by design.** `fetchQuota(apiKey:baseURL:)`
  becomes `fetchQuota(auth:baseURL:)` per (core 03). Every existing provider
  must adopt the new signature at once — today that's only ZAI, so the blast
  radius is small, but the contract change must land in the same commit as
  the Claude Code provider to keep `swift build` green. This is the explicit
  cost of doing it right now instead of deferring, per the user's call:
  these contract changes only compound as more auth shapes arrive.
- **The `rate_limits` field is subscription-gated and session-timing-dependent.**
  Per Claude Code Docs, `rate_limits` "appears only for Claude.ai subscribers
  (Pro/Max) after the first API response in the session." Free-tier users
  and brand-new sessions will see no data. AC5 already handles absent
  windows; AC10 surfaces the no-data case honestly. We cannot manufacture
  data that does not exist.
- **The statusline JSON shape is documented but not version-pinned.** Claude
  Code can rename fields across releases. The Codable layer stays private to
  the module (mirrors (providers 01) Plan), so a field rename is a one-file
  change. We pin to the shape documented at
  https://code.claude.com/docs/en/statusline as of writing and note the
  pinned version in a comment.
- **Two processes writing the cache concurrently is impossible by design.**
  Claude Code invokes the statusline command as a fresh subprocess on each
  update (debounced 300 ms, in-flight cancellation per the docs). Atomic
  write via temp + rename (AC7) is belt-and-suspenders, not a correctness
  requirement.
- **Settings.json is a shared file we don't own.** Other tools (ccstatusline,
  `/statusline` AI-generated scripts, RTK, etc.) also write to
  `~/.claude/settings.json`. AC8 chains rather than overwrites, but a
  concurrent edit by another tool can still race. Mitigation: read-modify-
  write in one short critical section, never hold the file open, and detect
  a parse failure on write by re-reading (AC8 last bullet).
- **Cache freshness depends on the user actually running Claude Code.** This
  is the core trade-off of Option 1′ and is surfaced honestly in the UI
  (AC10). There is no workaround within ToS — refreshing the data requires
  either an active Claude Code session or spending the user's quota on a
  synthetic call, which we explicitly reject.
- **`.apiKeyFree` providers break the popover's "Clear Key" affordance.**
  Today every configured provider's section ends with a "Clear Key" button
  (ui 04). That button is meaningless for Claude Code (no key exists). The
  popover must suppress it for `.apiKeyFree` providers — a small new branch
  in `QuotaView.quotaContent`. This is the one App-layer branch on the
  `ProviderAuth` discriminator and is contained to a single view helper; it
  does not compromise (ui 02 AC9) because the branch is on the auth shape,
  not on a provider ID string.
- **Helper binary depends on `swiftc` at install time.** We compile the
  helper to a native binary when the user clicks "Install helper" (Plan §5)
  rather than shipping a pre-built binary — pre-built binaries would need
  notarization and arch-specific builds, neither of which we have today.
  Claude Code itself requires Swift on macOS, so `swiftc` is almost always
  present; when it isn't, the install aborts with a clear error rather than
  silently leaving the user with no data path.

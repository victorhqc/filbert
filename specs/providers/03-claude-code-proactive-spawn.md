## Objective

Spawn a window-less `claude -p` child process with Haiku when the user
manually clicks the Refresh button so the statusline cache is repopulated
without the user having to switch to Claude Code and prompt manually.

## Context

- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` — new file. Owns
  spawning `claude --model haiku -p …` as a child `Process`, waiting for
  process exit (Haiku + `--max-turns 1` keeps this bounded), then returning.
  Owns the debounce window and in-flight coalescing. Reuses
  `ClaudeCodeLocator` from (providers 02 AC1) for binary resolution.
- `Sources/Core/ProviderProtocol.swift` — adds a new `ProactiveRefreshable`
  protocol alongside `AIProvider`:
  ```swift
  public protocol ProactiveRefreshable: AIProvider {
      func proactiveRefresh() async throws
  }
  ```
  `AIProvider` itself is **unchanged** — no new default methods, no
  protocol-wide default throwing. Providers that want to opt in declare
  conformance to `ProactiveRefreshable`; providers that don't (ZAI today)
  never see the method.
- `Sources/Core/ProviderRegistry.swift` — gains `proactiveRefresh(for:)`
  that downcasts to `ProactiveRefreshable` and calls through, throwing
  `ProviderSetupError.notSupported` when the provider does not conform.
  Mirrors the existing `installHelper(for:)` shape.
- `Sources/App/QuotaViewModel.swift` — gains a `manualRefresh(for:)` entry
  point that calls `registry.proactiveRefresh(for:)` (catching
  `.notSupported` so non-conforming providers behave identically to today)
  and then runs the existing fetch path. The Refresh button is rebound
  from `fetchQuota(for:)` to `manualRefresh(for:)`. The auto-refresh loop
  is **untouched** — scheduling proactive refresh is explicitly deferred to
  a separate spec.
- `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift` — declares
  `extension ClaudeCodeProvider: ProactiveRefreshable` and implements
  `proactiveRefresh()` by delegating to the refresher. `fetchQuota`,
  cache mapping (providers 02 AC5/AC6), and staleness semantics
  (providers 02 AC5b/AC10) are unchanged.
- `Sources/Providers/ClaudeCode/Resources/statusline_helper.swift` —
  unchanged. The helper remains the sole writer of the cache (providers 02
  AC7); the refresher never writes the cache directly.
- Builds on (providers 02). Reverses the "synthetic call explicitly
  rejected" stance documented in (providers 02 Risks): the user has
  accepted the small Haiku quota cost in exchange for fresher data with
  less manual context-switching.
- Related: (core 03) auth shape. This provider is still `.apiKeyFree`;
  the spawn reuses the user's existing Claude Code login and never touches
  the Keychain.

## Acceptance Criteria

### AC1: Refresher spawns `claude -p` with Haiku and minimal flags
- **Given** the `claude` binary is locatable via `ClaudeCodeLocator`
  (providers 02 AC1)
- **When** the provider asks the refresher to refresh
- **Then** the refresher spawns the binary with argv
  `["--model", "haiku", "-p", "--max-turns", "1",
  "--no-session-persistence", "--tools", "", "ok"]` — no `--debug`, no
  interactive TUI, no other flags
- **And** `--model haiku` selects Haiku (cheapest subscription model) so
  the spawn consumes the smallest possible slice of the user's 5h / 7d
  windows (CLI reference: `--model` accepts aliases `sonnet`, `opus`,
  `haiku`, `fable`)
- **And** `--max-turns 1` caps the agent loop at one model call so the
  process can't run away with extra turns
- **And** `--no-session-persistence` prevents the spawn from writing a
  throwaway session under `~/.claude/projects/`
- **And** `--tools ""` disables every tool so the model only emits text
  and cannot run Bash / Edit / etc.
- **And** the refresher does **not** configure `standardInput`,
  `standardOutput`, or `standardError` — the child inherits the parent's
  descriptors, which for a GUI menu-bar app effectively discard the
  response text. The response is intentionally ignored; the cache write
  is the only side effect we care about
- **And** the process inherits an environment where `PATH` includes the
  directory the binary was resolved from, so Claude Code's own subprocess
  lookups still succeed

### AC2: Refresher waits for process exit, with a bounded timeout
- **Given** a spawned `claude -p` process (Haiku + `--max-turns 1`)
- **When** the refresher waits
- **Then** it awaits process exit up to `spawnTimeoutSeconds` (default
  30s). Haiku + one turn typically completes in 1–3s; the timeout is a
  safety net for network hiccups, not the expected path
- **And** on timeout it sends `SIGTERM`, waits a 2s grace, and escalates
  to `SIGKILL` if the process is still alive — never leaves an orphaned
  `claude` behind
- **And** the refresher returns successfully once the process is reaped,
  regardless of its exit code — exit code is diagnostic only

### AC3: Spawn fires only on manual Refresh click — never on auto-refresh
- **Given** the user clicks the Refresh button in the popover for
  `claude-code`
- **When** the view model's `manualRefresh(for:)` runs
- **Then** it first calls `registry.proactiveRefresh(for: "claude-code")`,
  awaits its completion, and only then performs the existing cache read
  via `fetchQuota(for:)`
- **And** the existing auto-refresh loop (5-min cadence from ui 02 AC7)
  and the initial app-launch fetch both still call `fetchQuota(for:)`
  directly — they never spawn `claude`
- **And** `proactiveRefresh(for:)` on `ProviderRegistry` downcasts the
  provider to `ProactiveRefreshable` and throws
  `ProviderSetupError.notSupported` when the provider does not conform —
  the view model catches `.notSupported` and proceeds straight to
  `fetchQuota(for:)`, so non-conforming providers (ZAI today) are
  behaviorally identical to before

### AC4: Spawn is debounced and in-flight clicks coalesce onto one process
- **Given** a successful spawn completed at time `T`
- **When** another manual refresh is requested within
  `spawnDebounceSeconds` (default 60s, matching providers 02 AC9's
  read-debounce window)
- **Then** the refresher skips the spawn entirely and returns immediately
  — the cache read in AC3 still happens, so the user sees the most recent
  cached data, but no second `claude` process is started
- **And** if a spawn is in-flight when a second manual refresh arrives,
  the second caller awaits the same in-flight `Task` — never starts a
  parallel `claude` process
- **And** the debounce timestamp is set on spawn *attempt* (not on
  successful exit), so a failed spawn still suppresses follow-up clicks
  for the debounce window — no spawn storm on repeated errors
- **And** debounce state lives in the refresher (per-provider-instance)
  and is not persisted across app launches

### AC5: Refresher never blocks the UI
- **Given** the menu-bar app is running with the popover open or closed
- **When** the user clicks Refresh for `claude-code`
- **Then** the spawn happens off the main actor — the UI thread is never
  blocked for the spawn duration
- **And** the popover shows the existing `.loading` state for the provider
  while the spawn + cache read is in flight, then transitions to
  `.loaded` / `.error` exactly as today
- **And** the spawned process inherits the GUI app's std streams (AC1),
  so no Terminal window, dialog, or notification is shown by `claude`
- **And** if the user is actively prompting Claude Code in another
  terminal, both processes coexist — the helper's atomic cache write
  (providers 02 AC7) prevents torn reads

### AC6: Spawn diagnostics surface via cache `written_at`
- **Given** the spawn ran and Claude Code invoked the statusline helper
- **When** the provider reads the cache
- **Then** the `written_at` timestamp is newer than the pre-spawn value,
  confirming the spawn successfully triggered the helper
- **And** if `written_at` did NOT advance (helper not installed, workspace
  trust not accepted, spawn failed before any API response, etc.), the
  provider surfaces the resulting "No data" / `.stale` state per
  (providers 02 AC10) — it does NOT retry the spawn in the same refresh
  tick

### AC7: Orthogonality — ZAI and other providers are untouched
- **Given** the change lands
- **When** `swift build` and the ZAI test suite run
- **Then** `ZAIProvider` compiles unchanged, never declares
  `ProactiveRefreshable` conformance, and its network path is unaffected
- **And** the Refresh button rebinds to `manualRefresh(for:)` for **all**
  providers uniformly — there is no App-layer branch on `providerId ==
  "claude-code"` to enable the spawn. Providers that do not conform to
  `ProactiveRefreshable` simply skip it and read the cache / hit the
  network exactly as today

## Plan

1. **New protocol.** Add `ProactiveRefreshable: AIProvider` with a single
   `func proactiveRefresh() async throws` to `ProviderProtocol.swift`.
   `AIProvider` itself is unchanged — no defaults, no protocol-wide
   additions. Only providers that opt in declare conformance (AC7).
   `ProviderRegistry` gains `proactiveRefresh(for:)` that downcasts to
   `ProactiveRefreshable` and throws `ProviderSetupError.notSupported`
   otherwise, mirroring the shape of `installHelper(for:)`.

2. **New file: `ClaudeCodeRefresher.swift`.** A `Sendable` `actor` (the
   in-flight task slot + debounce timestamp require mutation) holding a
   `ClaudeCodeLocator` plus constants `spawnTimeoutSeconds` (30),
   `terminateGraceSeconds` (2), and `spawnDebounceSeconds` (60). Public
   surface: `func refresh() async throws`, callable from the provider.
   Internals: debounce check → in-flight check → spawn → await exit (or
   timeout → SIGTERM → grace → SIGKILL). Uses `Process`; never touches
   `URLSession` or Keychain. Does **not** redirect std streams (AC1).

3. **Provider integration.** `ClaudeCodeProvider.init` grows a `refresher`
   parameter defaulting to `ClaudeCodeRefresher()`. An `extension
   ClaudeCodeProvider: ProactiveRefreshable {}` implements
   `proactiveRefresh()` by delegating to `refresher.refresh()`.
   `fetchQuota` is **unchanged** — it still reads the cache and maps it
   per (providers 02 AC5/AC6). The spawn always happens *before* the
   fetch, on the manual path only (AC3); the cache read sees whatever
   the helper wrote.

4. **View model wiring.** `QuotaViewModel` gains `manualRefresh(for:)`
   that: sets `.loading`, calls `registry.proactiveRefresh(for:)`
   (catching `.notSupported` and proceeding), then runs the existing
   fetch path. The Refresh button is rebound from `fetchQuota(for:)` to
   `manualRefresh(for:)` for **all** providers uniformly. The existing
   auto-refresh loop (`startAutoRefresh`) and the initial app-launch
   fetch still call `fetchQuota(for:)` directly — scheduling the spawn
   is deferred to a separate spec.

5. **Tests.**
   - `ClaudeCodeRefresherTests` — inject a fake binary path pointing at a
     tiny shell script that asserts its argv matches AC1 exactly
     (`--model haiku -p --max-turns 1 --no-session-persistence --tools ""
     ok`) and then sleeps briefly before exiting 0. A second test asserts
     concurrent callers share one OS process. A third asserts a second
     call within `spawnDebounceSeconds` skips the spawn entirely. A
     fourth asserts a hung fake process (sleep 60) is terminated within
     `spawnTimeoutSeconds + terminateGraceSeconds`.
   - `ClaudeCodeProviderTests` extension — assert
     `proactiveRefresh()` delegates to the refresher (use a stub
     refresher), and that `fetchQuota` is unchanged (no spawn
     side-effect, just cache read).
   - `ProviderRegistryTests` extension — assert
     `proactiveRefresh(for:)` calls through to a conforming provider and
     throws `.notSupported` for a non-conforming provider.
   - `QuotaViewModelTests` extension — assert `manualRefresh(for:)`
     calls `proactiveRefresh` then `fetchQuota` for a conforming
     provider, and skips straight to `fetchQuota` for a provider that
     throws `.notSupported`.
   - Orthogonality: ZAI fetch path is unchanged when both providers are
     registered together — mirrors (providers 02 AC12). `ZAIProvider`
     does not declare `ProactiveRefreshable` conformance.

6. **Spec cross-references.** Update (providers 02 Risks) — the
   "synthetic call explicitly rejected" bullet is replaced with a pointer
   to (providers 03) explaining the new stance: a Haiku-billed,
   `--max-turns 1` call whose quota cost is small and bounded by the
   60s debounce. (providers 02 AC9) is unchanged: cache reads remain
   click-debounced; the spawn is gated by the manual click, with its own
   60s debounce window.

No code is written until this spec is reviewed.

## Risks

- **Workspace trust gate.** The statusline command only runs in
  directories where the user has accepted Claude Code's workspace-trust
  dialog (statusline doc, Troubleshooting). When we spawn `claude` from
  the menu-bar app, the CWD we choose must already be trusted or the
  statusline is silently skipped — `claude --debug` logs
  `Status line command skipped: workspace trust not accepted`. Default
  plan: spawn with CWD set to `$HOME`, which is almost always trusted if
  the user has ever run `claude` at all. Mitigation: AC6 surfaces the
  skipped-statusline case as "No data" via `written_at` not advancing —
  it never crashes the app. If `$HOME` proves not to be trusted in
  practice, a follow-up can scan `~/.claude/projects/` for a known-good
  directory or surface a setup hint; that complexity is deferred from
  this spec.
- **Quota cost — small, bounded, accepted by design.** Each manual spawn
  bills one Haiku call with roughly prompt-cache-warm input tokens (~10
  to low hundreds) and a one-token-ish output (`--tools ""` and
  `--max-turns 1` cap the work). The subscription 5h / 7d windows
  advance by a sliver — exactly the signal we want to surface. The
  60s debounce (AC4) bounds worst-case spawns to at most ~60 per hour of
  continuous clicking, which is not a realistic usage pattern. This is
  the explicit trade-off vs. the no-cost / no-data status quo in
  (providers 02).
- **Auth failure is invisible to us.** Claude Code's login state lives
  outside our process. If the user is logged out, `claude -p` exits
  non-zero before any API response, so `rate_limits` is never written
  (statusline doc: `rate_limits` appears only "after the first API
  response in the session"). Mitigation: AC6 surfaces this case as "No
  data" via `written_at` not advancing. We do not proactively detect
  auth state without spawning — there is no documented channel for it.
- **`claude` CLI surface is not versioned.** A future Claude Code release
  could rename `--model`, change Haiku's alias, change `-p` semantics, or
  gate one of our flags behind a different name. Mitigation: the
  refresher swallows non-zero exits (AC2) and the view model never
  surfaces spawn failures as fetch errors (AC3), so a CLI change degrades
  to "no proactive refresh" — the cache read still works as in
  (providers 02). Tests pin the exact argv so a CLI surface drift is
  caught at test time.
- **Orphaned `claude` processes.** If the menu-bar app crashes mid-spawn,
  the child process is left running with no parent waiting. Mitigation:
  AC2 uses `SIGTERM` then `SIGKILL` after a 2s grace; the `Process`
  handle is owned by the refresher's structured task, which is
  cancellable. A separate watchdog is out of scope for v1.
- **`ProactiveRefreshable` extends the Core protocol surface.** Adding a
  new protocol is a smaller change than extending `AIProvider`, but it
  still introduces a new public type in Core that every provider *could*
  conform to. Mitigation: conformance is opt-in and not required; ZAI
  and other providers never see the method (AC7). The protocol is the
  right home because the capability is provider-orthogonal, not specific
  to Claude Code.
- **Statusline helper must already be installed.** The spawn only
  refreshes the cache if the user has clicked "Install helper" in
  Settings (providers 02 AC7). `fetchQuota` already short-circuits when
  not configured per (providers 02 AC3), so the spawn only runs after
  `isConfigured` returns true.

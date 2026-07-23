## Objective

Spawn a window-less `claude -p "/usage"` child process when the user manually
clicks the Refresh button, parse the usage percentages and reset times out of
that command's output, and write the shared cache — so usage refreshes
without the user having to open Claude Code's TUI and prompt manually. This
makes the Refresh button work for users who drive Claude Code through an
editor (e.g. Zed) and never see the interactive status line.

## Discovery — why `-p` cannot reuse the statusline, and what to use instead

The original plan assumed a `claude -p` spawn would trigger Claude Code's
`statusLine` command, which would repopulate the cache via the helper
(providers 02). Empirically that is **false**, and the search for a headless
data source went through two iterations:

- The status line is a **TUI-only** feature. In `--print` / non-interactive
  mode Claude Code never renders it, so the configured `statusLine` command
  (our cache writer) is never invoked and the cache is never written.
- Driving an interactive session headlessly instead (via a PTY) hits the
  workspace-trust gate and is far too fragile to rely on.
- `claude -p … --output-format stream-json --verbose` emits a
  `rate_limit_event` on stdout headlessly, but it carries only reset times +
  status + overage — **no `used_percentage`**. Rejected: the percentage is
  the headline number users want.
- `claude -p "/usage"` prints the **same figures the TUI shows**, headlessly,
  inside the JSON `result` field:
  ```
  Current session: 77% used · resets Jul 21 at 12:59am (Europe/Berlin)
  Current week (all models): 37% used · resets Jul 24 at 5:59am (Europe/Berlin)
  Current week (Fable): 0% used
  ```
  "Current session" is the 5-hour window; "Current week (all models)" is the
  7-day window. This is the data source the refresher uses: it gives the
  percentage **and** the reset time, in the same shape the statusline helper
  writes. `/usage` is model-free, so the spawn costs effectively nothing.
  Trade-off: the text is English-oriented, so parsing is best-effort — an
  unmatched line is skipped, never guessed.

## Context

- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` — new file. Owns
  spawning `claude --model haiku -p "/usage" --output-format json` as a child
  `Process`, waiting for process exit (bounded), capturing stdout, parsing
  the session/week percentages + reset phrases, and **writing the cache
  itself** via `StatuslineCacheStore`. The percentage/reset parsing lives in
  `ClaudeCodeRefresher+Parse.swift`. Owns the debounce window and in-flight
  coalescing. Reuses `ClaudeCodeLocator` from (providers 02 AC1).
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
  `proactiveRefresh()` by delegating to the refresher. `fetchQuota` and
  staleness semantics (providers 02 AC5b/AC10) are unchanged. The cache
  **mapping** handles a `resets_at` that may be absent (reset phrase didn't
  parse): the line then shows the percentage bar without a countdown.
- `Sources/Providers/ClaudeCode/StatuslineCacheStore.swift` — the `Window`
  model's `used_percentage` and `resets_at` are both optional, so a partial
  parse still surfaces what it has. Backward compatible: a statusline-written
  cache (which always has both) decodes unchanged.
- `Sources/Providers/ClaudeCode/Resources/statusline_helper.swift` —
  unchanged. The helper is **no longer the sole writer**: it owns the
  percentage writes during interactive TUI use, and the refresher writes the
  same-shaped percentage windows on the headless `/usage` path. Both use the
  same atomic temp-file + rename contract (providers 02 AC7), so a concurrent
  reader never sees a torn file. The refresher merges per-window over the
  existing cache and only writes when it parsed at least one window, so a
  failed spawn never clobbers previously good data.
- Builds on (providers 02). Reverses the "synthetic call explicitly
  rejected" stance documented in (providers 02 Risks): the user has accepted
  the (near-zero, `/usage` is model-free) spawn cost in exchange for fresher
  data with less manual context-switching.
- Related: (core 03) auth shape. This provider is still `.apiKeyFree`;
  the spawn reuses the user's existing Claude Code login and never touches
  the Keychain.

## Acceptance Criteria

### AC1: Refresher spawns `claude -p "/usage"` in JSON mode
- **Given** the `claude` binary is locatable via `ClaudeCodeLocator`
  (providers 02 AC1)
- **When** the provider asks the refresher to refresh
- **Then** the refresher spawns the binary with argv
  `["--model", "haiku", "--max-turns", "1", "--no-session-persistence",
  "--safe-mode", "--strict-mcp-config", "--no-chrome",
  "--tools", "", "--output-format", "json", "-p", "/usage"]` — no `--debug`,
  no interactive TUI, no other flags. `--safe-mode`, `--strict-mcp-config`,
  and `--no-chrome` are the startup-isolation flags added by
  (providers 06 AC1, AC2); see that spec for why they are distinct from
  Claude's tool-permission modes (providers 06 AC3)
- **And** `-p "/usage"` runs the built-in usage command non-interactively;
  its text output carries the session (5-hour) and week (7-day) percentages
  and reset times. `/usage` is model-free, so the spawn is effectively free
- **And** `--output-format json` wraps that text in a single JSON object so
  the refresher reads it from the `result` field (unlike `stream-json`, this
  does not require `--verbose`)
- **And** `--model haiku` / `--max-turns 1` bound the work in the event
  `/usage` ever triggers a model turn; `--no-session-persistence` prevents a
  throwaway session under `~/.claude/projects/`
- **And** `--tools ""` disables every tool. Because `--tools` is **variadic**
  (`<tools...>`), it must be followed by another flag — never by the
  positional prompt — or the CLI treats `/usage` as a tool name and errors
  with *"Input must be provided … when using --print"*. This is why the
  prompt (`-p "/usage"`) is pinned to the end of the argv
- **And** the refresher spawns the child in an AI Usage-owned directory below
  `FileManager.default.temporaryDirectory`, never the parent's CWD — the
  startup-isolation behavior is specified fully in (providers 06 AC1)
- **And** the refresher captures **stdout** (via a `Pipe`), discards
  **stderr** (`/dev/null`), and does not configure stdin. The `/usage` output
  is a few KB — well under the OS pipe buffer — so stdout is drained after
  the process is reaped
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
- **And** the spawned process's stdout is piped and stderr is discarded
  (AC1), so no Terminal window, dialog, or notification is shown by `claude`
- **And** if the user is actively prompting Claude Code in another
  terminal (which drives the statusline writer), both processes coexist —
  the atomic temp-file + rename cache write (providers 02 AC7), used by the
  refresher too, prevents torn reads

### AC6: Refresh writes the cache from `/usage`, and a barren spawn never clobbers
- **Given** the spawn ran and its `result` text yielded at least one window
- **When** the refresher parses stdout
- **Then** it writes the cache with a fresh `written_at` and the parsed
  window(s) (percentage + reset), merging per-window over any existing cache
- **And** if **no** window parsed (logged out, empty output, output not in
  the expected English shape, spawn failed, etc.), the refresher leaves the
  cache exactly as it was — a failed refresh never overwrites good data with
  an empty one. The provider then surfaces whatever cache exists (or "No
  data" / `.stale` per providers 02 AC10) and does NOT retry in the same tick
- **And** a window whose percentage parsed but whose reset phrase did not
  still surfaces the percentage bar, just without a countdown — a partial
  result is never dropped wholesale

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
   `ClaudeCodeLocator` and a `StatuslineCacheStore` plus constants
   `spawnTimeoutSeconds` (30), `terminateGraceSeconds` (2), and
   `spawnDebounceSeconds` (60). Public surface: `func refresh() async throws`,
   callable from the provider. Internals: debounce check → in-flight check →
   spawn → await exit (or timeout → SIGTERM → grace → SIGKILL) → read piped
   stdout → parse the `/usage` percentages + reset phrases → merge-and-write
   the cache. Parsing lives in `ClaudeCodeRefresher+Parse.swift`. Uses
   `Process`; never touches `URLSession` or Keychain. Captures stdout via a
   `Pipe`, discards stderr (AC1).

3. **Provider integration.** `ClaudeCodeProvider.init` grows a `refresher`
   parameter defaulting to `ClaudeCodeRefresher()`. An `extension
   ClaudeCodeProvider: ProactiveRefreshable {}` implements
   `proactiveRefresh()` by delegating to `refresher.refresh()`.
   `fetchQuota` still reads the cache; its **mapping** tolerates a missing
   `resets_at` (percentage bar without a countdown). The spawn always happens
   *before* the fetch, on the manual path only (AC3); the cache read sees
   whatever the refresher (or the statusline helper) most recently wrote.

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
     tiny shell script that asserts its argv matches AC1 exactly (pinning the
     `/usage` flags and the trailing `-p "/usage"`). One test emits a
     `/usage` JSON payload on stdout and asserts the refresher parsed both
     windows (percentage + reset) into the cache. Focused tests cover
     `parseResetPhrase` across time formats (`12:59am`, `11pm`) and zones.
     One asserts a spawn that emits no usable output leaves an existing cache
     untouched. Others assert concurrent callers share one OS process, a
     second call within `spawnDebounceSeconds` skips the spawn, and a hung
     fake process (sleep 60) is terminated within
     `spawnTimeoutSeconds + terminateGraceSeconds`.
   - `ClaudeCodeProviderProactiveRefreshTests` — assert `proactiveRefresh()`
     delegates to the refresher and that `fetchQuota` never spawns `claude`.
     Percentage mapping is already covered by `ClaudeCodeProviderTests`.
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

Implemented. The *Discovery* section above records the mid-implementation
findings (that `-p` cannot drive the statusline, and that `stream-json` lacks
the percentage) that reshaped the plan to "run `claude -p "/usage"`, parse its
percentages + reset times, and write the cache".

## Risks

- **Workspace trust gate — sidestepped by not using the statusline.** The
  statusline command only renders in an interactive TUI *and* only in a
  trusted workspace. This is precisely why the refresher does **not** rely
  on it: `claude -p` never renders a status line at all, so there is no
  trust prompt and no statusline-skip to worry about. `/usage` prints its
  figures regardless of CWD trust. (Earlier iterations tried to trigger the
  statusline via `-p`, then to read a `stream-json` `rate_limit_event`; see
  the *Discovery* section for why both were abandoned.)
- **Parsing is English-oriented and CLI-format-dependent.** The `/usage`
  output ("Current session: NN% used · resets …") is free text, not a
  stable API. If Claude Code localizes it or rewors it, the regex stops
  matching. Mitigation: an unmatched line is skipped (never guessed), and a
  run that parses nothing leaves the existing cache untouched (AC6) — the
  worst case is a stale-but-not-wrong cache, never a corrupted one. A
  percentage that parses but whose reset phrase doesn't still surfaces the
  bar. `parseResetPhrase` handles the observed time formats (`12:59am`,
  `1am`, `11pm`) and infers the absent year as the nearest occurrence.
- **Quota cost — effectively zero.** `/usage` is a model-free command that
  reports already-tracked usage; it does not consume a 5h / 7d slice the way
  a real model turn would. `--model haiku` / `--max-turns 1` bound the work
  in case a future release routes `/usage` through a model. The 60s debounce
  (AC4) further bounds spawns. This is strictly cheaper than the rejected
  `-p "ok"` approach, which billed one Haiku call per refresh.
- **Auth failure is invisible to us.** Claude Code's login state lives
  outside our process. If the user is logged out, `claude -p "/usage"` won't
  print usable figures. Mitigation: AC6 — with nothing parsed, the refresher
  leaves the existing cache untouched (never clobbers good data) and the
  provider surfaces whatever cache exists / "No data". We do not proactively
  detect auth state without spawning — there is no documented channel for it.
- **`claude` CLI surface is not versioned.** A future Claude Code release
  could rename `--model`, change `-p` semantics, gate one of our flags, or
  change `/usage`'s output. Mitigation: the refresher swallows non-zero exits
  (AC2), the view model never surfaces spawn failures as fetch errors (AC3),
  and a parse miss leaves the cache untouched — so a CLI change degrades to
  "no proactive refresh", with the cache read still working as in
  (providers 02). Tests pin the exact argv so an argv drift is caught early.
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

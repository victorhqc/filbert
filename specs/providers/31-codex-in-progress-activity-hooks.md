## Objective

Add `PostModelRequest` and `PostToolUse` to Filbert's Codex hooks, so a long agentic turn keeps Smart refresh fast while it runs, not only when it starts and ends.

## Context

- Status: approved and implemented 2026-11-09, uncommitted. Extends (providers 30). Signals still go through (core 14) unchanged.
- `Sources/Providers/OpenAICodex/CodexHooksInstaller.swift` — `events` lists the hook events Filbert installs. Install, remove, and status already loop over that list.
- `Sources/Providers/OpenAICodex/Resources/Localizable.xcstrings` — the install description says "two hooks" and the next steps say "trust both Filbert hooks". Both change in every shipped language.
- `Sources/App/QuotaViewModel+ActivitySignals.swift` — each signal records a hint and pulls the next check forward. `automaticRefreshInterval` still applies the minimum interval and the retry gate, so more signals do not mean more requests.
- `Tests/OpenAICodexProviderTests/CodexHooksInstallerTests.swift` — install, remove, and status tests.
- Today a turn signals twice: when the prompt is sent and when the turn stops. A turn that runs for 20 minutes gives no signal in between, so Smart refresh can fall back to its slow cadence while usage keeps rising.

## Evidence

Collected 2026-11-09 from the [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks) and the binaries on the user's Mac.

- **The events exist in every client we use.** The config parser in Codex CLI 0.167.0 and in Zed's bundled Codex 0.166.0 (`codex-acp`) both list `PreModelRequest`, `PostModelRequest`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `SubagentStart`, `SubagentStop`, `Stop`, and `Interrupt`.
- **`PostModelRequest`** runs "after each model request attempt, including retries". Its output is diagnostic only: it cannot change the context or block the request. `matcher` is ignored.
- **`PostToolUse`** runs "after supported tools produce output", including Bash, `apply_patch`, and MCP tools. Hosted tools such as web search are not covered. It honors `matcher`, and an omitted `matcher` matches every tool.
- **No experimental label.** The docs mark no hook as experimental. `hooks` is `stable true` in `codex features list`.
- **Background limit.** Codex runs up to eight background hooks at once per session. Filbert's hook is one `touch`, so it ends in milliseconds.
- **Trust is per event and position.** `~/.codex/config.toml` stores trust under keys such as `"<path>/hooks.json:stop:0:0"`: file, event, group index, handler index, plus a hash of the handler. Install appends a new group, so the user's existing `UserPromptSubmit` and `Stop` trust survives. Only the two new hooks need approval.
- **Not documented:** whether `PostModelRequest` and `PostToolUse` run inside subagents. Plan step 1 checks it.

## Acceptance Criteria

### AC1: Install adds four async hooks

- **Given** the `codex` binary is found
- **When** the user installs activity detection
- **Then** the provider adds one Filbert handler each to `UserPromptSubmit`, `Stop`, `PostModelRequest`, and `PostToolUse`
- **And** the `PostToolUse` group has no `matcher`, so it runs for every tool
- **And** every handler has the same fixed command, `async: true`, and `timeout: 5` as (providers 30 AC1, AC2)
- **And** the rules of (providers 30 AC1, AC3) still hold: other hooks are kept, no duplicates, atomic write, and no edits to `config.toml` or trust state.

### AC2: Existing installs keep their trusted hooks

- **Given** `hooks.json` has Filbert's `UserPromptSubmit` and `Stop` handlers from an earlier version
- **When** the user installs again
- **Then** the provider leaves those two handlers and their groups unchanged and in place
- **And** it appends one group each for `PostModelRequest` and `PostToolUse`
- **And** Codex asks the user to approve only the two new hooks.

### AC3: Status requires all four hooks

- **Given** the provider reads its status (providers 30 AC6)
- **When** any of the four Filbert handlers is missing
- **Then** the status is `notInstalled`
- **And** an install from an earlier version, with only two handlers, reads as `notInstalled` until the user installs again.

### AC4: Remove takes out all four hooks

- **Given** any mix of Filbert's four handlers is installed
- **When** the user removes activity detection
- **Then** the provider removes every Filbert handler from all four events, following (providers 30 AC4).

### AC5: Texts no longer count the hooks

- **Given** the status texts from (providers 30 AC6)
- **When** they are shown
- **Then** the install description says install adds hooks to `~/.codex/hooks.json`, without a number
- **And** the next steps say to trust all Filbert hooks, not "both"
- **And** each text is localized in every shipped language.

### AC6: A long turn keeps signalling

- **Given** the four hooks are installed and trusted
- **When** a Codex turn makes several model requests or tool calls
- **Then** the signal file is touched after each of them, and the provider emits signals while the turn runs, coalesced as in (providers 30 AC5)
- **And** the App's request rate stays within the minimum interval and the retry gate (core 14 AC4).

## Plan

1. [-] **Skipped 2026-11-09 by user decision.** Filbert trusts the documented behavior. If the new hooks do not fire, detection falls back to turn start and end, as in (providers 30). Original step: **Verify first, by hand.** Append the two new groups to `~/.codex/hooks.json` in the exact form Filbert will write. Approve them with `/hooks`, and confirm `/hooks` asks only about the two new ones. Run one long CLI turn with several tool calls and one Zed turn, and record the signal file's modification times during each turn. If a subagent is easy to start, record whether its requests touch the file too. Write the results to Evidence. If `PostModelRequest` does not fire mid-turn, stop and update this spec.
2. [x] Test first: extend the installer tests for four events, an upgrade from a two-handler file (AC2), status with three of four handlers, and removal from a mixed file (AC1–AC4).
3. [x] Add `PostModelRequest` and `PostToolUse` to `CodexHooksInstaller.events`. Install already skips events that have Filbert's handler, so AC2 needs no new logic.
4. [x] Reword the two texts and their translations (AC5). The string keys change, so update the catalog entries in place.
5. [x] Run the full validation gate.

## Findings

- 2026-11-09: steps 2–5 implemented. The full validation gate passes.
- No installer logic changed. Install already skipped events that hold Filbert's handler and appended the rest, so the upgrade test passed on the new event list alone.
- AC6 has no unit test of its own. The installer tests pin the four events, and the watcher tests from (providers 30) already cover coalescing.
- The reworded texts need a native review, as earlier localized strings did.

## Risks

- **Silent partial upgrade.** After reinstalling, the old trusted hooks fire on the first prompt, so the status turns `active` even if the user never approves the two new hooks. Signals then work as in (providers 30), just less often. The next-steps text is shown right after install, so the user sees the request to trust all hooks once. A separate signal file for the new hooks could detect this, but it would change the fixed command for those hooks. Not worth it for now.
- **Existing users see `notInstalled`.** Users on (providers 30) see "not installed" in Settings after the update, though their two hooks still fire and still signal. The popover does not nag them, because it only shows for `awaitingFirstSignal` (ui 41). The release notes should tell them to install again.
- **More hook runs.** `PostModelRequest` can fire every few seconds in a busy turn. Each run is one `touch`, and the watcher coalesces bursts within one second.
- **Subagents.** If the new hooks do not run inside subagents, a turn that hands most work to subagents still signals less often. `SubagentStart` and `SubagentStop` could be added later.

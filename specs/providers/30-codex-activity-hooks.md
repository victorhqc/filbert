## Objective

Install two Codex hooks that tell Filbert when a Codex turn starts or ends, in any Codex client, so Smart refresh can follow Codex work automatically.

## Context

- Status: picked up 2026-11-09, awaiting review. First drafted 2026-10-23. Implements the capability from (core 14). Its Settings UI is a separate, still unnumbered draft.
- `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` — reads usage through `account/rateLimits/read` on the local app server (providers 05). That stays the only usage source. The hooks only signal activity.
- `Sources/Providers/OpenAICodex/CodexLocator.swift` — finds the `codex` binary. Install is unavailable without it.
- `Sources/Providers/ClaudeCode/StatuslineHelperInstaller.swift` — the precedent for editing another tool's config: merge into it, mark Filbert's entry, and restore it on removal (providers 02).
- `Tests/OpenAICodexProviderTests/` — new installer, status, and watcher tests.
- Today a Codex turn reaches Filbert only when a slow poll sees a usage change or the user refreshes by hand.

## Evidence

Collected 2026-10-23 on the user's Mac and from the [Codex hooks documentation](https://learn.chatgpt.com/docs/hooks).

- **Hooks are stable and on by default.** `codex features list` on Codex 0.145.0 prints `hooks stable true`.
- **Config files.** Codex reads hooks from `~/.codex/hooks.json` or from an inline `[hooks]` table in `~/.codex/config.toml`. If one layer has both, Codex merges them and warns at startup.
- **Format.** `{"hooks": {"<Event>": [{"matcher": "...", "hooks": [{"type": "command", "command": "...", "async": true, "timeout": 600}]}]}}`. `matcher` is ignored for `UserPromptSubmit` and `Stop`.
- **Input.** Every command hook receives one JSON object on stdin with `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`, and, for turn events, `turn_id`. No usage or rate-limit fields.
- **Async.** `"async": true` runs the hook in the background. It cannot block or change the turn.
- **Trust.** Codex skips a new or changed non-managed hook until the user trusts it with `/hooks` in the CLI. Trust is recorded against the hook's hash in `~/.codex`.
- **Zed and other ACP clients.** Zed's Codex agent is `@agentclientprotocol/codex-acp` 2.2.2. It wraps `codex app-server` and ships its own `codex` binary. That binary contains the hook engine, including `UserPromptSubmit`, `Stop`, `transcript_path`, and `trusted_hash`. `~/.codex/state_5.sqlite` has a thread with `originator = zed`, so Zed uses the same `~/.codex`. Plan step 1 confirmed that the hook fires for a Zed turn.
- **Rechecked 2026-11-09.** Codex is still 0.145.0 with `hooks stable true`. `~/.codex/hooks.json` does not exist yet, and `CODEX_HOME` is unset. Zed still runs `codex-acp` from its agent registry.
- **CLI hook fires (2026-11-09).** A temporary async `Stop` hook, `/usr/bin/touch '/tmp/filbert-hook-check'`, updated the file at 10:53:55 during a `codex-tui` turn. Codex had updated itself to 0.167.0 at 10:50, and `hooks` is still `stable true`. The single-quoted path worked, so Codex runs `command` through a shell. A second CLI turn touched it again at 10:58:35, and Codex showed no hook error or warning.
- **Zed hook fires (2026-11-09).** With the same hook, a turn from Zed's Codex agent touched the file at 11:01:55. `state_5.sqlite` records that thread with `originator = zed` and `cli_version = 0.166.0`, the binary bundled in `codex-acp`. The turn finished at 11:01:54. The user had trusted the hook once in the CLI, and Zed ran it without another review, so trust in `~/.codex` covers every client.
- **Command form is not documented.** `command` is a string in every example, but the docs do not say whether Codex runs it through a shell. The examples use `$(…)` and embedded quotes, which suggests a shell. Plan step 1 confirms it with the real command form.
- **Empty output is success.** A hook that exits `0` with no output is treated as success. `Stop` rejects plain-text stdout, so the hook command must print nothing.
- **Trust in the app too.** The Codex desktop app trusts hooks under Settings > Hooks, as well as `/hooks` in the CLI.
- **No self-trigger.** Filbert's own reads write to `~/.codex/logs_2.sqlite` but start no turn. No session file changed between 2026-10-07 and 2026-10-23 while Filbert kept polling.

## Acceptance Criteria

### AC1: Install adds two async hooks to `~/.codex/hooks.json`

- **Given** the `codex` binary is found
- **When** the user installs activity detection
- **Then** the provider adds one `UserPromptSubmit` handler and one `Stop` handler to `~/.codex/hooks.json`
- **And** each handler is `type: "command"`, `async: true`, with `timeout: 5`
- **And** the provider creates the file, with `{"hooks": {...}}`, when it does not exist
- **And** every other key, event, group, and handler in the file is kept unchanged
- **And** a second install adds no duplicate handlers
- **And** the write is atomic
- **And** the provider never edits `~/.codex/config.toml`, never changes the `hooks` feature flag, and never writes trust state.

### AC2: The hook command is fixed, local, and content-free

- **Given** the hooks are installed
- **When** Codex runs either hook
- **Then** the command only updates the modification time of one signal file in Filbert's cache directory, `~/.cache/filbert/codex-activity`
- **And** the command does not read stdin, store the hook payload, or make a network request
- **And** the command string is the same across Filbert updates, so an update does not invalidate the user's trust
- **And** the command still works when Filbert is not running.

### AC3: Install never damages the user's hook config

- **Given** `~/.codex/hooks.json` exists but is not valid JSON, or has a shape the provider does not recognize
- **When** the user installs or removes activity detection
- **Then** the provider leaves the file unchanged and reports an error with the file path
- **And** the error is logged without file content (core 10).

### AC4: Remove restores the user's config

- **Given** the hooks are installed
- **When** the user removes activity detection
- **Then** the provider removes only handlers whose command matches Filbert's command exactly
- **And** it removes a group or event only when Filbert's removal left it empty
- **And** it deletes the file only when nothing else is left in it
- **And** it deletes the signal file.

### AC5: The provider signals only on Codex turns

- **Given** the hooks are installed and Codex is enabled in Filbert
- **When** the signal file's modification time changes
- **Then** the provider emits one activity signal (core 14 AC1)
- **And** changes within one second are coalesced into one signal
- **And** Filbert's own `account/rateLimits/read` calls never emit a signal (core 14 AC7)
- **And** the provider watches with a file-system event source that reports a modification-time change on an existing file, not by polling
- **And** the watcher survives the signal file being created, replaced, or deleted.

### AC6: Status reflects install and trust

- **Given** the provider reports its signal status (core 14 AC2)
- **When** the status is read
- **Then** it is `unavailable` with the existing "Codex CLI not installed" reason when the binary is missing
- **And** it is `notInstalled` when either handler is missing from `~/.codex/hooks.json`
- **And** it is `awaitingFirstSignal` when both handlers are present and no signal file exists
- **And** it is `active` when both handlers are present and the signal file exists
- **And** install deletes any existing signal file, so only a hook run after install can make the status `active`
- **And** the `awaitingFirstSignal` text tells the user to trust Filbert's two hooks, with `/hooks` in the Codex CLI or Settings > Hooks in the Codex app.

### AC7: Usage reads are unchanged

- **Given** activity detection is installed, missing, or awaiting trust
- **When** the provider fetches usage
- **Then** `fetchQuota`, its mapping, and its observations behave as in (providers 05) and (providers 18)
- **And** the provider's `setup` state does not depend on the hooks.

## Plan

1. [x] **Verify Zed first.** Add a temporary async `Stop` hook by hand, in the exact form Filbert will install: `/usr/bin/touch` with the quoted absolute path to a file in `/tmp`. Trust it, send one prompt from Zed's Codex agent, and check the file's modification time. Repeat with the CLI and record both results in Evidence. This also confirms the command form and that Codex shows no error. If the Zed hook does not fire, stop and update this spec before any code is written.
2. [x] Add `CodexHooksInstaller` with install, remove, and status read over an injectable `hooks.json` URL and signal-file URL (AC1, AC3, AC4, AC6). Use Core's `AnyJSON` so unknown keys survive the round trip.
3. [x] Build the hook command as `/usr/bin/touch` with the quoted absolute path to the signal file, in the form step 1 confirmed (AC2).
4. [x] Add a watcher with FSEvents on the signal file's directory, with file-level events, events since now only, and a one-second latency that also coalesces bursts. It emits into an `AsyncStream<Date>` and stops when the stream terminates (AC5). A `DispatchSource` on the directory does not fire when `touch` updates an existing file, so it would miss every turn after the first.
5. [x] Make `OpenAICodexProvider` conform to `ActivitySignaling` (core 14).
6. [x] Localize the status and error texts in every shipped language.
7. [x] Tests: install on a missing file, an empty file, a file with other hooks, and an inline-`[hooks]` user; remove in each case; invalid JSON; idempotence; status per state; coalescing; the watcher across file deletion.

## Findings

- 2026-11-09: steps 2–7 implemented. The full validation gate passes. The installer, watcher, and provider tests passed 8 repeated runs; the watcher tests alone passed 12 more.
- `AnyJSON` replaces `JSONSerialization`, because SwiftLint bans `Any` in `Sources/`. The rewrite keeps every key and value, but it sorts keys and pretty-prints the file. Numbers pass through `Double`, so an integer above 2^53 would lose precision. Hook files hold small timeouts, so this is acceptable.
- A provider module cannot declare a type alias: the launch smoke test in `scripts/test-local-signing.py` parses provider sources and rejects it.
- An empty or whitespace-only `hooks.json` counts as no hooks. Install writes Filbert's handlers into it.
- Install creates `~/.cache/filbert/` so the hook's `touch` has a directory to write into. The watcher creates it too, before it starts.
- An unreadable `hooks.json` makes the status `notInstalled` with the same error text as AC3, so the UI can explain why install will fail.
- The watcher emits only when the signal file exists after the event batch, so the deletion by remove or reinstall never produces a signal.
- AC3 logging: the error is a `DiagnosticError` with the codes `hooks-file-unreadable` and `hooks-file-unrecognized`. `ErrorLog` records only codes, never messages or file content. The App's install action, in the UI spec, records it.
- (core 14 AC7) now has its test: a real fetch through a fake `codex` app server, with the watcher running, produces no signal.
- The new strings need a native review, as earlier localized strings did. "Settings > Hooks" stays in English, because it names the Codex app's own menu.

## Risks

- **`CODEX_HOME`.** A user who sets `CODEX_HOME` in their shell keeps their config elsewhere. Filbert is a GUI app and does not see that variable, so it would edit `~/.codex` and the hooks would never fire. The status would stay at `awaitingFirstSignal`. Out of scope for now.
- **Inline `[hooks]` users.** If `config.toml` already has `[hooks]`, adding `hooks.json` makes Codex warn at startup. The hooks still run. Settings could mention it if this proves common.
- **Hooks turned off.** A user with `[features] hooks = false` stays at `awaitingFirstSignal`. The status text should name this cause.
- **Hook format drift.** The hooks format is documented but new. A breaking change would surface as `notInstalled` or `awaitingFirstSignal`, never as a usage failure (AC7).
- **Trust friction.** Users must run the Codex CLI once to trust the hooks, even if they only use Codex through Zed or VS Code.

## Objective

Prevent the headless Claude Code refresh from probing macOS-protected user locations during startup, without weakening Claude Code's tool-permission policy or claiming to sandbox the child process.

## Context

- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` — owns the child
  process arguments, environment, and working directory.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherTests.swift` — verifies
  the exact argv.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherWorkingDirectoryTests.swift`
  — verifies the child's working directory and the directory-creation failure
  path (AC5).
- `packaging/Filbert.entitlements` — currently has no App Sandbox entitlement.
  This remains unchanged.
- Extends the proactive spawn in (providers 03). Its AC1 is the authoritative
  argv contract and is revised by this spec.
- `--permission-mode bypassPermissions` and
  `--dangerously-skip-permissions` are not TCC controls. Anthropic documents
  them as modes that skip Claude Code's approval layer for agent tool use.
  They neither remove filesystem access from the `claude` process nor prevent
  its startup code from touching protected paths. Adding both would also not
  provide compatibility: a CLI that does not recognize the first flag exits
  during argument parsing before the second flag can act as a fallback.
- Claude Code reads project and user configuration at startup. That surface
  includes CLAUDE.md files, settings, skills, plugins, hooks, MCP servers,
  status-line commands, and project state. A child that inherits an unsuitable
  working directory can therefore inspect that directory and its parents
  before the model or a built-in command uses any tool.
- Claude Code 2.1.169 introduced `--safe-mode`. Anthropic documents it as
  disabling startup customizations while leaving authentication, model
  selection, built-in tools, and permissions working normally:
  https://code.claude.com/docs/en/cli-usage.
- `--bare` is not suitable. It also minimizes startup, but disables OAuth and
  macOS Keychain reads; the refresher must reuse the user's existing Claude
  Code login.
- Apple's `Process` documentation states that a subprocess inherits its
  parent's current directory unless the caller sets one explicitly:
  https://developer.apple.com/documentation/foundation/process.
- There is no supported per-child macOS sandbox that can be added as a small
  wrapper around an arbitrary external executable. App Sandbox applies to the
  app and its `Process` children, and a sandboxed app cannot normally execute
  a program outside its bundle, container, or app-group containers. Adopting
  it would be an app-wide architecture and storage migration, not a refresher
  flag change:
  https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox.
  The older `sandbox-exec` / `sandbox_init` interfaces are deprecated and are
  not a supported production boundary.

## Acceptance Criteria

### AC1: Spawn starts in a dedicated temporary directory

- **Given** Filbert is about to start the `claude` child
- **When** it configures `Process`
- **Then** it creates a Filbert-owned directory below
  `FileManager.default.temporaryDirectory` and assigns that URL to
  `process.currentDirectoryURL`
- **And** the directory is not the user's home, Documents, Desktop, Downloads,
  Music, the app's source checkout, or another user-selected project
- **And** failure to create the directory aborts that refresh attempt and
  leaves the existing usage cache untouched

### AC2: Spawn disables Claude Code startup customizations

- **Given** a supported Claude Code release is locatable through
  `ClaudeCodeLocator` (providers 02 AC1)
- **When** the refresher spawns it (providers 03 AC1)
- **Then** argv includes `--safe-mode`, which disables non-managed CLAUDE.md
  discovery, skills, plugins, hooks, MCP servers, custom commands and agents,
  output styles, status-line commands, LSP servers, and auto-memory
- **And** argv includes `--strict-mcp-config` without `--mcp-config`, so no
  user, project, or local MCP server is loaded
- **And** argv includes `--no-chrome`, so the refresh does not initialize the
  optional Chrome integration
- **And** authentication still uses Claude Code's normal signed-in state;
  `--bare` is not passed

### AC3: Spawn does not bypass Claude Code permissions

- **Given** the `/usage` refresh already passes `--tools ""`
  (providers 03 AC1)
- **When** the child starts
- **Then** argv contains neither `--permission-mode bypassPermissions` nor
  `--dangerously-skip-permissions`
- **And** this spec makes no claim that a Claude permission mode can grant,
  deny, or suppress a macOS TCC decision

### AC4: The documented argv is updated

- **Given** a reader opens (providers 03 AC1)
- **When** they inspect the argv literal
- **Then** it matches `ClaudeCodeRefresher.spawnArguments`, including
  `--safe-mode`, `--strict-mcp-config`, and `--no-chrome`
- **And** the explanation cites the startup-isolation behavior as
  (providers 06 AC1, AC2)
- **And** the variadic `--tools ""` argument still has another flag to its
  right before the terminal `-p "/usage"` pair

### AC5: Automated tests verify argv and working-directory isolation

- **Given** `ClaudeCodeRefresherTests`
- **When** the argv test runs
- **Then** its expected value continues to derive from
  `ClaudeCodeRefresher.spawnArguments`, with no hardcoded duplicate
- **And** a fake child records `$PWD` and the test proves it ran in the
  injected temporary working directory rather than the test runner's current
  directory
- **And** a directory-creation failure test proves no child starts and no
  existing cache is overwritten

### AC6: A clean macOS account receives no protected-resource prompts

- **Given** a non-managed macOS account where Filbert has never been granted
  Music, Documents, Desktop, or Downloads access and Claude Code is 2.1.169 or
  newer
- **When** the user clicks Refresh for Claude Code
- **Then** no TCC prompt appears for those resources
- **And** `/usage` still refreshes the cached session and weekly figures
- **And** this result is verified manually because CI has neither the macOS
  TCC interaction layer nor a signed-in real Claude Code installation

### AC7: Unsupported Claude Code versions fail safely

- **Given** a Claude Code version older than 2.1.169 does not recognize
  `--safe-mode`
- **When** the refresher attempts to run the documented argv
- **Then** the child exits without producing usage data
- **And** the barren-spawn behavior in (providers 03 AC6) leaves the prior
  cache untouched, so the app shows stale data rather than crashing or
  retrying without `--safe-mode`
- **And** the refresher never falls back to a less isolated argv

## Plan

1. [x] Add a working-directory dependency to `ClaudeCodeRefresher`, defaulting
   to a Filbert-specific child of `FileManager.default.temporaryDirectory`.
   Create it immediately before each spawn and set
   `Process.currentDirectoryURL` before `run()`.
2. [x] Add `--safe-mode`, `--strict-mcp-config`, and `--no-chrome` to
   `spawnArguments`. Keep `--tools ""` before another flag and keep
   `-p "/usage"` last.
3. [x] Update (providers 03 AC1) and the explanatory comment above
   `spawnArguments` to distinguish startup isolation from Claude's
   tool-permission modes.
4. [x] Extend `ClaudeCodeRefresherTests` with an injected temporary working
   directory, a `$PWD` assertion, and a directory-creation failure case. Keep
   the existing derived argv assertion.
5. [x] Run the focused Claude Code provider tests, the full test suite, and
   the manual clean-account TCC check in AC6 before considering the behavior
   verified. Automated tests pass; **AC6 remains a manual release gate.**

## Risks

- **This is not an OS sandbox.** The child still runs with the invoking user's
  OS identity. The mitigation removes known startup discovery paths and
  supplies an inert working directory; it does not form a kernel-enforced
  filesystem allowlist. If strict containment becomes a product requirement,
  it needs a separate architecture spec that evaluates app-wide App Sandbox
  adoption or an embedded, signed helper.
- **Managed policy can still run managed behavior.** Anthropic documents that
  `--safe-mode` preserves managed settings policy. AC6 therefore scopes the
  manual guarantee to a non-managed account. Enterprise behavior must be
  tested against the organization's managed Claude Code configuration.
- **Old Claude Code releases cannot refresh.** Versions before 2.1.169 reject
  `--safe-mode`. Retrying without it would reintroduce the protected-location
  probes, so stale data is the safer result.
- **Future CLI drift.** Anthropic may rename flags or change what safe mode
  disables. A failed spawn remains non-destructive under (providers 03 AC6),
  while AC5 pins the argv contract and AC6 checks the user-visible TCC result.
- **The exact original probe is not proven by unit tests.** A working-directory
  change and safe mode address the documented startup discovery surfaces.
  Manual TCC verification remains the release gate for the actual OS behavior.

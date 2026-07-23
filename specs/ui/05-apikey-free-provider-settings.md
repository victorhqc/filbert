## Objective

Render a distinct Settings row variant for `.apiKeyFree` providers (today:
Claude Code) that replaces the API-key field with an "Install helper" /
"Remove helper" control, hides the base-URL override, and surfaces the
provider's own configuration state — without branching the popover on a
provider ID.

## Context

- `Sources/App/SettingsView.swift` — currently renders one
  `ProviderSettingsRow` per registered provider. Every row assumes the
  `.apiKey` shape: a `SecureField` for the key, Save/Clear buttons, and the
  Advanced base-URL disclosure (ui 03). For `.apiKeyFree` providers none of
  that applies, so the row is dispatched to a new `APIKeyFreeSettingsRow`
  variant by inspecting `ProviderInfo.authShape` from (core 03).
- `Sources/App/QuotaView.swift` — the per-provider section in the popover
  ends with a "Clear Key" button today (ui 04). That button is meaningless
  for `.apiKeyFree` providers (no key exists) and is suppressed when
  `authShape == .apiKeyFree`. The rest of the section is unchanged — Claude
  Code renders as a normal `ProviderQuota`.
- `Sources/App/QuotaViewModel.swift` — today owns `saveKey(_:for:)` /
  `deleteKey(for:)` for the `.apiKey` path and the override accessors from
  (ui 03). It now also owns install/uninstall actions for the Claude Code
  helper (delegating to `StatuslineHelperInstaller` from providers 02) and
  surfaces a richer setup state via the extended `ProviderState` from
  (providers 02 Plan §3 / core 03 AC6).
- `Sources/Core/ProviderProtocol.swift` — `ProviderInfo` gains an
  `authShape: ProviderAuth.Shape` field so the App layer can dispatch row
  variants on the discriminator, not on a provider ID. Specified in
  (core 03).
- Builds on the orthogonal architecture in (core 01) and (ui 02 AC9): the
  Settings list and popover are still driven by the registry; the new row
  variant is selected by `authShape`, never by `providerId == "claude-code"`.
- Reference implementation patterns: the existing `ProviderSettingsRow` in
  `SettingsView.swift` (API-key field + Advanced disclosure), and the
  `errorContent` / `loadingContent` patterns in `QuotaView.swift` for
  state-driven section bodies.

## Acceptance Criteria

### AC1: Settings list dispatches row variants by `authShape`
- **Given** the Settings window is rendering its provider list
- **When** it iterates `viewModel.registeredProvidersSorted`
- **Then** for each `ProviderInfo` it inspects `info.authShape`
- **And** when `authShape == .apiKey` it renders the existing
  `ProviderSettingsRow` (key field, badge, Advanced disclosure — unchanged
  from ui 02 / ui 03)
- **And** when `authShape == .apiKeyFree` it renders the new
  `APIKeyFreeSettingsRow`
- **And** the dispatch is on `authShape`, never on a provider ID string

### AC2: `APIKeyFreeSettingsRow` shows display info + setup state
- **Given** a `.apiKeyFree` provider is rendered in Settings
- **When** its row renders
- **Then** it shows the same display-name + description + badge header as
  the `.apiKey` row (ui 02 AC2), so the visual rhythm of the list is
  preserved
- **And** the badge reflects the provider's setup state surfaced via the
  extended `ProviderState`: `setup(...)` → "Setup needed" (muted),
  `loaded` → "Ready" (green), `error` → "Error" (red), matching the colour
  conventions of the existing Configured/Unconfigured badge

### AC3: When `claude` binary is missing, the row shows an actionable message
- **Given** `ClaudeCodeLocator.resolve()` returns `nil` (binary not on PATH
  or in known install dirs — providers 02 AC1)
- **When** the row renders
- **Then** the body shows "Claude Code was not found. Install it from
  claude.com and reopen Settings." with no Install button (installing the
  helper is pointless without the binary)
- **And** the row surfaces this as a `setup` state via the view model so
  the popover omits this provider from its live-quota list (ui 02 AC3:
  unconfigured providers are absent from the popover, not disabled)

### AC4: When the binary is present but the helper is not installed, the row shows "Install helper"
- **Given** the binary is locatable and `StatuslineHelperInstaller` reports
  the helper is not installed in `~/.claude/settings.json`
- **When** the row renders
- **Then** the body shows a short explanation ("Filbert reads your Claude
  Code usage by hooking into its status line. This adds a small helper
  script to ~/.claude/.") followed by an "Install Helper" button
- **And** clicking the button calls
  `viewModel.installHelper(for: providerId)`, which compiles the Swift
  helper source and chains into the user's existing `statusLine.command`
  per (providers 02 AC7/AC8)
- **And** the row surfaces transient feedback during install ("Installing…")
  and on success transitions to the AC5 state

### AC5: When the helper is installed, the row shows "Remove helper" + path
- **Given** the helper is installed and the chain entry exists in
  `~/.claude/settings.json`
- **When** the row renders
- **Then** the body shows the helper binary path
  (`~/.claude/filbert-statusline`) as monospaced secondary text, and a
  "Remove Helper" button
- **And** clicking the button calls
  `viewModel.removeHelper(for: providerId)`, which unchains and deletes
  the helper per (providers 02 AC11)
- **And** no "Install Helper" button is shown at the same time — the two
  states are mutually exclusive

### AC6: `APIKeyFreeSettingsRow` has no base-URL override
- **Given** a `.apiKeyFree` provider's row is rendered
- **When** the user looks for the Advanced disclosure (ui 03)
- **Then** it is absent — `.apiKeyFree` providers do not make HTTP requests
  to an overridable host, so the concept does not apply
- **And** no override can be saved for them via any path (the view-model
  override accessors are a no-op or throw when called with a `.apiKeyFree`
  provider ID)

### AC7: Helper install/uninstall errors surface inline
- **Given** an install or uninstall fails (e.g. `swiftc` not on PATH,
  `~/.claude/settings.json` unparseable per providers 02 AC8, write
  permission denied)
- **When** the operation fails
- **Then** the row shows the error message inline beneath the action
  button, in the same red-caption style as the existing override editor's
  error (ui 03 AC3)
- **And** the row stays in its prior state — a failed install does not
  flip the badge to "Ready", a failed uninstall does not flip it to
  "Setup needed"

### AC8: Popover suppresses "Clear Key" for `.apiKeyFree` providers
- **Given** the popover is rendering a `.apiKeyFree` provider's section in
  the `loaded` state
- **When** the section footer renders
- **Then** the "Clear Key" button from (ui 04) is omitted — there is no key
  to clear
- **And** the Refresh button and "Last updated" label still render (Claude
  Code has a refresh action — it re-reads the cache file, providers 02 AC9)
- **And** this suppression is gated on `authShape == .apiKeyFree`, not on a
  provider ID string

### AC9: Popover shows stale-cache hint for `.apiKeyFree` providers
- **Given** a `.apiKeyFree` provider's `ProviderQuota.isStale == true`
  (the provider set the flag based on its own freshness threshold —
  providers 02 AC5b)
- **When** the popover renders that provider's section
- **Then** beneath the headline and usage lines it shows two muted lines:
  "Last updated by Claude Code: 3h ago" and "Open Claude Code to refresh"
- **And** the hint is gated on `quota.isStale`, not on a recomputed
  threshold in the App layer — the UI never knows what "stale" means for
  any given provider, it just reads the flag
- **And** `.apiKey` providers never set `isStale == true` today (their data
  comes from a direct API call), so they never trigger the hint

### AC10: Setup state is surfaced through the existing `ProviderState` channel
- **Given** a `.apiKeyFree` provider is in any of its setup states (binary
  missing, helper missing, helper installed)
- **When** the view model updates its state
- **Then** the popover and Settings row both read from the same
  `[String: ProviderState]` map as `.apiKey` providers — there is no
  parallel state channel for `.apiKeyFree`
- **And** the extended `ProviderState.setup(String)` case from (core 03
  AC6) carries the human-readable reason that both surfaces render

### AC11: Orthogonality holds — adding a future `.apiKeyFree` provider requires no App edits beyond registration
- **Given** a new `.apiKeyFree` provider module conforming to `AIProvider`
- **When** it is registered in `AppMain.init()` (one line) and linked in
  `Package.swift`
- **Then** it renders via `APIKeyFreeSettingsRow` with no further edits to
  `SettingsView`, `QuotaView`, or `QuotaViewModel` — preserving (ui 02 AC9)
- **And** if its setup flow differs from Claude Code's (different helper
  script, different install path), it surfaces that through its own
  `ProviderState.setup(...)` payload, not through new App-layer branches

### AC12: All UI strings are localized
- **Given** the app running under a non-English locale
- **When** any new string renders (badge labels, install/remove buttons,
  setup messages, stale-cache hints, errors)
- **Then** every user-facing string goes through `String(localized:)` — no
  hard-coded English literals, matching (ui 01 AC7), (ui 02 AC10), and
  (ui 03 AC8)

## Plan

1. **Core: extend `ProviderInfo` with `authShape`.** Specified in (core 03).
   The App layer reads it; it never reads a provider ID to dispatch UI. [ ]
2. **ViewModel: helper install/uninstall actions.** Add
   `installHelper(for:)` and `removeHelper(for:)` on `QuotaViewModel`,
   delegating to `StatuslineHelperInstaller` from (providers 02). Both
   update the per-provider `ProviderState` (loading during the operation,
   then the resulting `setup(...)` / `loaded` / `error(...)` state). The
   view model does not know it is Claude Code — it calls a protocol method
   on the provider that returns an installer handle, or throws if the
   provider does not support helper install (future `.apiKeyFree`
   providers may have a different setup mechanism). [ ]
3. **SettingsView: dispatch row by `authShape`.** Replace the unconditional
   `ProviderSettingsRow(provider:…)` with a switch on `provider.authShape`:
   `.apiKey` → existing row (unchanged); `.apiKeyFree` → new
   `APIKeyFreeSettingsRow`. [ ]
4. **SettingsView: `APIKeyFreeSettingsRow`.** A new private struct with
   the same header layout as `ProviderSettingsRow` (display name +
   description + state badge) and a body that switches on setup state:
   - binary missing → actionable message + link, no button
   - helper not installed → explanation + "Install Helper" button
   - helper installed → path display + "Remove Helper" button
   - transient error → inline red caption above the action button
   The row takes the same callback shape as the existing row
   (`onInstall`, `onRemove`, plus a state value), keeping the parent
   `SettingsView` free of provider-specific logic. [ ]
5. **QuotaView: suppress "Clear Key" for `.apiKeyFree`.** In
   `quotaContent(_:providerId:)`, look up the provider's `authShape` via
   the registry (or via a small `isAPIKeyFree(providerId:)` helper on the
   view model that delegates to the registry) and omit the "Clear Key"
   button when it is `.apiKeyFree`. The rest of the footer (Refresh +
   Last updated) is unchanged. [ ]
6. **QuotaView: stale-cache hint.** When `quota.isStale == true` (the
   flag set by the provider per providers 02 AC5b), render the two muted
   hint lines beneath the usage rows. The UI does not compute freshness —
   it reads the flag. [ ]
7. **Tests.** As in (ui 03), view-level tests are limited without a UI host;
   cover what is testable at the view-model layer:
   - `installHelper(for:)` delegates to the installer and updates state to
     `loaded` on success, `error(...)` on failure (installer stubbed).
   - `removeHelper(for:)` mirrors the above.
   - `isAPIKeyFree(providerId:)` returns the right value for both ZAI and
     Claude Code by inspecting the registry.
   SwiftUI wiring is verified by manual review, matching the existing
   pattern. [ ]
8. **`Package.swift`.** No changes — no new module. [ ]

No code is written until this spec is reviewed.

## Risks

- **`ProviderInfo.authShape` is a new field on a public Core type.** It is
  additive and specified in (core 03), but every `ProviderInfo` initializer
  call site needs updating. Today that's only `ProviderRegistry`, so the
  blast radius is one file; flagged so it isn't a surprise during
  implementation.
- **`ProviderQuota.isStale` is the single source of truth for freshness.**
  Earlier drafts had the threshold duplicated between the provider and the
  UI; resolved by having the provider own the flag (providers 02 AC5b) and
  the UI only read it. Adding a future `.apiKeyFree` provider with a
  different freshness rule (e.g. 15 minutes) requires no App change —
  orthogonality holds.
- **"Open Claude Code to refresh" is a passive hint, not an action.** AC9
  intentionally does not provide a button that launches Claude Code —
  spawning another app from a menu-bar popover is surprising UX and
  Claude Code is a CLI that may not have a clean `open` target. The hint
  is text-only. If we later want an action, that's a follow-up.
- **Error messages from the installer are technical.** A failed `swiftc`
  compile or an unparseable `settings.json` produces a low-level error
  string. AC7 surfaces it verbatim in the red-caption style; we accept
  the technical message because (a) it's accurate, (b) the user is
  likely a developer if they have Claude Code installed, and (c)
  papering over it with a generic "Install failed" loses actionable
  detail. Revisit if non-developer users start hitting this.
- **Test coverage gap.** Same caveat as (ui 03 Risks): the row dispatch
  and state-driven bodies are not directly tested without a UI host. The
  view-model tests cover the data flow; the view wiring is verified by
  manual review.

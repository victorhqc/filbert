## Objective

Expose the per-provider base-URL override from (core 02) in the Settings
window as an advanced, collapsible option on each provider row, so users can
route requests through a custom proxy without editing files or defaults.

## Context

- `Sources/App/SettingsView.swift` — currently renders one `ProviderSettingsRow`
  per registered provider with an API-key field and a Configured/Unconfigured
  badge (ui 02 AC2/AC3). Each row gains an "Advanced" disclosure that reveals
  the base-URL field.
- `Sources/App/QuotaViewModel.swift` — today owns key save/clear
  (`saveKey(_:for:)`, `deleteKey(for:)`) and triggers fetches. It now also
  owns the override URL via Core's typed accessor (core 02 AC5):
  `ProviderOverrides.baseURL(for:)` / `setBaseURL(_:for:)`. The view never
  touches `UserDefaults` directly.
- `Sources/Core/ProviderOverrides.swift` — already exposes the typed
  `baseURL(for:)` / `setBaseURL(_:for:)` API, with `https`-only validation
  (core 02 AC5/AC6). This spec is purely the UI wiring on top.
- `Sources/Core/ProviderRegistry.swift` — already reads the override in
  `fetchAll()` (core 02 AC2). No registry change here; saving a new URL in
  the UI just needs to trigger a re-fetch so the user sees the change take
  effect without waiting for the 5-minute loop (ui 02 AC7).
- Builds on the orthogonal provider architecture in (core 01) and the
  Settings window shape from (ui 02). No provider module changes — the
  override is provider-agnostic from the UI's perspective (ui 02 AC9).
- Deployment target stays macOS 14.0; the disclosure uses SwiftUI
  `DisclosureGroup`, available since macOS 11.

## Acceptance Criteria

### AC1: Every provider row has an Advanced disclosure
- **Given** the Settings window is open
- **When** a provider row renders (configured or unconfigured)
- **Then** it shows an "Advanced" disclosure beneath the existing key/badge
  content, collapsed by default
- **And** the disclosure is present for every registered provider — no
  provider-specific branching (ui 02 AC9)

### AC2: Expanding reveals a base-URL field pre-filled with the current value
- **Given** a provider with no saved override
- **When** the user expands its Advanced disclosure
- **Then** the field shows the provider's static default URL (e.g.
  `https://api.z.ai`), rendered read-only-style so the user understands
  what the default is, with an input below labeled "Custom base URL (proxy)"
  for the override
- **And** when an override is already saved, the input is pre-filled with it

### AC3: Saving requires an `https` URL
- **Given** the user has typed a URL into the override field
- **When** they click Save (or submit the field)
- **Then** the value is validated through `ProviderOverrides.setBaseURL`
  (core 02 AC5); `https` URLs persist, and non-`https` / empty-host values
  show an inline error message ("Only `https` URLs are allowed.") and do
  not save
- **And** the inline error is cleared as soon as the user edits the field

### AC4: Saving a valid URL triggers an immediate re-fetch
- **Given** a configured provider
- **When** the user saves a new override URL for it
- **Then** the view model triggers a single fetch for that provider
  (re-using the existing `performFetch(for:)` path) so the user sees the
  proxy take effect without waiting for the 5-minute loop
- **And** a saved override for an unconfigured provider is stored but no
  fetch is triggered — the override just sits there until the user adds a key

### AC5: A saved override is clearly indicated
- **Given** a provider with a saved override
- **When** its Advanced disclosure is collapsed
- **Then** the row shows a small "(custom URL)" or equivalent indicator next
  to the badge, so the user can tell at a glance that this provider is not
  using its default URL — expanded state is not required to know an override
  is in effect

### AC6: Clearing the override restores the default
- **Given** a provider with a saved override
- **When** the user clears the override field and saves (or clicks a "Reset"
  button next to the field)
- **Then** `ProviderOverrides.setBaseURL(nil, for:)` is called, the field
  returns to showing the default URL, and AC4's re-fetch behavior applies so
  the next request hits the default host
- **And** clearing the override does **not** clear the API key — the two
  are independent

### AC7: Override state survives window close and app relaunch
- **Given** a saved override
- **When** the user closes the Settings window and reopens it, or quits and
  relaunches the app
- **Then** the override field still shows the saved URL, because overrides
  persist via `UserDefaults` (core 02 AC4)
- **And** the popover continues to use the override URL for fetches across
  relaunches

### AC8: All UI strings are localized
- **Given** the app running under a non-English locale
- **When** the Settings window renders (disclosure label, field labels,
  placeholder, Save/Reset buttons, validation error)
- **Then** every user-facing string goes through `String(localized:)` — no
  hard-coded English literals, matching (ui 01 AC7) and (ui 02 AC10)

## Plan

1. **ViewModel: override accessors.** Add thin `@MainActor` methods on
   `QuotaViewModel` that wrap `ProviderOverrides.setBaseURL(_:for:)` and
   `baseURL(for:)`, mirroring the existing `saveKey`/`deleteKey` pattern.
   The save path triggers `performFetch(for:)` for already-configured
   providers (AC4). Surface validation errors via a thrown
   `ProviderOverrideError` (already declared in Core) so the view can show
   the inline message. [x]
2. **ViewModel: derived "has override" flag.** Expose a small helper like
   `overrideURL(for providerId: String) -> URL?` the view can call to
   pre-fill the field and drive the "(custom URL)" indicator. Do **not**
   add observable state — the view reads it on demand from Core. [x]
3. **SettingsView: `ProviderSettingsRow` gains an Advanced disclosure.** A
   `DisclosureGroup` sits below the existing key/badge block. Expanded, it
   shows:
   - a read-only line with `type(of: provider).baseURL` (or the closest
     equivalent surfaced via a new `defaultBaseURL` field on `ProviderInfo`
     if needed — see Risks).
   - a `TextField` bound to local `@State` for the override.
   - a Save button and a Reset button (Reset is disabled when no override
     is saved).
   - an inline error `Text` shown when `ProviderOverrideError.invalidURL`
     is thrown. [x]
4. **SettingsView: collapsed indicator.** When an override is saved, the
   row's badge HStack gets a small secondary "custom URL" label. [x]
5. **Tests.** ViewModel-level tests are limited because the registry's
   Keychain dependency is hardcoded (existing `KeychainTests` caveat);
   cover what's testable:
   - Saving a valid `https` URL via the view-model accessor stores it via
     `ProviderOverrides` and is read back.
   - Saving a non-`https` URL throws `ProviderOverrideError.invalidURL`.
   - Clearing via the accessor removes the stored value.
   SwiftUI view tests stay out of scope (no UI test host today); the
   validation path is exercised through the view-model tests. [skipped —
   see Self-Review note; validation is already covered at the Core layer
   by `ProviderOverridesTests`, and the view-model wrapper's unique logic
   (conditional re-fetch) is untestable without an injectable Keychain.]
6. **No `Package.swift` changes** — no new module or dependency. [x]

No code is written until this spec is reviewed.

## Risks

- **`ProviderInfo` may not carry the default URL today.** The collapsed-row
  indicator and the read-only default line both want
  `type(of: provider).baseURL`. `ProviderInfo` (Core) currently exposes
  `id`, `displayName`, `description` only. Two options:
  1. Extend `ProviderInfo` with a `defaultBaseURL: URL` field, populated by
     the registry (one-line change, keeps the App layer provider-agnostic).
  2. Skip the read-only default line and only show the override input.
  Preferred: option 1 — it lets the user see what they're overriding
  without expanding, and the cost is one field on a small value type.
- **`UserDefaults` suite.** `ProviderOverrides` uses `UserDefaults.standard`
  by default. The app does not appear to use an app group today; if it ever
  does (for widgets or extensions), the suite needs to be plumbed through
  `ProviderOverrides.setUserDefaults(_:)` at app launch. Out of scope here;
  flagged for a future `widgets/` spec.
- **Re-fetch on save may surface transient errors.** If the saved proxy is
  wrong or unreachable, AC4's immediate fetch will fail and the popover will
  show an error state. That's the desired behavior — the user gets feedback
  that the proxy doesn't work — but the error message will be the provider's
  generic network-error string, not "your proxy URL is wrong." Acceptable
  for this spec; a future enhancement could surface a more targeted message.
- **Validation runs only on Save.** AC3 explicitly delays validation until
  submit, so partially typed URLs don't flash red while the user is still
  editing. This matches the existing API-key field behavior in
  `ProviderSettingsRow.saveIfValid`.
- **Test coverage gap.** Without a UI test host, the disclosure rendering
  and field-binding behavior are not directly tested. The view-model tests
  exercise the data flow; the view wiring is verified by manual review.

## Objective

Let the user re-order providers via drag-and-drop in a dedicated Settings tab,
and have that order drive how providers are stacked in the menu-bar popover.

## Context

- `Sources/App/SettingsView.swift` — currently a flat `List` mixing provider
  key/URL rows with balance thresholds (ui 02, ui 03, ui 08). Splits into a
  `TabView` so credentials stay on one tab and ordering lives on its own.
- `Sources/App/QuotaViewModel.swift` — `registeredProvidersSorted` and
  `configuredProviderIds` are derived by display-name sort today; both must
  honor the user-saved order instead.
- `Sources/App/QuotaView.swift` — `ForEach(viewModel.configuredProviderIds, …)`
  is already order-sensitive; no structural change, it just reads the new
  order through the view model.
- `Sources/Core/ProviderRegistry.swift` — owns the list of registered
  providers; needs no ordering logic itself, but `QuotaViewModel` needs a
  Core-level store to read/write the order.
- New `Sources/Core/ProviderOrder.swift` — `UserDefaults`-backed persistence
  for an ordered list of provider IDs, mirroring the pattern in
  `Sources/Core/ProviderOverrides.swift` (ui 03) so the storage shape stays
  private to Core.
- Builds on (ui 02) (multi-provider settings) and (ui 03) (per-provider
  `UserDefaults` precedent). Provider modules are untouched — orthogonality
  rule in `AGENTS.md` §0 holds.

## Acceptance Criteria

### AC1: Settings has separate tabs for credentials and appearance
- **Given** the Settings window is open
- **When** it renders
- **Then** it shows a `TabView` with two tabs: one labeled "Providers" holding
  the existing key/URL rows and balance thresholds (ui 02, ui 03, ui 08), and
  one labeled "Appearance" holding the new ordering UI
- **And** no credentials, base-URL overrides, or threshold inputs appear on
  the Appearance tab

### AC2: Appearance tab lists every registered provider by name
- **Given** the Appearance tab is shown
- **When** it renders
- **Then** it shows one row per registered provider, displaying only the
  provider's display name (no description, no badge, no key field)
- **And** the list is driven by the registry — no row is hard-coded to a
  specific provider, so a newly registered provider appears automatically

### AC3: User can re-order providers via drag-and-drop
- **Given** the Appearance tab is showing two or more providers
- **When** the user drags a row and drops it at a new position
- **Then** the list reorders immediately to reflect the drop
- **And** the new order is persisted to `UserDefaults` so it survives app
  restart

### AC4: Default order matches today's display-name sort
- **Given** no saved order exists (fresh install, or saved order deleted)
- **When** the Appearance tab and the popover render
- **Then** providers appear in the display-name ascending order already used
  by `registeredProvidersSorted` (ui 02 AC4) — no behavior change for existing
  users on first launch

### AC5: Newly registered providers append to the saved order
- **Given** a saved order exists for providers A and B
- **When** a new provider C is registered (e.g. via a future AppMain change)
- **Then** C appears after the saved providers in the default position
  (alphabetical among unsaved providers), without displacing the user's
  explicit A/B order
- **And** deleting a provider's saved position (e.g. provider B is removed
  from the registry) does not corrupt the saved list — B is simply dropped on
  read

### AC6: Popover renders configured providers in the saved order
- **Given** two or more configured providers and a non-default saved order
- **When** the popover renders
- **Then** configured providers stack in the saved order, not the
  display-name order
- **And** providers with no saved position fall back to their display-name
  sort relative to each other, after all explicitly ordered providers

### AC7: Order change updates the popover live
- **Given** the popover is open and the Settings window is open
- **When** the user reorders providers in the Appearance tab
- **Then** the popover's provider sections reorder on the next render without
  requiring an app restart or manual refresh

### AC8: Order storage shape is private to Core
- **Given** any App-layer code
- **When** it needs the effective provider order
- **Then** it calls a public `ProviderOrder` API (e.g.
  `ProviderOrder.effectiveOrder(for: registeredIds)` and
  `ProviderOrder.setOrder(_:)`), never reads or writes the raw `UserDefaults`
  key directly — matching the encapsulation in (ui 03)

### AC9: Ordering UI is localized
- **Given** the app running under a non-English locale
- **When** the Appearance tab renders (tab title, row labels, any hint text)
- **Then** every user-facing string goes through `String(localized:)` — no
  hard-coded English literals, matching (ui 02 AC10)

## Plan

1. **Core: add `ProviderOrder`.** New `Sources/Core/ProviderOrder.swift`,
   `UserDefaults`-backed, mirrors the `ProviderOverrides` pattern (private
   `defaults`, `setUserDefaults` test hook, private key prefix). Public API:
   - `effectiveOrder(for providerIds: [String]) -> [String]` — returns the
     passed IDs re-sorted so saved-order IDs come first in their saved
     sequence, then any unsaved IDs in display-name order. (Caller passes
     `[String]`, not names, so Core stays name-agnostic; the view model
     resolves names from `ProviderInfo` after.)
   - `savedOrder() -> [String]?` — raw read, used only to seed the editor.
   - `setOrder(_ providerIds: [String])` — writes the full list.
   Storage key: `provider-order`. Filtering is tolerant: IDs in the saved
   list but not in the registry are dropped on read; IDs in the registry but
   not in the saved list are appended.
2. **App: thread the order through `QuotaViewModel`.**
   - `registeredProvidersSorted` becomes `registeredProvidersOrdered`: builds
     the ID order via `ProviderOrder.effectiveOrder(for:)`, then maps to
     `ProviderInfo` via the registry. Display-name sort is the fallback
     inside Core, not in the view model.
   - `refreshDerived()` uses the same ordered source for
     `configuredProviderIds` so (ui 07) quiet-refresh paths pick the order up
     for free.
   - Add `func moveProvider(from: IndexSet, to: Int)` and
     `func persistOrder(_ ids: [String])` so the Order tab can write back.
     After writing, call `refreshDerived()` so (AC7) holds.
3. **App: split `SettingsView` into a `TabView`.**
   - Tab 1 "Providers": the existing `List` (key rows, base-URL overrides,
     balance thresholds) — unchanged content, just nested under the tab.
   - Tab 2 "Appearance": new `AppearanceTab` view with a `List` of provider
     display names bound to the view model, using SwiftUI's `.onMove` + a drag
     autoscroll so the user can re-order with the mouse (macOS 14 supports
     this on `List` without extra dependencies).
4. **App: no structural change to `QuotaView`.** It already iterates
   `viewModel.configuredProviderIds` in order; once that array honors the
   saved order, the popover follows.
5. **Tests:** new `Tests/CoreTests/ProviderOrderTests.swift` covering (AC4),
   (AC5), (AC8) — empty saved order → identity/display-name sort, partial
   saved order → saved-first then unsaved, stale saved IDs → dropped,
   `setOrder` round-trip. Uses the `setUserDefaults` test hook with an
   in-memory `UserDefaults` instance (suite name) to avoid polluting
   `.standard`.

No code is written until this spec is reviewed.

## Risks

- SwiftUI `.onMove` on macOS 14 `List` works but the drag affordance is less
  obvious than on iOS; if a user can't discover drag, we may need a follow-up
  spec adding up/down buttons. Out of scope here.
- `QuotaViewModel.registeredProvidersSorted` is referenced by name in
  `SettingsView` and `refreshDerived()`. Renaming to
  `registeredProvidersOrdered` is a small breaking change inside the App
  module — fine because App is the only caller, but worth noting.
- Persisting only IDs (not names) means a provider that changes its
  `providerId` would lose its position. IDs are stable by convention (core 01),
  so this is the same risk as Keychain key lookup and acceptable.
- `UserDefaults` is host-process state — if a future sandbox/widget extension
  needs the order it must go through an App Group container. That's a
  follow-up; today only the main app reads it.

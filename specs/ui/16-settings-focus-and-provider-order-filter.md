## Objective

Fix two Settings-window papercuts: re-clicking "Settings…" must raise the
already-open window instead of leaving it behind the frontmost app, and the
Appearance tab's "Provider order" list must show only providers that are
actually configured and tracking.

## Context

- `Sources/App/QuotaView.swift` — the popover's "Settings…" entry uses
  SwiftUI's built-in `SettingsLink`, which opens the `Settings` scene on first
  click but does not reliably raise an already-open window when Filbert is in
  `.accessory` activation policy. Same site has an "Open Settings" button in
  `emptyState`. Both need to bring the window forward.
- `Sources/App/SettingsView.swift` — declares the `Settings` scene body and
  already calls `NSApp.activate(ignoringOtherApps: true)` in `.onAppear`, but
  `.onAppear` only fires once per view lifetime, so it does not help on a
  second "Settings…" click that targets an already-existing window.
- `Sources/App/AppMain.swift` — declares `Settings { SettingsView(...) }` (ui
  02 AC1); no change to the scene itself is expected, only to how it is opened.
- `Sources/App/AppearanceSettingsView.swift` — `providerOrderRows` iterates
  `viewModel.registeredProvidersOrdered` (all registered providers). It must
  instead iterate only the configured subset, matching the popover's
  `configuredProviderIds` filter.
- `Sources/App/QuotaViewModel.swift` — owns both
  `registeredProvidersOrdered: [ProviderInfo]` (ui 09 AC2) and the configured
  filter logic in `refreshDerived()` (states `.loading`/`.loaded`/`.error` =
  configured; `.unconfigured`/`.setup` = not). The fix needs a configured
  variant of the ordered list, not a parallel ordering scheme.
- Builds on (ui 02) (the Settings scene and the configured/unconfigured split)
  and (ui 09) (the saved provider order). This spec narrows (ui 09 AC2) from
  "lists every registered provider" to "lists every configured provider" —
  see Plan and Risks.

## Acceptance Criteria

### AC1: "Settings…" opens the window when closed
- **Given** the Settings window is not currently open
- **When** the user clicks "Settings…" in the menu-bar popover (or "Open
  Settings" in the empty state)
- **Then** the Settings window opens and becomes the active, key window

### AC2: "Settings…" raises the window when already open in the background
- **Given** the Settings window is already open but another app is frontmost
  (Filbert's window is hidden behind it)
- **When** the user opens the popover and clicks "Settings…"
- **Then** the existing Settings window is brought to the front, ordered above
  all other Filbert windows, and Filbert is activated so the window receives
  keyboard focus
- **And** no second Settings window is created

### AC3: Same raise behavior from the empty state
- **Given** the empty-state popover is shown (no configured providers) and the
  Settings window is already open in the background
- **When** the user clicks "Open Settings"
- **Then** the existing Settings window is raised and activated exactly as in
  AC2 — the empty-state button has the same behavior as the popover's
  "Settings…" button

### AC4: "Provider order" shows only configured providers
- **Given** the user has at least one configured provider and at least one
  unconfigured provider registered
- **When** the Settings window is open and the Appearance tab is selected
- **Then** the "Provider order" card renders exactly one row per configured
  provider and zero rows for unconfigured providers
- **And** the set of rows matches the providers shown in the popover
  (`viewModel.configuredProviderIds`), not the full registry

### AC5: Filter reacts live to credential changes
- **Given** the Settings window is open on the Appearance tab
- **When** the user switches to the Providers tab, saves a key for a previously
  unconfigured provider (or clears the key of a configured one)
- **Then** on returning to the Appearance tab, the "Provider order" list
  reflects the new configured set without an app restart — newly configured
  providers appear, freshly unconfigured providers disappear

### AC6: Drag-and-drop still reorders only the visible rows
- **Given** two or more configured providers are listed in "Provider order"
- **When** the user drags one row onto another
- **Then** the visible list reorders immediately and the new order is persisted
- **And** the popover's provider stacking follows the new order on the next
  render (ui 09 AC7 still holds for the configured subset)
- **And** reordering does not corrupt the saved positions of providers that are
  currently hidden because they are unconfigured

### AC7: Empty "Provider order" is communicated, not silently blank
- **Given** no providers are configured (popover is in its empty state)
- **When** the user opens the Settings Appearance tab
- **Then** the "Provider order" card shows a short hint pointing the user to
  configure a provider on the Providers tab, rather than rendering an empty
  list with no explanation

## Plan

1. **App: add a reusable "open and raise Settings" action.** Replace the bare
   `SettingsLink { … }` usages in `QuotaView.swift` with a small `Button`
   whose action captures `@Environment(\.openSettings)` and, after calling
   it, runs `NSApp.activate(ignoringOtherApps: true)` plus an
   `NSApplication`-level lookup that finds the Settings `NSWindow` and calls
   `makeKeyAndOrderFront(nil)` on it. The window lookup must not assume a
   specific title — match by the Settings scene's window class or by a
   stable identifier, not by localized text. The button label and styling
   stay identical to the current `SettingsLink` so the UI is unchanged.
2. **App: stop relying on `.onAppear` for activation.** The `SettingsView`
   `.onAppear` `NSApp.activate` call stays (it covers the first-open case
   where the window did not previously exist), but it is not the mechanism
   that satisfies AC2/AC3 — the button action from step 1 does that, because
   it runs on every click.
3. **App: expose a configured-only ordered list on the view model.** Add
   `configuredProvidersOrdered: [ProviderInfo]` to `QuotaViewModel` — same
   ordering source as `registeredProvidersOrdered`, filtered by the same
   `ProviderState` rule already used in `refreshDerived()` (drop
   `.unconfigured` and `.setup`). This avoids duplicating the "what counts
   as configured" predicate in the view layer.
4. **App: point `AppearanceSettingsView` at the configured list.**
   `providerOrderRows` iterates `viewModel.configuredProvidersOrdered`
   instead of `registeredProvidersOrdered`. The drag/drop delegate still
   receives the *full* ordered list (so absolute positions in the saved
   order are preserved); only the rendered `ForEach` is filtered. This
   preserves AC6's "do not corrupt hidden positions" requirement.
5. **App: empty hint when the configured list is empty.** When
   `configuredProvidersOrdered.isEmpty`, the "Provider order" card body
   renders a single localized hint line (e.g. "Configure a provider on the
   Providers tab to start reordering.") instead of an empty `VStack`.
6. **Tests:** `Tests/AppTests` is currently AppKit/SwiftUI-light (no UI
   render tests). The view-model change in step 3 is unit-testable: assert
   `configuredProvidersOrdered` matches `configuredProviderIds` (mapped to
   `ProviderInfo`) across a mixed configured/unconfigured registry. The
   window-raise behavior in steps 1–2 is not unit-testable without a host
   app, so it is verified manually per the ACs.

No code is written until this spec is reviewed.

## Risks

- **Narrowing (ui 09 AC2).** This spec changes the Appearance tab from "every
  registered provider" to "only configured providers", which is a behavior
  change to a previously specced feature. It is intentional and matches how
  the popover already works, but a reviewer should sanity-check that no
  existing user workflow depends on reordering providers that are not yet
  configured. The underlying `ProviderOrder` storage still holds all saved
  IDs, so re-enabling a hidden provider later restores its prior position.
- **Settings window lookup.** Finding the right `NSWindow` to raise is the
  fragile part of AC2/AC3. Matching by localized window title breaks under
  non-English locales; the implementation must use a locale-independent
  identifier (window class or scene identifier). If SwiftUI exposes no
  stable handle on macOS 14, fall back to iterating
  `NSApp.windows` and picking the one hosting the `SettingsView` — never
  hard-code a title.
- **`.accessory` activation quirks.** Filbert runs as an accessory app
  (`setActivationPolicy(.accessory)`), where `NSApp.activate` historically
  behaves inconsistently across macOS versions. If `activate` alone does not
  raise the window on a targeted macOS version, `NSApplication.shared`
  `Yosemite`-era `.activate()` overrides or `NSWindow`'s
  `orderFrontRegardless()` may be needed. Document whichever path is taken.
- **Drag/drop index mapping.** Filtering the rendered list while the drop
  delegate sees the full ordered list means source/destination indices must
  be resolved against the full list, not the visible subset. The existing
  `ProviderOrderDropDelegate` already keys off provider IDs, so this should
  hold, but a regression here would silently reorder hidden providers —
  worth a manual check after implementation.

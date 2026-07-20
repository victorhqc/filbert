## Objective

Add a standalone Settings window where the user picks which providers are
enabled, and gate the menu-bar popover and widget to show only providers whose
credentials have been configured.

## Context

- `Sources/App/AppMain.swift` — currently hard-codes `ZAIProvider` in the
  registry and renders a single-provider popover; becomes the place where a
  real `Settings` scene is declared and the popover is switched to iterate
  over configured providers.
- `Sources/App/QuotaViewModel.swift` — single-provider today (`providerId`
  field, one `quota` value); generalizes into a per-provider state map.
- `Sources/App/SettingsView.swift` — currently a single z.ai key field embedded
  in the popover; moves out of the popover into the Settings window and becomes
  the provider-picker list.
- `Sources/App/QuotaView.swift` — renders one `ProviderQuota`; becomes a
  per-provider section, repeated for each configured provider in the popover.
- `Sources/Core/ProviderRegistry.swift` — `fetchAll()` already iterates
  registered providers; needs an API to list *all known* providers and their
  configured state so the UI can render the picker (core 01 AC4).
- `Sources/Core/Keychain.swift` — unchanged API; reused per provider ID.
- Builds on the orthogonal provider architecture in (core 01) and the existing
  single-provider settings surface in (ui 01). The provider modules themselves
  (providers 01) stay untouched — this is a Core + App change.
- Deployment target stays macOS 14.0; the Settings window uses SwiftUI's
  `Settings` scene + `Form`/`List`, both Sonoma-baseline.

## Acceptance Criteria

### AC1: A real Settings window reachable from the menu bar
- **Given** the app is running
- **When** the user opens the menu-bar popover and clicks "Settings…"
- **Then** a standalone macOS window opens (standard `Settings` scene), separate
  from the popover, that lists every provider the app knows about

### AC2: Provider list shows all known providers with configured state
- **Given** the Settings window is open
- **When** it renders
- **Then** it shows one row per registered provider (z.ai today; future
  providers added by registering them in `AppMain` appear automatically — no UI
  edits per provider), each row displaying the provider's display name, a
  short description, and a configured/unconfigured badge
- **And** no row is hard-coded to a specific provider — the list is driven by
  the registry

### AC3: Unconfigured provider is enabled but pending credentials
- **Given** a provider with no Keychain key (e.g. a freshly registered new
  provider)
- **When** its row renders in Settings and the menu-bar popover renders
- **Then** the Settings row shows a key entry field (and Save/Clear), and the
  provider is **omitted** from the popover's live-quota list (not shown as
  disabled, not shown with an error — just absent until configured)

### AC4: Configured provider appears in popover and widget
- **Given** a provider with a saved Keychain key
- **When** the popover renders
- **Then** that provider's quota appears as one section in the popover
  (headline + usage lines, same layout as (ui 01 AC4)) and is included in the
  widget's data
- **And** multiple configured providers each render as their own section,
  ordered by provider display name

### AC5: Removing credentials removes the provider from the popover
- **Given** a configured provider
- **When** the user clears its key in Settings
- **Then** the Keychain entry is deleted (core 01 AC3), the popover drops that
  provider's section on the next render, and no further fetches are scheduled
  for it

### AC6: Per-provider refresh, independent failure isolation
- **Given** two or more configured providers
- **When** one provider's fetch fails (auth, network, decode)
- **Then** its popover section shows the error with Retry (ui 01 AC6), while
  the other configured providers continue to render their last-known-good data
  — one provider's failure never blanks the whole popover

### AC7: Auto-refresh runs per configured provider at the existing cadence
- **Given** one or more configured providers
- **When** the popover is open and time passes
- **Then** each configured provider refreshes on the 5-minute interval from
  (ui 01 AC5), and providers that become unconfigured stop refreshing
  immediately without cancelling in-flight fetches for other providers

### AC8: Menu-bar icon stays neutral
- **Given** any mix of configured/unconfigured providers
- **When** the menu-bar icon renders
- **Then** it stays the system SF Symbol from (core 01 AC6); it does **not**
  turn into a per-provider icon and does **not** show an error state when a
  provider is unconfigured (unconfigured is not an error)

### AC9: Adding a future provider requires no App-layer edits beyond registration
- **Given** a new provider module conforming to `AIProvider` (core 01 AC2)
- **When** it is registered in `AppMain.init()` (one line) and linked in
  `Package.swift`
- **Then** it appears in the Settings list and behaves correctly with no
  further edits to `SettingsView`, `QuotaView`, `QuotaViewModel`, or the
  widget — preserving the orthogonality rule in section 0 of `AGENTS.md`

### AC10: Settings window chrome is localized
- **Given** the app running under a non-English locale
- **When** the Settings window renders (window title, provider descriptions,
  Save/Clear buttons, configured/unconfigured badges)
- **Then** every user-facing string goes through `String(localized:)` — no
  hard-coded English literals, matching (ui 01 AC7)

## Plan

1. **Core: registry surfaces known providers.** Extend `ProviderRegistry`
   with a `registeredProviders: [ProviderInfo]` accessor (where `ProviderInfo`
   is a small value type carrying `id`, `displayName`, `description`) and a
   `isConfigured(_ id:)` helper that asks the Keychain. Keep `fetchAll()`
   semantics — it already iterates and isolates per-provider failures.
2. **Core: `ProviderState` value.** Introduce a `Sendable` enum or struct that
   the view model can hold per provider: `.unconfigured`, `.loading`,
   `.loaded(ProviderQuota)`, `.failed(String)`. This replaces the single
   scalar state on `QuotaViewModel`.
3. **App: `QuotaViewModel` becomes multi-provider.** It owns
   `[String: ProviderState]`, a per-provider refresh `Task`, and re-derives
   the active set from the registry's configured state on launch and on every
   key save/clear. Each provider keeps its own 5-minute loop so cancelling one
   does not cancel the others.
4. **App: split `SettingsView` out of the popover.** It becomes the body of a
   real `Settings` scene in `AppMain`. The popover gains a "Settings…" button
   that calls `NSApp.sendAction(Selector(("showSettingsWindow:")), …)` or the
   Sonoma-equivalent `Settings` scene open. The popover no longer hosts the
   key field.
5. **App: `QuotaView` becomes a per-provider section.** A small
   `ProviderSection` view wraps the existing `QuotaView` layout for one
   provider; the popover `ForEach`es over configured providers and renders one
   `ProviderSection` each, separated by `Divider()`. The empty state (no
   providers configured) shows a "Open Settings to add a provider" prompt.
6. **Widget/menu-bar data source:** whatever feeds the widget today is updated
   to read from the per-provider state map instead of the single `quota`
   property — same data, different shape.
7. **`Package.swift`:** no target changes needed for this spec (provider
   modules are unchanged); only App + Core sources move.

No code is written until this spec is reviewed.

## Risks

- The current `QuotaViewModel` is single-provider throughout (`providerId`,
  single `quota`, single `refreshLoop`). Migrating to a per-provider map is the
  bulk of the work and a regression risk for the existing z.ai flow — the
  z.ai-only path must behave exactly as in (ui 01) after the change.
- SwiftUI `Settings` scene behavior differs between macOS versions; on Sonoma
  the `SettingsLink` / `EnvironmentValues.openSettings` is the supported way
  to open it from a `MenuBarExtra` popover — older `sendAction` selectors are
  deprecated and may warn.
- The popover has a fixed `frame(width: 280)`. With multiple providers stacked,
  the popover wraps its body in a `ScrollView` with a `frame(maxHeight: 400)` so
  the window stays bounded while every configured provider stays one swipe
  away. No count cap, no hidden state, no "and N more…" link. The single-
  provider case (common today) renders identically to (ui 01) — scroll only
  activates when content exceeds the cap.
- The widget is mentioned in AC4/AC7 but the widget itself is not yet specced
  (no `widgets/NN-*.md`); this spec assumes the widget reads the same
  `[String: ProviderState]` source as the popover. If the widget has its own
  data pipeline, that's a follow-up spec.
- Storing/clearing keys hits the real Keychain (ui 01 Risks) — same caveat
  applies, now multiplied across providers.

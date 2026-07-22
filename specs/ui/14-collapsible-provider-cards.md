## Objective

Redesign each popover provider section into a card with a standardized logo
badge and a larger title, make it collapsible, and show a compact
ring+percentage / remaining-amount status beside the title when collapsed —
mirroring the menu-bar icon (ui 10) — so a crowded multi-provider popover stays
scannable.

## Context

- `Sources/App/QuotaView.swift` — owns the popover. `providerSection(providerId:
  state:)` (lines 71–85) dispatches by `ProviderState`; `quotaContent(_:
  providerId:)` (lines 113–179) renders the caption row (name + last-updated +
  error triangle + refresh, grouped top-right per ui 11 AC4), the headline row
  (with the balance tier `Circle`, ui 08 AC3), the usage lines, peak-hours block
  (ui 04), and the stale hint (ui 05). This is where the header restructures and
  the collapse gate go.
- `Sources/App/QuotaStatusResolver.swift` — pure `resolve(for:) -> Status`
  (`.window(percentage:)` / `.balance(...)` / `.fallback`) and `tier(for:)`,
  already shared by the popover and the menu-bar icon (ui 10). The collapsed
  compact status reuses these verbatim so a collapsed card and the menu bar can
  never disagree.
- `Sources/App/MenuBarStatusIcon.swift` — the reference for "circle + percentage
  / remaining amount". Its ring is a bitmap `NSImage` because `MenuBarExtra`'s
  label layer drops SwiftUI `Shape`s (ui 10). The popover is a window-style
  panel where `Shape`s **do** render (the existing `UsageBar` and `PeakHoursBlock`
  prove it), so the collapsed card draws a native SwiftUI ring — tier-colored,
  not the monochrome menu-bar template.
- `Sources/App/QuotaViewModel.swift` — publishes `configuredProviderIds`
  (ui 09 ordering), `providerStates`, `refreshErrors`, `isRefreshing`. It gains
  a glyph lookup and collapse toggles; no data-flow change.
- `Sources/Core/ProviderProtocol.swift` — `AIProvider` and `ProviderInfo` carry
  no glyph today. A new `ProviderGlyph` descriptor is added to `AIProvider`
  (static) and surfaced through `ProviderInfo`, so each provider ships its own
  logo. This keeps the architecture orthogonal (AGENTS.md §4): a new provider
  supplies its glyph without touching the app layer or any other provider.
- `Sources/Core/ProviderOrder.swift` — the UserDefaults store pattern
  (parameterless `defaults`, `setUserDefaults(_:)` test hook, private key) the
  new collapse-state store mirrors. Collapse state is presentation state, not a
  secret, so it stays out of the Keychain (AGENTS.md §3).
- Providers ship Resources bundles already (`Package.swift`) except
  `OpenAICodexProvider`, which has none yet — adding a glyph asset there also
  adds its `resources:` line.
- Builds on (ui 10) for the compact status, (ui 04) / (ui 08) for the tier
  palette and balance dot, (ui 09) for ordering, (ui 11) for the top-right
  refresh cluster, (ui 02) for per-provider sections, and (core 01) for provider
  orthogonality. Follows (ui 12)'s precedent of monochrome, license-safe glyphs
  drawn/shipped rather than pasted official brand rasters.

## Acceptance Criteria

### AC1: Each provider header shows a standardized logo badge + larger title
- **Given** a configured provider's section
- **When** it renders
- **Then** the header row leads with a fixed-size logo badge (a rounded-rect
  container of one shared size and corner radius for every provider) followed by
  the provider display name at a larger, more prominent weight/size than today's
  `.caption` semibold (e.g. `.headline`)
- **And** every provider's badge uses identical dimensions, inset, and treatment
  so the four logos read as one visual family regardless of source artwork
- **And** the name still truncates (`.lineLimit(1)`, tail) before the trailing
  header cluster on long names, preserving (ui 11)

### AC2: Logos are pre-generated build-time assets, loaded not computed
- **Given** the standardization pass that normalizes each source logo to the
  shared style
- **When** the app runs
- **Then** that pass has already run **once at authoring/build time**, producing
  a committed image asset per provider; the app never runs the standardization
  transform at launch or on any render — startup only *loads* the finished asset
- **And** no per-startup or per-render `CGContext` drawing produces a provider
  logo (unlike the ring / vintage face, which are drawn live per bucket/tier);
  the badge is a static bundled resource
- **And** regenerating the assets is a repeatable, committed step (a script), so
  the same input logos always yield the same normalized output

### AC3: Logos are supplied orthogonally by each provider
- **Given** the `AIProvider` protocol
- **When** a provider is registered
- **Then** it exposes a `ProviderGlyph` (a Core value type naming a bundled
  template asset + its `Bundle`, or an SF Symbol name as a placeholder fallback),
  surfaced on `ProviderInfo`, and the popover renders any provider's glyph
  through one shared badge view
- **And** adding, removing, or changing one provider's glyph requires no change
  to any other provider or to the app-layer render code (core 01, AGENTS.md §4)
- **And** a provider whose glyph asset is missing or fails to load falls back to
  a neutral placeholder glyph so the badge never renders empty

### AC4: Each configured provider section is collapsible
- **Given** a configured provider section (`.loaded`, `.setup`, `.loading`, or
  `.error`)
- **When** the user activates the header's disclosure control (chevron) or taps
  the header outside the refresh button
- **Then** the section toggles between expanded and collapsed with an animated
  chevron (`chevron.down` expanded, `chevron.right` collapsed)
- **And** tapping the refresh button toggles a refresh, never the collapse state
- **And** the disclosure control is keyboard-focusable and exposes an
  accessibility action announcing "Expand" / "Collapse"

### AC5: A collapsed section shows a compact status beside the title
- **Given** a `.loaded` provider whose `QuotaStatusResolver.resolve(for:)` is not
  `.fallback`, in the collapsed state
- **When** the header renders
- **Then** for a `.window(percentage:)` status it shows a small tier-colored
  progress ring plus `NN%` at the trailing edge — laid out `<badge> <name> …
  <ring> <NN%>` — and for a `.balance(...)` status it shows the balance tier
  `Circle` dot plus the formatted amount — `<badge> <name> … <dot> <amount>`
- **And** the percentage, the currency string, the ring fraction, and the tier
  are all derived from `QuotaStatusResolver` / the shared tier palette, so a
  collapsed card, an expanded card, and the menu-bar icon can never disagree
  (ui 10 AC3/AC4, ui 04 AC2, ui 08 AC3)
- **And** the ring fraction is clamped to `[0, 1]` via
  `QuotaStatusResolver.clampedFraction(_:)` before drawing (ui 10 AC6)
- **And** a `.loaded` provider that resolves to `.fallback` (no usable
  percentage or positive balance) shows no compact status — just the badge and
  name — so a collapsed card never shows misleading data (ui 10 AC5)

### AC6: An expanded section renders exactly today's full content
- **Given** an expanded `.loaded` section
- **When** it renders
- **Then** below the header it shows the current full body unchanged — headline
  with its balance dot (ui 08), usage-line rows with bars (ui 04), peak-hours
  block (ui 04), stale-cache hint (ui 05), and the bottom "Last updated" label /
  error triangle — with no compact ring/amount duplicated in the header
- **And** the top-right refresh cluster (refresh button, error triangle) from
  (ui 11 AC4) stays in the header and works in both collapsed and expanded states

### AC7: Collapse state persists per provider; first-run defaults are positional
- **Given** the user collapses or expands any provider — including the top-most
  one
- **When** the popover is reopened or the app restarts
- **Then** that provider's chosen state is restored from a UserDefaults-backed
  Core store mirroring `ProviderOrder` (private key, parameterless `defaults`,
  `setUserDefaults(_:)` test hook), keyed by provider ID, never written to the
  Keychain (AGENTS.md §3) — the saved preference wins for every provider, the
  first included
- **And** a provider with **no saved state** falls back to a positional default:
  **expanded when it is the current top-most provider** (first in
  `configuredProviderIds`, ui 09), **collapsed otherwise** — so a first run shows
  only the most-important provider open and the rest collapsed, keeping the
  popover compact
- **And** once the user toggles a provider it has a saved entry that overrides
  the positional default forever after (the default only governs never-touched
  providers), so after the first run the visible state is entirely the user's
  preference
- **And** the positional default is applied by the App layer (which knows the
  order), not by the Core store — the store returns `nil` for an unsaved
  provider, mirroring `ProviderOrder.savedOrder()` vs `effectiveOrder(for:)`
- **And** a saved ID no longer registered is ignored on read

### AC8: Non-loaded states keep a header with badge + name
- **Given** a provider in `.setup`, `.loading`, or `.error`
- **When** the section renders
- **Then** the header still shows the badge, name, and disclosure control; the
  collapsed state hides the state body (spinner / setup text / error) and the
  expanded state shows it exactly as today
- **And** an `.error` or `.setup` collapsed header shows no percentage/amount
  (there is no `.loaded` quota to resolve) — the refresh/error triangle in the
  header cluster remains the only status signal

### AC9: Compact status uses the popover tier palette, not the menu-bar monochrome
- **Given** a collapsed `.window` or `.balance` card
- **When** the compact ring / dot renders
- **Then** it uses `tierColor(_:scheme:)` (green/orange/red, WCAG-tuned per
  ui 11 AC1) so it matches the expanded card's colored number and balance dot —
  the monochrome-template rule is specific to the menu bar (ui 10 AC8) and does
  not apply inside the popover

### AC10: Accessibility
- **Given** VoiceOver focusing a provider header
- **When** it announces the header
- **Then** it announces the provider name, the expanded/collapsed state, and —
  when collapsed with a compact status — a localized summary such as
  "42% used" or "$12.34 remaining" reusing the menu-bar icon's sentences
  (ui 10 AC9), and the badge is decorative/labeled by the name (no redundant
  announcement)

### AC11: Localization
- **Given** the app under a non-English locale
- **When** the header, disclosure actions, and accessibility summaries render
- **Then** every user-facing string goes through `String(localized:)` and lands
  in `Sources/App/Resources/Localizable.xcstrings`, matching (ui 02 AC10),
  (ui 10 AC10)

## Plan

1. **Core: `ProviderGlyph` + protocol surface.** Add to
   `Sources/Core/ProviderProtocol.swift`:
   ```swift
   public enum ProviderGlyph: Sendable {
       case sfSymbol(String)
       case asset(name: String, bundle: Bundle)
   }
   ```
   Add `static var providerGlyph: ProviderGlyph { get }` to `AIProvider` with a
   default (`.sfSymbol("cpu")`) so existing providers compile, and add a `glyph`
   field to `ProviderInfo`, populated in `ProviderRegistry.registeredProviders`.
   Core stays Foundation-only — `Bundle` is Foundation; no SwiftUI leaks in.
2. **Assets: generate the standardized glyphs once, at build/authoring time.**
   A committed generator (e.g. `scripts/generate-provider-glyphs.*`) takes each
   provider's source logo and runs the shared standardization pass — normalize to
   one canvas size, monochrome/template treatment, consistent inset — emitting a
   finished template asset (PDF or `@1x/@2x` PNG) into that provider's
   `Resources`. This runs **once when regenerating art**, never at app launch or
   on render (AC2). Each provider then returns `.asset(name:bundle:)` pointing at
   its committed file; `OpenAICodexProvider` gains a
   `resources: [.process("Resources")]` line in `Package.swift`. The generator is
   deterministic so re-running it on the same inputs reproduces the same assets.
   Recommend simplified single-color glyphs in a common style, not official brand
   rasters — see Risks. Until final art exists, a provider may return
   `.sfSymbol(...)` as a placeholder so the feature ships incrementally.
3. **App: `ProviderLogoBadge` view.** One shared SwiftUI view rendering any
   `ProviderGlyph` — `Image(systemName:)` or `Image(nsImage:)` from the named
   bundle asset — inside a fixed rounded-rect (e.g. 20×20, `.secondary.opacity`
   background), tinted `.primary` for a unified monochrome family. On asset load
   failure it draws the placeholder symbol (AC3).
4. **App: `CompactProviderStatus` view.** Given a `QuotaStatusResolver.Status`,
   renders the collapsed trailing cluster: a native SwiftUI ring
   (`Circle().trim(from:0,to: clampedFraction).stroke(tierColor…)` over a
   `.secondary.opacity(0.2)` track) + `NN%` for `.window`, or the tier `Circle`
   dot + `formattedAmount` for `.balance`. `Shape`s are safe here (this is the
   window popover, not the menu-bar label). Colors come from the popover's
   `tierColor(_:scheme:)` (AC9).
5. **App: restructure `quotaContent` into a card.** Split into a persistent
   `providerHeader` (badge, name at `.headline`, disclosure chevron, the ui 11
   top-right cluster, and — when collapsed & `.loaded` — `CompactProviderStatus`)
   and the existing body, shown only when expanded. Wrap the header tap in a
   `Button`/`onTapGesture` that toggles collapse, keeping the refresh `Button`
   as a separate hit target. Apply the same header to the `.setup` / `.loading`
   / `.error` branches (AC8) so every section is a card.
6. **Core: `ProviderCollapseState` store.** New
   `Sources/Core/ProviderCollapseState.swift` mirroring `ProviderOrder`: it
   stores only providers the user has explicitly toggled and returns the saved
   value or `nil` when untouched — `collapsedState(for:) -> Bool?`,
   `setCollapsed(_:for:)`, parameterless `defaults`, `setUserDefaults(_:)`,
   private key. The store bakes in **no** default (no expanded/collapsed
   assumption) — the positional default is the App's job (AC7), just as
   `ProviderOrder` leaves resolution to `effectiveOrder(for:)`.
7. **App: view-model wiring.** `QuotaViewModel` gains `glyph(for:) ->
   ProviderGlyph` (from `ProviderInfo`) and a resolved
   `isCollapsed(_ id:) -> Bool` that returns
   `ProviderCollapseState.collapsedState(for: id) ?? (id != configuredProviderIds.first)`
   — saved preference wins; otherwise the top-most provider is expanded and the
   rest collapsed (AC7). `toggleCollapsed(_:)` writes the explicit value via
   `setCollapsed(_:for:)`, published so the popover re-renders. No change to
   `configuredProviderIds`, `providerStates`, or refresh flow.
8. **Tests.**
   - `Tests/CoreTests/ProviderCollapseStateTests.swift` — untouched ID returns
     `nil`, set collapsed/expanded round-trips, `setUserDefaults` swap, mirroring
     `ProviderOrderTests`.
   - `Tests/AppTests` view-model default resolution — with an empty store the
     top-most `configuredProviderIds` entry resolves expanded and every other
     resolves collapsed; a saved entry overrides the positional default for any
     position including the first.
   - `Tests/CoreTests` — `ProviderInfo.glyph` populated from registry; default
     glyph applied when a provider does not override.
   - Reuse `Tests/AppTests` resolver coverage — the compact status is a pure
     function of `QuotaStatusResolver.resolve`/`tier`/`clampedFraction`, already
     tested (ui 10); add cases asserting `.fallback` → no compact status (AC5).

No code is written until this spec is reviewed.

## Risks

- **Trademark / licensing of official logos.** Decided: ship **simplified,
  single-color glyphs that stay as close to each official mark as possible**
  without reproducing the protected raster — consistent with (ui 12)'s
  license-safe precedent. "As close as possible" is a judgment call per logo; the
  standardization pass (Plan §2) enforces one shared silhouette treatment, so a
  glyph that drifts too far from — or too literally copies — a brand mark is a
  per-asset review item, not a code concern. Some marks (e.g. wordmark-only
  brands) reduce to an initial or abstract shape; flagged so a reviewer expects
  that, not a pixel-accurate logo.
- **Header tap vs. refresh button.** The collapse toggle wraps the header while
  the refresh `Button` sits inside it. On macOS a nested `Button` inside a
  tappable container can double-fire. Plan §5 keeps refresh a distinct
  `Button`/hit target and puts the collapse toggle on the chevron + the header
  background outside it; verify no double-trigger at implementation.
- **Ring at small size in the popover.** The compact ring is ~14–16pt. Unlike
  the menu bar it can be tier-colored and antialiased as a real `Shape`, but a
  too-thin stroke reads poorly. Reuse the menu-bar ring's ~85%-drawable / open-
  gap proportions as a starting point and eyeball at the popover's `280` width.
- **Positional first-run default hides data on launch.** On a fresh run only the
  top-most provider is expanded; the other three collapse to compact rows, so
  their full breakdowns are one click away rather than visible immediately. This
  is the intended declutter (AC7) and reverses today's all-expanded popover — a
  reviewer should confirm the compact row still surfaces enough (name + ring/%,
  or name + amount) that a collapsed provider isn't easy to overlook.
- **Untouched providers keep following the positional default.** A provider the
  user never toggles has no saved entry, so its state is recomputed from its
  current position each open. If the user reorders providers (ui 09) and a
  never-touched provider becomes top-most, it flips to expanded; the old top, if
  also never touched, flips to collapsed. This matches "no expressed preference →
  positional default" but means an untouched provider's state can change on
  reorder. Toggling it once pins it. Acceptable and documented, not a bug.
- **`ProviderGlyph.asset` bundle resolution.** Each provider passes
  `Bundle.module`; the app loads the named asset from that bundle. A mis-typed
  name or a missing `resources:` line yields no image — AC3's placeholder
  fallback prevents an empty badge, but the misconfigured provider ships with
  the generic glyph until fixed. Covered by the registry test in Plan §8.
- **Orthogonality preserved.** The glyph travels with the provider and the
  render path is provider-agnostic, so adding a provider still touches only its
  own module plus its `Package.swift` target (core 01, AGENTS.md §4). No
  app-layer `switch providerId` is introduced.

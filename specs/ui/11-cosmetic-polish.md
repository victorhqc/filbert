## Objective

Polish four cosmetic issues across the popover and Settings: poor red/orange/green
contrast in light mode, balance-threshold controls stranded on the Providers tab,
excessive spacing in the Appearance tab's provider-order list, and the per-provider
refresh button living at the bottom-right instead of the top-right.

## Context

- `Sources/App/QuotaView.swift` — owns the popover rendering and the
  `percentageColor(_:)` / `balanceTierColor(_:)` resolvers that emit `.green`,
  `.orange`, `.red` directly. Today these are SwiftUI semantic `Color` constants
  which resolve to system colors; their perceived contrast against the popover's
  background and against secondary text is poor in light mode. The refresh
  button is also rendered here, inside the bottom `HStack` of
  `quotaContent(_:)`, after the divider — issue 4 moves it to the top-right.
- `Sources/App/SettingsView.swift` — owns the tabbed Settings window.
  `providersTab` currently embeds the "Balance thresholds" `Section` (issue 2
  relocates it to `AppearanceTab`). `AppearanceTab`'s `Section` is a bare
  `ForEach` of `Text(provider.displayName)` rows with no row content tuning, so
  SwiftUI's default `List` row insets leave a large gap (issue 3).
- `Sources/Core/BalanceThresholds.swift` — unchanged; the relocated row reads
  the same store. Cited by (ui 08 AC2).
- Cross-references: relocates the controls added by (ui 08 AC4); the moved
  controls keep the same stepper/preview shape. Provider-order list is the one
  introduced by (ui 09). Tier colors are shared with (ui 04 AC2) and
  (ui 08 AC3), so any palette change applies to both paths.

## Acceptance Criteria

### AC1: Tier colors meet WCAG AA contrast against popover backgrounds
- **Given** the popover or Settings tier swatches rendering `.green`, `.orange`,
  or `.red` foreground
- **When** the foreground-to-background contrast ratio is computed for both the
  light appearance (against the popover's light container background) and the
  dark appearance (against the popover's dark container background)
- **Then** the ratio is at least **4.5:1** for normal-sized text and at least
  **3:1** for the large headline text and the large tier swatches, per WCAG AA
- **And** the resolved color is identical for the percentage path
  (`percentageColor(_:)`) and the balance path (`balanceTierColor(_:)`) so the
  two paths can never disagree, preserving (ui 04 AC2) / (ui 08 AC3)
- **And** the spec records the measured ratios (per color, per appearance) in
  its Plan so a reviewer can audit them without re-running the measurement

### AC2: Balance-thresholds controls move to the Appearance tab
- **Given** the Settings window open on the Appearance tab
- **When** it renders
- **Then** the "Balance thresholds" section (steppers, tier preview, hint) is
  shown on the Appearance tab, below the "Provider order" section
- **And** the Providers tab no longer renders any balance-thresholds section
- **And** the section's contents, stepper semantics, and persistence are
  unchanged from (ui 08 AC4) — only its tab placement moves
- **And** the section's localized header and footer strings still resolve
  through `String(localized:)` per (ui 01 AC7)

### AC3: Provider-order rows in the Appearance tab use tight padding
- **Given** the Appearance tab's "Provider order" section with multiple
  providers
- **When** it renders
- **Then** the vertical gap between consecutive provider rows is small — no
  larger than the default `List` row content spacing used elsewhere in the app
- **And** the row still supports drag-to-reorder (`.onMove`) and shows only the
  provider's display name, per (ui 09)
- **And** no new horizontal margins are introduced that would misalign the
  provider-order rows with other rows on the same tab (e.g. the relocated
  balance-thresholds rows)

### AC4: Per-provider refresh button moves to the top-right
- **Given** a configured provider's popover section rendering its `quotaContent`
- **When** the section renders
- **Then** the refresh button appears in the top-right corner of the section —
  aligned with the provider-name caption row — rather than in the bottom
  `HStack` after the divider
- **And** the button keeps its current behavior: icon-only `RefreshIcon`,
  borderless style, `"Refresh"` tooltip, disabled while refreshing, debounced
  per (ui 07 AC3/AC4)
- **And** the bottom row keeps the "Last updated: …" label and the refresh-error
  triangle indicator; only the refresh `Button` is removed from it
- **And** the same relocation applies to every provider state that currently
  shows a refresh control — if any other state needs one, it follows the same
  top-right placement

## Plan

Four independent edits; no model changes.

1. **Contrast audit + palette (AC1).** Measure the current `.green`/`.orange`/
   `.red` foreground against:
   - Light: `NSColor.windowBackgroundColor` light variant (popover container).
   - Dark: the same in dark mode.
   Use the WCAG 2.1 contrast formula
   `(L1 + 0.05) / (L2 + 0.05)` on the sRGB-relative luminance of each color.
   Record the before/after ratios in this spec's Risks or a short table in the
   commit message. If any ratio is below AA, introduce a single private helper
   — e.g. `tierColor(_ tier: Tier) -> Color` — that returns tuned `Color`
   values (typically darker greens/reds and a slightly deeper orange in light
   mode; brighter variants in dark mode) selected via
   `@Environment(\.colorScheme)` or `NSAppearance.current`. Both
   `percentageColor(_:)` and `balanceTierColor(_:)` delegate to it so the two
   paths stay in sync. SwiftUI's semantic `.green`/`.orange`/`.red` are kept as
   the dark-mode values if they already pass; only the failing appearance is
   tuned, to minimize visual drift.

   Measured baseline (SwiftUI semantic colors, macOS default palette):
   | Color  | Light ratio | Dark ratio | Pass?            |
   |--------|-------------|------------|------------------|
   | green  | TBD         | TBD        | fill at audit    |
   | orange | TBD         | TBD        | fill at audit    |
   | red    | TBD         | TBD        | fill at audit    |

2. **Move thresholds to Appearance (AC2).** In `SettingsView.swift`, remove the
   trailing `Section { BalanceThresholdsSettingsRow() }` from `providersTab`
   and append the same section to `AppearanceTab`'s `List`, after the provider
   order section. No change to `BalanceThresholdsSettingsRow` itself.

3. **Tighten provider-order spacing (AC3).** In `AppearanceTab`, apply
   `.listRowInsets` / `.listRowSeparator` tuning or wrap rows so the vertical
   gap shrinks to match the rest of the app. Prefer the smallest change that
   removes the large gap — e.g. setting explicit row content spacing rather
   than introducing a custom row layout. Keep `.onMove` intact.

4. **Relocate refresh button (AC4).** In `quotaContent(_:)` in `QuotaView.swift`:
   - Lift the `Button { viewModel.manualRefresh(for:) }` out of the bottom
     `HStack` into an overlay or a top `HStack` aligned with the
     `Text(quota.providerName)` caption row, pushed to the trailing edge with a
     `Spacer()`.
   - Leave the bottom `HStack` with `lastUpdatedLabel`, the error triangle, and
     a trailing `Spacer()` (or remove the `Spacer()` if the row becomes
     left-aligned only).
   - Keep all accessibility/tooltip/disabled behavior identical.

## Risks

- **Palette drift.** Tuning red/orange/green changes the look in both the
  popover and the Settings tier preview, since they share the resolver. The
  tuned values are chosen to pass AA while staying recognizably
  red/orange/green; if the user prefers the original hues, the audit table in
  AC1 makes the trade-off explicit (original ratio vs. AA target).
- **`@Environment(\.colorScheme)` in a menu-bar popover.** `MenuBarExtra`'s
  popover may report a color scheme that lags the user's current appearance
  during a live switch. If observed, fall back to reading
  `NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])` at render
  time. Flagged for the implementation, not a spec blocker.
- **Appearance-tab list ordering.** Moving thresholds below the provider-order
  list makes the tab longer. If the tab feels heavy, a follow-up can split it
  — out of scope here.
- **Refresh button at top-right may overlap long provider names.** The caption
  is `.caption` font and short; the button is a small glyph. An `HStack` with
  `Spacer()` keeps them apart. If a future provider has a very long display
  name, the caption should truncate before the button — verify at
  implementation.
- **No behavior change.** None of these edits alter data flow, persistence, or
  provider behavior. The orthogonal-provider rule (core 01) is preserved.

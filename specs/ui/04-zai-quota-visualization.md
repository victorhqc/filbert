## Objective

> Status: **implemented** — `Sources/App/QuotaView.swift`, `Sources/App/Resources/Localizable.xcstrings`.

Replace the z.ai popover's plain-text quota rows with a horizontal-bar
visualization, add a peak-hours block, and give the Refresh control an icon —
matching the readability of the zai-bar reference without leaking provider
concepts into Core or other providers.

## Context

- `Sources/App/QuotaView.swift` — current rendering. `usageLineRow(_:)` draws
  label + percentage text + countdown; `quotaContent(_:)` holds the footer
  (last updated + text Refresh button). Both become visualization-aware for the
  z.ai provider only, decided by `providerId` (ui 01).
- `Sources/Core/ProviderProtocol.swift` — the shared `ProviderQuota` /
  `UsageLine` / `UsageDetail` model (core 01). **No new fields are added
  here** — the bar reads existing `percentage` / `used` / `total`, and
  peak-hours is computed in the view from constants (see Plan).
- `Sources/Providers/ZAI/ZAIProvider.swift` — already maps every limit z.ai
  returns (providers 01). No change to the wire decoding.
- Reference: `ruhex/zai-bar` — same endpoint, same `(type, unit)` meanings, and
  a peak-hours block that converts the GLM Coding Plan's daily peak window to
  local time.
- Peak-hours rules (from zai-bar's README, stable as of writing):
  - Peak window: **14:00–18:00 UTC+8** (China Standard Time, no DST).
  - Advanced-model (GLM-5.2 / GLM-5-Turbo) multiplier: **3×** in peak,
    **2×** off-peak.
  - Limited-time promo: off-peak is **1×** until **2026-10-01**.
  - GLM-4.7 is always 1× (informational — the popover shows the advanced-model
    multiplier only).
- Cross-references: builds on (ui 01), consumes the data shape from
  (providers 01); keeps Core untouched per (core 01).
- i18n: every new chrome string — bar accessibility labels, peak-hours lines,
  the refresh tooltip — uses `String(localized:)` against the ZAI module's
  String Catalog (providers 01), matching (ui 01 AC7).

## Acceptance Criteria

### AC1: Horizontal usage bar per `UsageLine`
- **Given** a configured z.ai provider in the `.loaded` state
- **When** the popover renders a `UsageLine` that has either a `percentage` or
  a derivable percentage from `used` / `total`
- **Then** the row shows a horizontal bar filled to that percentage, alongside
  the existing label and numeric percentage; lines with no percentage data
  render text-only (no empty bar)

### AC2: Bar color follows usage tier
- **Given** a rendered usage bar
- **When** its percentage crosses thresholds
- **Then** the fill is green below 50%, yellow/orange from 50% to 79%, and red
  at 80% and above — matching the existing `percentageColor(_:)` tiers so the
  number and the bar never disagree

### AC3: Peak-hours block for the z.ai provider only
- **Given** the popover is rendering the `zai` provider section
- **When** the section is displayed
- **Then** a peak-hours block appears showing: the peak window in the user's
  **local** time (converted from 14:00–18:00 UTC+8), whether the user is
  currently inside the peak window, and the current advanced-model multiplier
  (3× in peak, else 1× while the promo is active, else 2×)

### AC4: Peak status is correct across time zones and the promo cutoff
- **Given** the user's local time and today's date
- **When** the peak block computes its state
- **Then** "currently in peak" is true iff the local now, converted to UTC+8,
  falls in `[14:00, 18:00)`; and the off-peak multiplier reads 1× before
  2026-10-01 and 2× on or after that date — both computed from `Date()`, not a
  cached snapshot, so it stays correct while the popover is open

### AC5: Refresh control shows an icon
- **Given** the per-provider footer with the Refresh button
- **When** it renders for any provider
- **Then** the button shows a `arrow.clockwise` SF Symbol (with a tooltip
  "Refresh") instead of the text "Refresh"; the keyboard equivalent and the
  loading-disabled state are unchanged

### AC6: Bars and peak block stay inside the popover width
- **Given** the existing `.frame(width: 280)` popover
- **When** bars and the peak block render
- **Then** nothing overflows or truncates — the bar takes the available width
  minus the percentage column, and the peak block wraps to two lines if needed

### AC7: Other providers are unaffected
- **Given** a future non-z.ai provider is configured
- **When** its section renders
- **Then** it shows the new bar visualization (bars are data-driven, not
  provider-specific), but **no** peak-hours block — the peak block is gated on
  `providerId == "zai"` and lives entirely in the view layer

### AC8: Localization parity
- **Given** the app running under a non-English locale
- **When** the new bars, peak block, and refresh tooltip render
- **Then** every user-facing string comes from `String(localized:)` — bar
  accessibility labels, "Peak hours", "In peak" / "Off peak", the multiplier
  line, and the Refresh tooltip — with entries in the String Catalog

## Plan

Three small, mostly-view-layer changes; Core is untouched.

1. **`UsageBar` SwiftUI subview** in `QuotaView.swift` (private, file-scoped).
   Takes `percentage: Double?` and a color resolved from the existing
   `percentageColor(_:)` tiers. Renders a thin track with a filled portion;
   clips to the track's corner radius. The accessibility label is a localized
   "\(pct)% used" string. Width is driven by the parent HStack, so it
   auto-fits the 280-pt popover.
2. **`PeakHoursBlock`** SwiftUI subview in `QuotaView.swift` (private,
   file-scoped). Holds the constants — `peakStartUTC8 = 14`, `peakEndUTC8 = 18`,
   `promoEnd = Date(2026-10-01)`, `tz = TimeZone(identifier: "Asia/Shanghai")`.
   Computes:
   - Local-time window: `Calendar.current` formatted with `.hourMinute`.
   - "In peak": convert `Date()` to Shanghai time, check hour ∈ `[14, 18)`.
   - Multiplier: 3× if in peak; else 1× if `Date() < promoEnd`; else 2×.
   Shown only when the surrounding section's `providerId == "zai"`.
3. **Refresh button**: replace `Text("Refresh")` with
   `Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)`
   and add `.help(String(localized: "Refresh"))`. Same `viewModel.fetchQuota`
   action, same `.disabled(ifLoadingState(providerId))` gating.
4. **Wire bars into `usageLineRow`**: insert `UsageBar(percentage:)` into the
   existing HStack beneath the label / above or next to the percentage number
   (single-line layout: label on the left, percentage on the right, bar full
   width beneath on its own row). Add a `hasPercentage` helper that returns
   `line.percentage ?? (used/total)` when both exist.

No changes to `ProviderProtocol`, `ZAIProvider`, or `QuotaViewModel`. No new
files outside `QuotaView.swift` and the existing String Catalog.

## Risks

- Peak-window math is in the view layer and recomputed on each render; if the
  popover stays open across the 14:00 / 18:00 boundary, SwiftUI may not
  re-render on its own. Mitigation: the 5-minute auto-refresh from (ui 01 AC5)
  touches the view model and triggers a re-render, and any user interaction
  (scroll, hover) does too; acceptable for a menu-bar popover.
- The 2026-10-01 promo cutoff is a hard-coded date. If z.ai extends it, this
  block will silently flip to 2× early. The date is isolated in
  `PeakHoursBlock` so a future spec can lift it into provider metadata.
- Adding a bar to non-z.ai providers (AC7) is a visible change for any future
  provider, but today z.ai is the only one, so no regression surface exists.
- `.iconOnly` labels need the `arrow.clockway` glyph to remain legible at the
  footer's `.caption` font — if not, fall back to `.titleAndIcon`.

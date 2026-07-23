## Objective

Replace the menu-bar popover's static icon with a dynamically rendered ring that
reflects the top-most configured provider's live status — a usage percentage for
window-based providers, or a remaining balance for credit-based providers — and a
short text value beside it.

## Context

- `Sources/App/AppMain.swift` — declares `MenuBarExtra(... systemImage:
  "brain.head.profile")`. Switches to the
  `MenuBarExtra(titleContent:label:)` initializer so the menu-bar label becomes
  a SwiftUI view (ring + text) while the localized string stays the window
  accessibility title.
- `Sources/App/QuotaView.swift` — already hosts `percentage(for:)`,
  `percentageColor(_:)`, `headlineBalanceColor(for:)`, and `amountText(for:)`.
  The ring extraction reuses `percentage(for:)` and `amountText(for:)` verbatim
  so the icon and the popover rows can never disagree (ui 04 AC2, ui 08 AC3).
- `Sources/App/QuotaViewModel.swift` — `configuredProviderIds` already reflects
  the user-saved order (ui 09 AC6); the top-most entry is its first element.
  `providerStates[id]` already carries the latest `.loaded(ProviderQuota)`.
- `Sources/Core/ProviderProtocol.swift` — unchanged. The icon reads the same
  `ProviderQuota` / `UsageLine` shape as the popover (core 01).
- Builds on (ui 09) for ordering, (ui 04) / (ui 08) for the percentage and
  balance semantics, and (ui 07) for the 5-minute auto-refresh that already
  drives the data. The menu-bar icon refreshes for free on the existing
  cadence — no new timer is introduced.
- Cost concern for `claude-code`: already resolved. (providers 03 AC3)
  mandates that the 5-minute auto-refresh loop and the app-launch fetch call
  `fetchQuota(for:)` directly and never spawn `claude -p`. Spawning is reserved
  for the manual Refresh button. The 5-minute refresh therefore updates the
  icon from Claude Code's cache without inurring any extra cost — no special
  rule is needed in this spec.
- macOS menu-bar rendering treats the label view as a template image: the OS
  applies its own foreground tint (black in light mode, white in dark mode,
  blue while highlighted). Per (ui 04) the popover uses tier colors
  (green/orange/red) — those colors are deliberately **not** reused on the
  icon. The ring is drawn in monochrome (`Color.primary`) and only the
  geometry encodes progress.

## Acceptance Criteria

### AC1: Menu-bar label is a SwiftUI view, not a static SF Symbol
- **Given** the app is running
- **When** the menu bar renders
- **Then** the menu-bar label is produced by a SwiftUI view passed via the
  `MenuBarExtra(_:label:)` initializer (the title string remains the
  accessibility/window title), not by `systemImage:`
- **And** the existing popover contents and Settings window are unchanged

### AC2: Top-most configured provider drives the icon
- **Given** at least one provider is configured
- **When** the menu-bar label renders
- **Then** the icon reads from the first entry of
  `viewModel.configuredProviderIds` (the user-saved top-most, per ui 09 AC6)
- **And** reordering providers in the Appearance tab (ui 09) changes which
  provider the icon reflects on the next render without an app restart

### AC3: Window-based provider renders a ring + percentage
- **Given** the top-most provider's latest state is `.loaded(ProviderQuota)`
  and the quota has at least one line for which `percentage(for:)` is non-nil
- **When** the icon renders
- **Then** it shows a circular ring whose filled arc length is
  `percentage / 100` clamped to `[0, 1]`, drawn over a tracked background ring
  in `Color.secondary.opacity(0.2)`
- **And** the percentage is rounded to the nearest whole number and rendered
  as text next to the ring in the form `NN%`, with the ring first and the
  number after it
- **And** the selected line follows the same priority the popover's headline
  uses for windowed providers — 5-hour window first, then weekly (ui 04 AC2,
  providers 01 AC5) — so the icon and the popover never disagree on which
  window is shown
- **And** the ring is an open arc with a small angular gap (a circle graph,
  not a closed pie) so the remaining portion is read as track, not as a
  second filled slice

### AC4: Balance-based provider renders a ring + currency amount
- **Given** the top-most provider's latest state is `.loaded(ProviderQuota)`,
  no line has a non-nil `percentage(for:)`, and at least one line has a
  positive `total` (ui 08)
- **When** the icon renders
- **Then** the ring's filled arc represents the balance line's `used / total`
  fraction (falling back to a full ring when `used` is nil but `total > 0`),
  reusing `amountText(for:)` for the formatted amount
- **And** the amount text appears next to the ring, ring first then amount,
  in the same currency format the popover's headline uses (ui 08 AC3)
- **And** when multiple balance lines exist, the first non-positive-filtered
  balance line drives the ring (mirrors `headlineBalanceColor(for:)`'s
  selection rule)

### AC5: Fallback to the static icon when no data is available
- **Given** any of: zero configured providers, the top-most provider's state
  is `.unconfigured` / `.setup` / `.loading` / `.error`, or the latest
  `ProviderQuota` has no usable percentage and no positive balance
- **When** the icon renders
- **Then** it shows the existing `brain.head.profile` SF Symbol and no text,
  so the menu bar never shows stale, partial, or misleading data
- **And** the popover continues to render whatever state it already renders
  for that provider (ui 07) — the icon's fallback is independent of the
  popover's content

### AC6: Ring geometry is consistent and clipped
- **Given** any percentage value, including `0`, `100`, and out-of-range
  values a provider might emit
- **When** the ring renders
- **Then** the filled arc is clamped to `[0, 1]` of the circumference before
  drawing — negative or >100 values never wrap around the track
- **And** the ring is sized to fit the menu bar's standard ~17pt content
  height (square aspect, height matched to a single-line `Text`), so the
  label does not shift the bar's vertical baseline

### AC7: Ring updates live with the existing auto-refresh
- **Given** the top-most provider is configured
- **When** the 5-minute auto-refresh loop (ui 02 AC7) completes a
  `fetchQuota(for:)` and the new `.loaded` state lands
- **Then** the ring and text update on the next render without an app
  restart or manual popover open
- **And** no new timer, scheduler, or polling loop is introduced — the icon
  is driven solely by the existing `@Observable` state mutations

### AC8: Monochrome rendering
- **Given** the icon rendering in either light or dark menu-bar mode
- **When** the ring draws
- **Then** the filled arc and the text use `Color.primary` (template) so the
  OS tint is respected, and no `.foregroundColor(.green / .orange / .red)`
  is applied to the menu-bar label — the popover keeps its tier colors, the
  menu bar does not

### AC9: Accessibility label summarizes the icon
- **Given** VoiceOver or another assistive technology focuses the menu-bar
  label
- **When** it announces the icon
- **Then** the accessibility label is a localized human sentence such as
  "<provider display name>: 42% used" or "<provider display name>: $12.34
  remaining", produced via `String(localized:)`
- **And** the fallback static icon keeps the existing
  `String(localized: "Filbert")` accessibility label

### AC10: Localization
- **Given** the app running under a non-English locale
- **When** the icon's text and accessibility label are produced
- **Then** every user-facing string goes through `String(localized:)` — the
  `NN%` format, the currency amount (already localized via
  `NumberFormatter`), and the accessibility sentence — matching (ui 02 AC10)

## Plan

1. **App: extract a `MenuBarStatusIcon` view.** New
   `Sources/App/MenuBarStatusIcon.swift`. It takes `viewModel: QuotaViewModel`
   (or, for testability, a value type carrying the resolved top-most state),
   reads `configuredProviderIds.first`, looks up `providerStates[id]`, and
   branches into:
   - window mode — when `percentage(for:)` is non-nil on the chosen line,
   - balance mode — when the quota has a positive-total balance-only line,
   - fallback — the existing `Image(systemName: "brain.head.profile")`.
   The line-selection rules mirror `QuotaView`'s private helpers; pull those
   helpers up to file-private free functions (or a small `enum
   QuotaStatusResolver`) so the icon and the popover share one implementation.
2. **App: render the ring.** SwiftUI `Circle().trim(from: 0, to:
   clampedFraction)` rotated `-90°` so the arc starts at 12 o'clock, stroked
   over a tracked `Circle()` in `Color.secondary.opacity(0.2)`. The open-gap
   look comes from `trim(to: clampedFraction * 0.85)` against a 0.85-base
   track (or equivalent) so ~15% of the circumference remains as visual
   breathing room at 100% — the exact ratio is a tuning constant in the
   view, not a Core concern.
3. **App: render the text.** An `HStack(ring, text)` with `Image`-first
   ordering, using `.font(.caption2.monospacedDigit())` and `.foregroundStyle
   (.primary)` so the OS tint is preserved. Frame height matches the ring's
   square size so the menu bar baseline does not shift.
4. **App: swap `AppMain`'s `MenuBarExtra` initializer.**
   ```swift
   MenuBarExtra(String(localized: "Filbert")) {
       QuotaView(viewModel: viewModel)
           .frame(width: 280)
   } label: {
       MenuBarStatusIcon(viewModel: viewModel)
   }
   .menuBarExtraStyle(.window)
   ```
   The `String(localized:)` argument remains the accessibility title (AC9);
   the `label:` closure produces the visible menu-bar content.
5. **App: no change to `QuotaViewModel`.** All state the icon needs is
   already published (`configuredProviderIds`, `providerStates`). The icon
   is a pure function of that state.
6. **Tests: `MenuBarStatusIcon` resolution logic.** New
   `Tests/AppTests/MenuBarStatusIconTests.swift` covering the pure
   line-selection function (no SwiftUI): empty providers → fallback,
   top-most `.loading` → fallback, window line present → percentage mode
   with 5-hour-before-weekly priority, no percentage but positive total →
   balance mode, out-of-range percentage → clamped to `[0, 1]`. The ring
   geometry itself is verified via the same clamping function the view
   calls.

No code is written until this spec is reviewed.

## Risks

- `MenuBarExtra(_:label:)` on macOS 14 (Sonoma, our deployment target)
  supports a `label:` closure, but the menu bar imposes a ~17pt content
  height and renders the label as a template image. The ring must be drawn
  with `Color.primary` / template styling — any explicit tint is ignored or
  makes the icon invisible in one mode. If the ring renders too thin to
  read at 17pt, the fallback is to fall back to a percentage-only text
  label (no ring) for the visible menu bar, keeping the ring for the
  popover header only. Out of scope here; revisit on first user feedback.
- The ring's open-gap ratio is a visual tuning constant. A bad value (e.g.
  too large a gap) can make low percentages read as "empty" and high
  percentages read as "incomplete". Plan §2 isolates it to one constant so
  it can be tweaked without touching Core.
- Selecting the top-most configured provider means a user who has not
  reordered (ui 09 AC4) sees the display-name-first provider. That matches
  today's popover ordering and is the least surprising default; called out
  so reviewers don't expect provider-specific priority in Core.
- The 5-hour-window percentage is a snapshot of when `fetchQuota` last ran.
  The icon will appear "stale" between refreshes (up to 5 minutes). This is
  the same freshness contract the popover already has (ui 07); no new
  polling is introduced to make the icon feel real-time — doing so would
  violate the rate-limit rule in `AGENTS.md` §3 and the explicit no-spawn
  rule in (providers 03 AC3).
- If a provider returns both a percentage line and a balance line on the
  same quota (capped API plans, per core 01), the icon picks the percentage
  line (AC3) and ignores the balance. This is consistent with how the
  popover's headline works today and avoids contradictory numbers in the
  menu bar.

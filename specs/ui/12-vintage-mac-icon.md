## Objective

Add an opt-in "Vintage Mac" appearance setting that, when enabled, replaces the
menu-bar status ring/text with a tiered Happy / Neutral / Sad Mac pixel face
derived from the top-most provider's status, drawn into a bitmap `NSImage` so
`MenuBarExtra`'s label layer accepts it.

## Context

- `Sources/App/MenuBarStatusIcon.swift` — renders today's ring. `MenuBarExtra`
  on macOS 14 silently drops arbitrary `Shape` / `Canvas` content, so the ring
  is drawn into a bitmap `NSImage` via `CGContext` and wrapped with
  `isTemplate = true` so the OS chrome tints it. A "Vintage Mac" mode reuses
  that exact rendering pipeline; only the bitmap content changes (a face
  instead of an arc). Cited by (ui 10).
- `Sources/App/QuotaStatusResolver.swift` — pure resolver producing
  `Status.window(percentage:)`, `Status.balance(used:total:formattedAmount:)`,
  or `Status.fallback`. Already shared by the popover and the icon. Vintage Mac
  introduces one new pure helper here, `tier(for:)`, so the icon, the popover,
  and the tests share one mood rule. Cited by (ui 10).
- `Sources/App/QuotaView.swift` — owns `percentageColor(_:)` for the window path
  (`< 50 → good`, `50 ..< 80 → warn`, `else → critical`) and `balanceTierColor`
  for the balance path (`BalanceThresholds.low` / `.ok`). The new tier helper
  must reuse these exact thresholds so the mac face can never disagree with the
  popover's tier colors. Cited by (ui 04 AC2), (ui 08 AC3).
- `Sources/Core/BalanceThresholds.swift` — the UserDefaults-backed thresholds
  store with a test-swappable `setUserDefaults(_:)` escape hatch. The new
  Vintage Mac setting follows the same store pattern (UserDefaults, not
  Keychain — `AGENTS.md` §3 reserves Keychain for secrets). Cited by (ui 08
  AC2).
- `Sources/App/SettingsView.swift` — `AppearanceTab` is where the toggle lives,
  next to the existing "Balance thresholds" section relocated by (ui 11 AC2).
- The classic Happy Mac / Sad Mac are 1-bit pixel art (historically ~32×32,
  black on transparent). Re-drawing them as `CGContext`-filled rects keeps the
  artwork crisp at the menu bar's ~17pt content height, themeable via
  `isTemplate`, and avoids shipping a sourced binary we cannot verify the
  license of. The Neutral face is the Happy model with the smile row replaced
  by a straight horizontal mouth.
- Builds on (ui 10) for the menu-bar label pipeline, (ui 08) for balance
  thresholds, (ui 04) for percentage thresholds, and (ui 11) for the
  Appearance tab layout.

## Acceptance Criteria

### AC1: A "Vintage Mac" toggle appears on the Appearance tab, off by default
- **Given** the Settings window open on the Appearance tab
- **When** it renders
- **Then** a new "Vintage Mac" `Toggle` appears, below the "Balance thresholds"
  section, with a localized label and a one-line localized subtitle explaining
  the effect ("Show a classic Happy / Sad Mac face instead of the ring in the
  menu bar")
- **And** the toggle defaults to **off** for new and existing users, so the
  ring/text icon is unchanged unless the user opts in
- **And** the toggle's state persists across app restarts via UserDefaults
  (same store pattern as `BalanceThresholds`), and is **not** written to the
  Keychain

### AC2: A pure `tier(for:)` helper derives good / warn / critical from status
- **Given** a resolved `QuotaStatusResolver.Status`
- **When** `QuotaStatusResolver.tier(for:)` is called
- **Then** for `.window(percentage:)` it returns `.good` when `percentage < 50`,
  `.warn` when `50 <= percentage < 80`, and `.critical` otherwise — the exact
  thresholds `QuotaView.percentageColor(_:)` uses today (ui 04 AC2)
- **And** for `.balance(used:total:formattedAmount:)` it tiers the **available
  amount** (`total`) directly against `BalanceThresholds.low` / `.ok` via the
  same rule the popover's `balanceTierColor` uses (ui 08 AC3) — `< low →
  .critical`, `[low, ok) → .warn`, `>= ok → .good`. The `used` value is
  ignored on purpose: DeepSeek emits `used: nil` (providers 04), and the user's
  mental model is "low available money = sad", which the available-amount rule
  captures directly
- **And** for `.fallback` it returns nil (no tier — the SF Symbol fallback
  applies)
- **And** the helper lives in `QuotaStatusResolver` with no SwiftUI dependency,
  so `Tests/AppTests` can exercise it directly

### AC3: A Vintage Mac face is drawn for each tier into a template `NSImage`
- **Given** Vintage Mac mode is enabled and a resolved non-fallback status
- **When** the menu-bar label renders
- **Then** the icon is a bitmap `NSImage` produced by `CGContext`, with
  `isTemplate = true`, drawn at the same ~17pt content height as the existing
  ring — never as a SwiftUI `Canvas` or `Shape`, which `MenuBarExtra` drops on
  macOS 14
- **And** there are exactly three face renderers keyed by tier:
  `.good → Happy`, `.warn → Neutral`, `.critical → Sad`
- **And** the three faces share a single monitor outline + screen; only the
  mouth shape differs — Happy curves up, Neutral is a straight horizontal line,
  Sad curves down — so the family is visually coherent
- **And** every renderer draws only solid black (`CGColor(gray: 0, alpha: 1)`)
  on transparent; no grayscale halftones, no color, since the OS tints the
  template

### AC4: Vintage Mac replaces the ring only; text stays beside the face
- **Given** Vintage Mac mode is enabled and the top-most provider resolves to
  either `.window` or `.balance`
- **When** the menu-bar label renders
- **Then** the mac face replaces **only the ring**; the trailing text value
  (`NN%` for window providers, the localized currency amount for balance
  providers) stays, ordered **face first, then text** — same layout and fonts as
  the existing ring + text label (ui 10 AC3/AC4)
- **And** the face updates on the next render whenever the tier changes — no
  new timer is introduced; the existing 5-minute auto-refresh (ui 07) drives
  it for free
- **And** a tier change that stays inside the same bucket (e.g. 42% → 47%,
  both `.good`) does not re-rasterize — the bitmap is cached per tier, mirroring
  the existing `MenuBarRingImageCache` pattern

### AC5: Fallback tier keeps the existing SF Symbol
- **Given** Vintage Mac mode is enabled and the resolved status is `.fallback`
  (no configured providers, `.loading`, `.error`, no usable data, etc.)
- **When** the menu-bar label renders
- **Then** it shows the existing `Image(systemName: "brain.head.profile")` with
  the existing localized "Filbert" accessibility label — identical to the
  non-Vintage fallback today (ui 10 AC5)
- **And** the popover's own content is unaffected by Vintage Mac mode

### AC6: Disabling the mode restores the ring + text exactly
- **Given** Vintage Mac mode is enabled and showing a mac face
- **When** the user turns the toggle off
- **Then** the menu-bar label reverts to the existing ring + text behavior from
  (ui 10), with no app restart required
- **And** the popover, Settings, and all other UI is unchanged by toggling

### AC7: Accessibility label still summarizes status
- **Given** VoiceOver focuses the menu-bar label under Vintage Mac mode
- **When** it announces the icon
- **Then** the accessibility label reuses the same localized human sentences
  produced today (e.g. "Claude Code: 42% used", "DeepSeek: $12.34 remaining")
  from (ui 10 AC9), so assistive tech loses no information when the visible
  text is hidden behind the face
- **And** the fallback keeps its existing "Filbert" label

### AC8: Localization
- **Given** the app running under a non-English locale
- **When** the toggle label, subtitle, and accessibility labels render
- **Then** every user-facing string goes through `String(localized:)` and is
  added to `Sources/App/Resources/Localizable.xcstrings`, matching (ui 01 AC7)
  and (ui 10 AC10)

## Plan

1. **Core: a `VintageMacIcon` UserDefaults store.** New
   `Sources/Core/VintageMacIcon.swift`, mirroring `BalanceThresholds`'s shape:
   a `public enum VintageMacIcon { static var isEnabled: Bool; static func
   setEnabled(_:); static func setUserDefaults(_:) }`, backed by a private
   UserDefaults key. Defaults to `false`. No secrets — stays out of Keychain
   per `AGENTS.md` §3.
2. **App: `tier(for:)` on `QuotaStatusResolver`.** Add a pure
   `static func tier(for status: Status) -> Tier?` that returns `.good` /
   `.warn` / `.critical` per AC2, reusing the exact thresholds from
   `QuotaView.percentageColor` (window) and `balanceTierColor` (balance).
   Promote the private `Tier` enum out of `QuotaView.swift` (or expose a
   `QuotaStatusResolver.Tier`) so the resolver, the popover, and the renderer
   share one type.
3. **App: `MenuBarMacFaceRenderer`.** New renderer in
   `Sources/App/MenuBarStatusIcon.swift` (or a sibling file) that draws one of
   three faces into a bitmap `NSImage` via `CGContext`, mirroring
   `MenuBarRingRenderer`'s context setup (`CGColorSpaceCreateDeviceGray`,
   `alphaOnly`, `isTemplate = true`). The face is a small grid of filled rects:
   shared monitor outline + screen for all three tiers, plus a per-tier mouth
   (smile / line / frown). Constants: ~28px bitmap (matches the ring), pixel
   rects chosen to read as the classic 1-bit mac face at ~14pt.
4. **App: cache + selection.** A `MenuBarMacFaceCache` keyed by `Tier` (three
   entries, built lazily), mirroring `MenuBarRingImageCache`. In
   `MenuBarStatusIcon.content`, when `VintageMacIcon.isEnabled` is true and
   `tier(for:)` returns non-nil, render an `HStack(face, text)` — the face
   `Image` (template, `@2x` frame) first, then the existing `percentageText`
   or `formattedAmount` text, identical fonts and foreground style as today.
   When disabled or nil, render the existing ring/text (window, balance) or SF
   Symbol (fallback) unchanged.
5. **App: Appearance tab toggle.** In `AppearanceTab`, add a `Section` below
   "Balance thresholds" with a `Toggle` bound to a `@State` mirror of
   `VintageMacIcon.isEnabled` that calls `VintageMacIcon.setEnabled(_:)` on
   change. Localized label + subtitle per AC1.
6. **Tests: `VintageMacIcon` store.** New
   `Tests/CoreTests/VintageMacIconTests.swift` mirroring
   `BalanceThresholdsTests`: default false, set true round-trips, survives
   `setUserDefaults` swap, invalid types fall back to default.
7. **Tests: `tier(for:)`.** Extend `Tests/AppTests/MenuBarStatusIconTests.swift`
   with cases for AC2: window at 0/49/50/79/80/100 → good/warn/critical
   boundaries; balance with `used: nil` and various `total` against the live
   `BalanceThresholds`; `.fallback → nil`; out-of-range window percentage
   clamps at the tier boundary, not inside the resolver.

No code is written until this spec is reviewed.

## Risks

- **Recognizability at ~14pt.** The classic faces are detailed; at menu-bar
  size the mouth shape is the only reliable differentiator. Plan §3 makes the
  mouth the largest single feature and keeps the monitor outline minimal. If
  the faces read as identical in a screenshot review, the fallback is to drop
  the monitor outline and ship just the screen + face — still legible, still
  1-bit. Flagged for the first visual review, not a spec blocker.
- **Tier disagreement with the popover.** The popover shows both the colored
  number/bar (window) and the colored Circle (balance) using the same
  thresholds. Vintage Mac must reuse those thresholds verbatim (AC2) — any
  drift means the menu-bar face and the popover disagree on mood. Plan §2
  centralizes the rule in `QuotaStatusResolver.tier(for:)` to prevent this.
- **Balance path with `used: nil`.** Real balance providers (DeepSeek) emit
  `used: nil` (providers 04). AC2 tiers on the **available amount** (`total`)
  directly, so a low DeepSeek balance shows Sad Mac and a healthy balance shows
  Happy Mac — matching the popover's `balanceTierColor` rule (ui 08 AC3). The
  `used` value is intentionally ignored so the icon never disagrees with the
  popover's balance Circle.
- **Template-tint contrast in dark mode.** The face is solid black on
  transparent with `isTemplate = true`; macOS inverts it for dark mode and
  tints blue on hover. The existing ring uses the same approach and is known
  to render correctly, so no new risk — flagged only because the face has more
  ink than the ring stroke and should be eyeballed at hover.
- **UserDefaults parity.** Vintage Mac follows `BalanceThresholds`'s store
  pattern, so it inherits the same single-user, single-default-store
  assumption. No new keychain, no new file on disk — matches `AGENTS.md` §3.
- **No new menu-bar code paths.** Vintage Mac is a branch inside the existing
  `MenuBarStatusIcon.content`; the existing ring/text/fallback paths are
  untouched, so (ui 10) AC1–AC10 all remain in force when the toggle is off.

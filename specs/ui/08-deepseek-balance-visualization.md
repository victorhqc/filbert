## Objective

Hide empty DeepSeek balance rows in the popover and color the remaining ones
by user-configurable credit-amount thresholds ("low" / "ok"), surfaced as a
Settings section.

## Context

- `Sources/App/QuotaView.swift` — current rendering. `usageLineRow(_:)` draws
  every `UsageLine` it receives, including zero balances. `percentageColor(_:)`
  handles percentage tiers (ui 04) but is never invoked on DeepSeek rows
  because `percentage(for:)` returns nil when `used` is missing. Both helpers
  become amount-aware for credit-style lines.
- `Sources/App/SettingsView.swift` — currently a single `List` of provider
  rows (ui 02). Gains a "Balance thresholds" `Section` exposing two
  stepper-controlled values plus a tier preview.
- `Sources/Core/ProviderProtocol.swift` — unchanged. `UsageLine.total` already
  carries the balance amount; no model field is added (core 01).
- `Sources/Core/ProviderOverrides.swift` — pattern reference for the new
  UserDefaults-backed store. Thresholds are not secrets, so they live in
  `UserDefaults` too (AGENTS.md §3).
- `Sources/Providers/DeepSeek/DeepSeekProvider.swift` — unchanged. It already
  emits one `UsageLine` per balance field with `total` set (providers 04 AC2);
  filtering happens in the view layer, not the provider.
- Cross-references: builds on (ui 04), consumes the data shape from
  (providers 04); keeps the Core model untouched per (core 01); inherits i18n
  rules from (ui 01 AC7).
- Currency: DeepSeek returns `USD` or `CNY` (providers 04). Thresholds are
  currency-agnostic — a single pair applies to whatever currency the user is
  billed in. See Risks.

## Acceptance Criteria

### AC1: Balance lines with non-positive or duplicate totals are not rendered
- **Given** the popover is rendering a `UsageLine` whose `used` is nil and
  whose `percentage` is nil
- **When** `usageLineRow(_:)` runs and `total` is nil or `<= 0`
- **Then** the row is omitted entirely (no label, no value, no bar)
- **And** lines with a positive `total` still render normally
- **And** when two balance rows would show the same positive `total`, only the
  first balance row (the Total balance in DeepSeek's ordering) is rendered —
  duplicate amounts are visually confusing and carry no extra information
- **And** the provider's `headline` keeps surfacing the total regardless
  (e.g. "$0 left" still appears when the account is empty), so the user is
  never left without a signal

### AC2: User-configurable low and ok thresholds, persisted
- **Given** the user opens Settings → Balance thresholds
- **When** they set "Low below" to 5 and "OK above" to 20
- **Then** both values are persisted in `UserDefaults` and survive relaunch
- **And** defaults are `5` (low) and `20` (ok) when the user has never set them
- **And** `ok` must be strictly greater than `low`; on save, the store clamps
  `ok = max(ok, low + 1)` and rejects non-positive values by ignoring them

### AC3: Headline colored by amount tier
- **Given** a rendered balance `UsageLine` whose `total` is positive and for
  which `percentage(for:)` returns nil
- **When** the headline's tier color is computed (from the first balance
  line, which the headline summarizes)
- **Then** it is red when `total < lowThreshold` (almost gone or gone),
  orange when `lowThreshold <= total < okThreshold` (decreasing), and green
  when `total >= okThreshold` (healthy)
- **And** the color is shown as a small filled `Circle` placed immediately
  after the headline (e.g. `$7.88 left ●`), sized to match the headline's
  cap height — no usage bar is drawn for balance rows, and no `Circle` is
  drawn on individual balance rows; they show only the formatted amount text
- **And** percentage-based rows continue to use the existing
  `percentageColor(_:)` tiers and their bar unchanged

### AC4: Settings section for thresholds
- **Given** the Settings window
- **When** it renders
- **Then** a "Balance thresholds" `Section` appears below the provider list,
  containing a stepper for "Low below", a stepper for "OK above", and a
  three-circle preview (red / orange / green) using the same `Circle` shape
  the popover shows next to the headline, so the Settings preview and the
  popover indicator stay visually identical
- **And** the "OK above" stepper's lower bound tracks the current "Low below"
  value so the user cannot enter an impossible pairing from the UI
- **And** a hint explains the thresholds apply to all provider currencies
- **And** every chrome string comes from `String(localized:)` per (ui 01 AC7)

### AC5: Other providers are unaffected
- **Given** a provider whose lines carry percentage data (z.ai, Claude Code)
- **When** its section renders
- **Then** its colors and bars follow the existing percentage path; only
  balance-only rows take the new amount-based path
- **And** no `if providerId == "deepseek"` branch is introduced — the path is
  selected from the line's data shape, preserving the orthogonal provider
  rule (core 01, ui 02 AC9)

### AC6: Localization parity
- **Given** the app running under a non-English locale
- **When** the threshold settings and balance rows render
- **Then** every new user-facing string resolves through
  `String(localized:)` — section title, stepper labels, hint, color-preview
  captions — with entries seeded in the App module's String Catalog

## Plan

Three layered changes; Core's `ProviderQuota` model is untouched.

1. **`BalanceThresholds` in Core.** A new file
   `Sources/Core/BalanceThresholds.swift` mirroring `ProviderOverrides`'s shape:
   - `static var low: Double` — reads `UserDefaults` key
     `"balance-thresholds-low"`, default `5`.
   - `static var ok: Double` — reads `"balance-thresholds-ok"`, default `20`.
   - `static func set(low:ok:)` — writes both, validating `low >= 0` and
     `ok > low`; clamps `ok` upward instead of throwing so the UI stays simple.
   - `static func setUserDefaults(_:)` for tests, identical pattern to
     (core 02 Plan 4).

2. **`QuotaView` rendering.**
   - Callers filter the lines array before `ForEach` so SwiftUI sees a stable
     list. Balance-only lines (`percentage(for:)` returns nil) with nil or
     `<= 0` total are dropped; when two balance rows would show the same
     positive total, only the first (the Total balance) is kept.
   - Add `amountColor(for: UsageLine) -> Color?` next to
     `percentageColor(_:)`. Returns nil for percentage-bearing lines; for
     balance-only lines with `total > 0`, picks red / orange / green from
     `BalanceThresholds.low` / `.ok`.
   - The balance row renders only the amount text (formatted via a small
     `NumberFormatter` on the line's `unit`). No `Circle`, no usage bar.
   - The headline gains a small filled `Circle` in the first balance line's
     tier color, placed immediately after the headline text. The circle's
     diameter tracks the headline's font size so it reads as a status glyph,
     not a separate control. The existing `UsageBar` (ui 04) remains in place
     for percentage rows.

3. **`SettingsView` thresholds section.** Append a `Section` to the existing
   `List`:
   - `Stepper(value: $lowInput, in: 0...1_000, step: 1)` labelled "Low below".
   - `Stepper(value: $okInput, in: (lowInput + 1)...1_000, step: 1)` labelled
     "OK above" — the lower bound moves with `lowInput`.
   - Three `Circle` swatches (red / orange / green) with text captions showing
     the resulting ranges, e.g. "under $5", "$5–$20", "$20 and up".
   - A caption: "Applies to every provider currency (USD, CNY, …)."
   - On change, call `BalanceThresholds.set(low:ok:)` with the clamped values.

4. **Tests.**
   - `Tests/CoreTests/BalanceThresholdsTests.swift` — round-trip, defaults,
     clamping, `ok > low` enforcement, isolated `UserDefaults` (same setup as
     the existing `ProviderOverridesTests`).
   - No new DeepSeek test — the provider is unchanged.

No changes to `ProviderProtocol`, `DeepSeekProvider`, or any other provider
module. The App layer reads `BalanceThresholds` directly — the same pattern
`SettingsView` already uses for `ProviderOverrides.baseURL(for:)` (core 02).

## Risks

- **Currency-agnostic thresholds.** A user billed in both USD and CNY sees the
  same numeric gate on both. $5 is a meaningful "low" for USD; for CNY (where
  typical balances run ≥ 100) it would always look "ok". Accepted for v1 —
  per-currency thresholds can land in a follow-up spec if the user actually
  hits this. The hint in AC4 calls it out so the user is not surprised.
- **Filtering rule hides zero balances.** When `granted_balance == 0`, the
  Granted credits row disappears. This matches the user's stated intent ("only
  render the labels if we plan to render anything"). The headline still
  surfaces the total, so the user is never blind to a true zero balance.
- **Deduplication hides sub-component rows.** When `granted_balance ==
  topped_up_balance` (or either equals `total_balance`), only the Total
  balance row survives. The user loses visibility into the split — accepted
  because identical amounts carry no extra information, and the headline
  Circle still reflects the total.
- **Circle on headline, not rows.** The tier indicator lives on the headline
  only; individual balance rows are uncolored. Users scanning the rows won't
  see per-line tier feedback — the headline is the single source of truth for
  tier status.
- **Two-breakpoint model.** The request mentioned "low / medium / ok" but only
  two transitions exist (red→orange, orange→green). Reduced to two steppers
  for UX simplicity; a third breakpoint can be added later without breaking
  the storage shape.
- **Thresholds in `UserDefaults` are visible to anything in the suite.** Same
  posture as (core 02) — they are not secrets, so Keychain stays reserved for
  API keys (AGENTS.md §3).
- **Circle as tier indicator, not progress.** The dot next to the amount
  encodes tier only (red/orange/green); it carries no quantitative meaning.
  Users expecting a fill bar may misread it. The dot's small size (matched to
  the text cap height) is intended to read as a status glyph, not a control —
  if testers find it ambiguous, switching to an SF Symbol (e.g.
  `circle.fill`) or adding a tooltip is a follow-up that does not change the
  ACs.

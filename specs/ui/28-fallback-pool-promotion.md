## Objective

When a provider's limit group runs out and its credit or money pool starts to decrease, show that pool as the provider's main allowance and move the exhausted limits to a smaller place.

## Context

- Status: draft for review. No production changes accompany this proposal.
- Builds on the line IDs, limit groups, and forecasts of (core 12). Codex is the first provider to use it (providers 18).
- Today Codex shows its credits as a small detail under the five-hour row (providers 05 AC7). When the windows reach 100%, the card still leads with the exhausted windows while work continues on credits.
- Whether a provider switches to credits on its own, or only after a user setting, is not verified. The app detects the switch from the data instead: the pool must decrease while the limits are exhausted.
- `Sources/Core/ProviderProtocol.swift` — `UsageLine` gains an optional fallback declaration.
- `Sources/App/QuotaView.swift` — renders the title and rows in provider order.
- `Sources/App/UsageLineRow.swift` — renders rows and their small detail lines.
- `Sources/App/QuotaStatusResolver.swift` — `resolve(for:)` picks the first percentage line, so exhausted windows show as critical even while credits are in use. The collapsed card (`CompactProviderStatus.swift`) and the menu bar (`MenuBarProviderPresentation.swift`, `MenuBarStatusVisual.swift`) both read this status.
- `Sources/Core/BalanceThresholds.swift` — user-configurable low and ok balance thresholds, shared by every balance status.
- `Sources/App/Resources/Localizable.xcstrings` — new labels and accessibility text.
- `Tests/AppTests/` — layout, status, and accessibility tests.

## Acceptance Criteria

### AC1: Providers declare candidate fallback pools

- **Given** a provider has a credit or money pool that can back a limit group
- **When** it maps an upstream result
- **Then** the pool's `UsageLine` names the limit group it can back
- **And** the declaration only makes the pool a candidate; promotion needs observed use (AC2)
- **And** a provider without the declaration keeps today's layout
- **And** Core and App contain no branch keyed on a provider ID.

### AC2: Promotion requires an observed decrease

- **Given** a limit group with a declared fallback pool, and at least one line in the group reports 100% used
- **When** two consecutive accepted observations, both taken while the group is exhausted, show the pool's balance decreasing
- **Then** the provider promotes the pool
- **And** a balance increase never promotes the pool, because the user may have just topped up
- **And** an unchanged balance does not promote the pool
- **And** the first observation after launch, or after the group becomes exhausted, only sets the baseline
- **And** duplicate, stale, or failed observations never count as a decrease (core 12 AC4)
- **And** a projected depletion (core 12 AC7) never promotes the pool
- **And** the baseline is memory-only and clears under the same lifecycle events as forecast history (core 12 AC11).

### AC3: The promoted card leads with the pool

- **Given** a promoted pool
- **When** the expanded card renders
- **Then** the title shows the pool, e.g. "Credits: 1,159.57", replacing the exhausted window's title
- **And** when the pool has an estimated forecast, the title adds it with the evidence line below, e.g. "Credits: 1,159.57 · About 3h of use remaining" and "Based on the last 20 minutes" (core 12 AC9)
- **And** the pool's row renders first, in the main row style
- **And** each exhausted window moves to a small detail line where the credits used to sit, e.g. "5-hour window · Limit reached · resets in 2h 10m"
- **And** windows in the group that are not exhausted keep their normal rows and forecast lines
- **And** no text predicts when consumption will switch back to the windows, apart from their reset countdown (core 12 AC8).

### AC4: The collapsed card and the menu bar follow the pool

- **Given** a promoted pool
- **When** `QuotaStatusResolver` resolves the provider's status
- **Then** it returns the pool's balance status instead of the exhausted window
- **And** the collapsed card shows the pool's tier dot and amount, like other balance providers
- **And** the menu bar shows the pool's balance status, like other balance providers
- **And** the tier uses the existing `BalanceThresholds`
- **And** the menu-bar accessibility label names the pool, e.g. "Codex: 1,159.57 credits".

### AC5: The layout returns when a measurement confirms the reset

- **Given** a promoted pool
- **When** a new provider measurement shows the exhausted windows have reset, usually back to 0%, and no line in the group is still at 100%
- **Then** the card, the collapsed card, and the menu bar return to the normal layout, with the pool back in its own row
- **And** the menu bar turns back from the provider glyph into the window ring
- **And** a reset of one window does not demote the pool while another window in the group is still at 100%, because usage is still blocked
- **And** a first reading after the reset above 0% still counts, because usage can resume before the next refresh
- **And** this rule applies only to a promoted pool; a provider that never switched to credits keeps today's ring behavior
- **And** a promoted pool whose balance stops decreasing stays promoted while the group is still exhausted
- **And** a reset time passing on the local clock does not change the layout on its own; the exhausted line shows "resets now" until a measurement arrives.

### AC6: Stale data stays honest

- **Given** the provider's data is stale or the last refresh failed
- **When** the card renders
- **Then** the layout follows the last displayed measurement, with the existing stale marker
- **And** it does not switch layouts from data the card is not showing.

### AC7: Accessibility

- **Given** a promoted pool
- **When** VoiceOver reads the card
- **Then** it says the pool is in use and which limits were reached, with their reset times, e.g. "Using credits. 5-hour window limit reached, resets in 2 hours 10 minutes"
- **And** it conveys the layout change without relying on color or order alone.

### AC8: Promotion is tested

- **Given** the feature is implemented
- **When** App tests run
- **Then** they cover:
  - promotion after a decrease while exhausted
  - no promotion on an increase, an unchanged balance, the first observation, a duplicate read, or without a declaration
  - partial exhaustion with a normal sibling row
  - a passed local reset without a new measurement
  - demotion after a reset measurement, including a first reading above 0%
  - no demotion while another window in the group is still at 100%
  - the menu bar returning from the glyph to the ring
  - stale data
  - the promoted title with and without a forecast
  - the collapsed-card and menu-bar status, including the balance tier
  - VoiceOver text.

## Plan

1. Add an optional `fallbackForLimitGroup` to `UsageLine`, defaulting to `nil`.
2. Add a memory-only promotion tracker. It records each candidate pool's balance while its group is exhausted, and promotes the pool on the first decrease between consecutive accepted observations. Feed it from the existing accepted-result path.
3. Add a pure App resolver that takes the lines and the tracker state, and returns either the normal layout or the promoted layout: the pool line, the exhausted lines, and the remaining rows. Keep it free of SwiftUI so `Tests/AppTests` can cover it.
4. Make `QuotaStatusResolver.resolve(for:)` use that resolver, so the collapsed card and the menu bar follow the promoted pool.
5. Render the promoted layout in `QuotaView` and `UsageLineRow`. Reuse the small detail-line style for exhausted windows.
6. Declare Codex credits as the candidate fallback for its window group in (providers 18).
7. Run the focused tests and the repository validation gate. Manually check the promoted card at normal width, the collapsed card, the menu bar, and VoiceOver.

```
Normal                                 Promoted (5-hour window exhausted, credits decreasing)
0% · resets in 5 hours                 Credits: 1,159.57 · About 3h of use remaining
5-hour window                 0%       Based on the last 20 minutes
▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬                      Credits                  1,159.57
resets in 5 hours                        5-hour window · Limit reached · resets in 2h 10m
Weekly                   7% used       Weekly                   7% used
▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬                      ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬
6d 7h left  About 14,8%/day available  6d 7h left  About 14,8%/day available
Credits                   1,159.57
```

## Risks

- Promotion needs at least one decrease after exhaustion, so the card keeps the exhausted layout for at least one refresh after credits start being used.
- A top-up and spending inside one refresh interval can cancel out and delay promotion.
- If something else spends the pool while the limits are exhausted, the app promotes the pool even though the windows are what blocks the user.
- `BalanceThresholds` were tuned for currency balances. Credit units may need their own thresholds later. Until then, the tier may be too relaxed or too strict for credits.
- In the ring menu-bar style, balance providers show only the provider glyph, with no ring. A promoted provider looks the same while it uses credits. This is accepted; the ring returns after the reset (AC5).
- At the boundary the layout can flip between refreshes. Measurement-only promotion and demotion keep it tied to real data.

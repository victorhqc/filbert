## Objective

When a provider's limit group runs out and its credit or money pool starts to decrease, show that pool as the provider's main allowance and move the exhausted limits to a smaller place.

## Context

- Status: partially implemented on `ferat/allowance-depletion-codex`, together with (providers 18). Plan steps 1–6 are implemented; the manual check in step 7 is open. Updated on 2026-10-12 with the Codex capture (providers 18).
- Builds on the line IDs, limit groups, and forecasts of (core 12). Codex is the first provider to use it (providers 18).
- (core 12 AC15) keeps each line's notice with its line: the headline speaks for one line, and a group line at 100% reads "Limit reached" in its row. While a pool is promoted, the pool is that line (AC3). (core 12 AC15) also removed the headline label, which the promoted headline needs again.
- Codex shows its credits in their own row after the windows (providers 18 AC4). When the windows reach 100%, the card still leads with "100% · Limit reached" while work continues on credits.
- Codex switches to credits on its own. On 2026-10-12 the five-hour window went from 98% to 100% between two reads, `rateLimitReachedType` became `"rate_limit_reached"`, and credits fell by 0.94 on the same read; the weekly window was at 66% (providers 18 Evidence). The next two reads fell by 2.52 and 4.57 credits. The app still detects the switch from the data: the pool must decrease while the limits are exhausted.
- `Sources/Core/ProviderProtocol.swift` — `UsageLine` gains an optional fallback declaration.
- `Sources/App/QuotaView.swift` — renders the headline and rows in provider order.
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
- **When** two consecutive accepted observations show the pool's balance decreasing, and the later one is taken while the group is exhausted
- **Then** the app promotes the pool; the provider only declares the candidate (AC1)
- **And** a balance increase never promotes the pool, because the user may have just topped up
- **And** an unchanged balance does not promote the pool
- **And** the first observation after launch only sets the baseline
- **And** a decrease from the last observation before exhaustion to the first exhausted one counts, because Codex spends credits from the request that reaches the limit; the pool is then promoted on the same read as "Limit reached"
- **And** duplicate, stale, or failed observations never count as a decrease (core 12 AC4)
- **And** a projected depletion (core 12 AC7) never promotes the pool
- **And** the baseline is memory-only and clears under the same lifecycle events as forecast history (core 12 AC11).

### AC3: The promoted card leads with the pool

- **Given** a promoted pool
- **When** the expanded card renders
- **Then** the pool is the line the headline speaks for (core 12 AC15), and the headline names it, e.g. "Credits: 1,159.57", replacing the "Limit reached" headline (core 12 AC9)
- **And** when the pool has an estimated forecast, the headline adds it with the evidence line below, e.g. "Credits: 1,159.57 · About 3h of use remaining" and "Based on the last 20 minutes" (core 12 AC9)
- **And** the pool's row renders first, in the main row style
- **And** each exhausted window moves to a small detail line under the pool's row, e.g. "5-hour window · Limit reached · resets in 2h 10m"
- **And** windows in the group that are not exhausted keep their normal rows and forecast lines
- **And** no text predicts when consumption will switch back to the windows, apart from their reset countdown (core 12 AC8).

### AC4: The collapsed card and the menu bar follow the pool

- **Given** a promoted pool
- **When** `QuotaStatusResolver` resolves the provider's status
- **Then** it returns the pool's amount instead of the exhausted window's 100%
- **And** the menu bar shows the provider glyph and the amount, e.g. "803,74", in place of the ring and "100%", like other balance providers
- **And** the collapsed card shows the amount, like other balance providers
- **And** a currency pool keeps its tier from `BalanceThresholds`; a credits pool shows no tier color, because the thresholds are in currency (core 13 AC3)
- **And** the menu-bar accessibility label names the pool, e.g. "OpenAI Codex: 803.74 credits remaining".

### AC5: The layout returns when a measurement confirms the reset

- **Given** a promoted pool
- **When** a new provider measurement shows the exhausted windows have reset, usually back to 0%, and no line in the group is still at 100%
- **Then** the card, the collapsed card, and the menu bar return to the normal layout, with the pool back in its own row
- **And** the menu bar turns back from the provider glyph into the window ring
- **And** a reset of one window does not demote the pool while another window in the group is still at 100%, because usage is still blocked
- **And** a first reading after the reset above 0% still counts, because usage can resume before the next refresh
- **And** this rule applies only to a promoted pool; a provider that never switched to credits keeps today's ring behavior
- **And** a promoted pool whose balance stops decreasing stays promoted while the group is still exhausted
- **And** a reset time passing on the local clock does not change the layout on its own; the exhausted line shows "resetting…", the app's existing wording, until a measurement arrives.

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
  - the promoted headline with and without a forecast
  - the collapsed-card and menu-bar amount, with a tier for a currency pool and none for credits
  - VoiceOver text.

## Plan

1. [x] Add an optional `fallbackForLimitGroup` to `UsageLine`, defaulting to `nil`.
2. [x] Add a memory-only promotion tracker. It records each candidate pool's balance while its group is exhausted, and promotes the pool on the first decrease between consecutive accepted observations. Feed it from the existing accepted-result path.
3. [x] Add a pure App resolver that takes the lines and the tracker state, and returns either the normal layout or the promoted layout: the pool line, the exhausted lines, and the remaining rows. Keep it free of SwiftUI so `Tests/AppTests` can cover it.
4. [x] Make `QuotaStatusResolver.resolve(for:)` use that resolver, so the collapsed card and the menu bar follow the promoted pool.
5. [x] Render the promoted layout in `QuotaView` and `UsageLineRow`. Reuse the small detail-line style for exhausted windows. Name the pool in the headline with a labeled value format in all four languages; (core 12 AC15) removed the earlier one.
6. [x] Declare Codex credits as the candidate fallback for its window group in the Codex provider. (providers 18) adds the credits row with no limit group. This step adds only the declaration, so (providers 18) does not depend on this spec.
7. [ ] Run the focused tests and the repository validation gate. Manually check the promoted card at normal width, the collapsed card, the menu bar, and VoiceOver.

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

### Implementation findings

- `FallbackPoolTracker` keeps the last balance and the promotion of each declared pool, per provider. It reads only fresh, non-stale results, from the same path as the forecast history, and clears with it.
- `FallbackPoolLayout` splits the lines into the pool, the exhausted lines of its group, and the other lines. The pool row carries one detail line per exhausted limit, e.g. "5-hour window · Limit reached · resets in 2 hours".
- `QuotaStatusResolver.Status` gained `.credits(formattedAmount:)`: an amount without a tier. A promoted currency pool keeps `.balance`.
- The presentation treats the pool as the headline line (core 12 AC15). Its headline always names the pool, adds the pool's estimate when there is one, and reads "Using Credits" and each reached limit to VoiceOver first. The name-style key "Promoted pool value format" passes `bundle: .module`.
- The menu bar and the collapsed card take the promoted pool IDs from the view model; the menu-bar provider selection does not need them.
- A scripted fake `codex` on 2026-10-12 showed the promoted card with credits learning, the menu-bar amount "794,65", and the normal card at 0% after the reset. At the popover's 280 pt width, "Limit reached · resets in 4 Minuten" did not fit beside "5-hour window" and was cut before the reset time. A detail line now moves its value under its label when the two do not fit on one line; details that fit keep one line.
- A rebuild on 2026-10-12 after the Codex session had ended showed the normal layout with "100% · Limit reached" and credits at 744,30. The first read after a launch only sets the baseline (AC2), and the credits no longer fell, so the pool stayed in its row. The promoted layout needs a session that spends credits.

## Risks

- Promotion needs a decrease into or during exhaustion. The Codex capture shows one on the read that reaches the limit, so the card switches at once; a provider that spends the pool later keeps the exhausted layout until the first decrease.
- The first pool estimate after the switch averages over the recent horizon, which mostly holds the flat balance from before the switch. On 2026-10-12 it read "About 2W 4d", then "About 2d 5h", while credits fell about 210 per hour, about 4 hours of use. The promoted headline shows this estimate, so the proposed (core 12) fix that starts the rate at the first decrease matters most here.
- A top-up and spending inside one refresh interval can cancel out and delay promotion.
- If something else spends the pool while the limits are exhausted, the app promotes the pool even though the windows are what blocks the user.
- `BalanceThresholds` are in currency, so a credits pool shows no tier color until credits get thresholds of their own.
- In the ring menu-bar style, balance providers show the provider glyph and the amount, with no ring. A promoted provider looks the same while it uses credits. This is accepted; the ring returns after the reset (AC5).
- At the boundary the layout can flip between refreshes. Measurement-only promotion and demotion keep it tied to real data.

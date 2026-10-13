## Objective

When a provider's limit group runs out while its credit or money pool still has a balance, show that pool as the provider's main allowance and move the exhausted limits to a smaller place. Without a balance, the exhausted limits and their reset times stay in front.

## Context

- Status: partially implemented on `ferat/allowance-depletion-codex`, together with (providers 18). Plan steps 1–6 and 8 are implemented; the manual check in step 7 is open. Updated on 2026-10-12 with the Codex capture (providers 18). Later on 2026-10-12 the user changed the promotion rule (AC2): a balance above 0 promotes the pool without waiting for a decrease. The user approved the change on 2026-10-13, and Plan step 8 implements it.
- Builds on the line IDs, limit groups, and forecasts of (core 12). Codex is the first provider to use it (providers 18).
- (core 12 AC15) keeps each line's notice with its line: the headline speaks for one line, and a group line at 100% reads "Limit reached" in its row. While a pool is promoted, the pool is that line (AC3). (core 12 AC15) also removed the headline label, which the promoted headline needs again.
- Codex shows its credits in their own row after the windows (providers 18 AC4). When the windows reach 100%, the card still leads with "100% · Limit reached" while work continues on credits.
- Codex switches to credits on its own. On 2026-10-12 the five-hour window went from 98% to 100% between two reads, `rateLimitReachedType` became `"rate_limit_reached"`, and credits fell by 0.94 on the same read; the weekly window was at 66% (providers 18 Evidence). The next two reads fell by 2.52 and 4.57 credits. The Codex CLI also hides its window-limit warnings while the account has credits (providers 18 Context). The first rule waited for the pool to decrease. After a launch with the limit already reached and no session running, the card then kept "Limit reached" with 744,30 credits left. So a balance above 0 is enough.
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
- **And** the declaration only makes the pool a candidate; promotion also needs an exhausted group and a balance above 0 (AC2)
- **And** a provider without the declaration keeps today's layout
- **And** Core and App contain no branch keyed on a provider ID.

### AC2: Promotion follows the pool's balance

- **Given** a limit group with a declared fallback pool, and at least one line in the group reports 100% used
- **When** the displayed measurement shows the pool with a balance above 0, or unlimited
- **Then** the app promotes the pool; the provider only declares the candidate (AC1)
- **And** this holds from the first measurement after launch; the app does not wait for the balance to decrease
- **And** spending keeps the balance above 0 until the pool runs out, so a decrease needs no rule of its own
- **And** a pool at 0 or below, or with a balance the app cannot read, is not promoted: the card keeps the normal layout, with "Limit reached" and the reset countdown of each exhausted line
- **And** a top-up while the group is exhausted promotes the pool on the next measurement
- **And** a projected depletion (core 12 AC7) never promotes the pool
- **And** promotion depends only on the displayed measurement, so the app keeps no promotion state between refreshes.

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

### AC5: The layout returns when a measurement confirms the reset or the pool runs out

- **Given** a promoted pool
- **When** a new provider measurement shows the exhausted windows have reset, usually back to 0%, and no line in the group is still at 100%
- **Then** the card, the collapsed card, and the menu bar return to the normal layout, with the pool back in its own row
- **And** the menu bar turns back from the provider glyph into the window ring
- **And** a reset of one window does not demote the pool while another window in the group is still at 100%, because usage is still blocked
- **And** a first reading after the reset above 0% still counts, because usage can resume before the next refresh
- **And** a measurement that shows the pool at 0 or below returns the card to the normal layout while the group is still exhausted, because nothing is left to spend; the exhausted lines show "Limit reached" with their reset countdown
- **And** a provider without a declared pool, or with a pool at 0, keeps today's ring behavior
- **And** a promoted pool whose balance stops decreasing stays promoted while the group is still exhausted and the balance is above 0
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
  - promotion from the first exhausted measurement with a balance above 0, and with unlimited credits
  - no promotion at 0, below 0, with an unreadable balance, or without a declaration
  - partial exhaustion with a normal sibling row
  - a passed local reset without a new measurement
  - demotion after a reset measurement, including a first reading above 0%
  - demotion when the pool reaches 0 while the group is still exhausted
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
8. [x] Apply the balance rule (AC2, AC5). `FallbackPoolLayout` decides promotion from the displayed lines alone: a declared pool with a balance above 0, or unlimited, while a line of its group is at 100%. Remove `FallbackPoolTracker` and the promoted pool IDs that the view model passes to the status resolver, the collapsed card, and the menu bar. Update the tests for AC2, AC5, and AC8, then repeat the manual check in step 7.

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

- `FallbackPoolLayout` decides promotion from the displayed lines alone (AC2). It splits the lines into the pool, the exhausted lines of its group, and the other lines. Plan step 8 removed `FallbackPoolTracker`, which promoted a pool only after its balance fell. The pool row carries one detail line per exhausted limit, e.g. "5-hour window · Limit reached · resets in 2 hours".
- `QuotaStatusResolver.Status` gained `.credits(formattedAmount:)`: an amount without a tier. A promoted currency pool keeps `.balance`.
- The presentation treats the pool as the headline line (core 12 AC15). Its headline always names the pool, adds the pool's estimate when there is one, and reads "Using Credits" and each reached limit to VoiceOver first. The name-style key "Promoted pool value format" passes `bundle: .module`.
- The card, the forecast headline, the collapsed card, and the menu bar each build the layout from the same displayed quota, so they cannot disagree.
- A scripted fake `codex` on 2026-10-12 showed the promoted card with credits learning, the menu-bar amount "794,65", and the normal card at 0% after the reset. At the popover's 280 pt width, "Limit reached · resets in 4 Minuten" did not fit beside "5-hour window" and was cut before the reset time. A detail line now moves its value under its label when the two do not fit on one line; details that fit keep one line.
- A rebuild on 2026-10-12 after the Codex session had ended showed the normal layout with "100% · Limit reached" and credits at 744,30. The first read after a launch only sets the baseline (AC2), and the credits no longer fell, so the pool stayed in its row. Under the balance rule (AC2), this case promotes the pool.

## Risks

- Promotion no longer waits for the pool to be spent. If a provider does not spend its pool once the limits run out, the card shows the pool on top while the windows block the user. The provider should then drop the declaration (AC1). Codex sends `spendControlReached`; it stayed false in every capture (providers 18 Evidence), so its effect on credit use is unknown.
- The first pool estimate after the switch averaged over the flat balance from before the switch. On 2026-10-12 it read "About 2W 4d" while credits fell about 210 per hour. (core 12 AC16) now starts the rate at the first decrease; the credits-switch replay estimates about 3h 19m.
- `BalanceThresholds` are in currency, so a credits pool shows no tier color until credits get thresholds of their own.
- In the ring menu-bar style, balance providers show the provider glyph and the amount, with no ring. A promoted provider looks the same while it uses credits. This is accepted; the ring returns after the reset (AC5).
- At the boundary the layout can flip between refreshes. Measurement-only promotion and demotion keep it tied to real data.

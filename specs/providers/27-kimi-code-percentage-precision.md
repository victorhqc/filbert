## Objective

Show Kimi Code window percentages with two decimal places in the popover.

## Context

- Status: approved and implemented 2026-10-27, uncommitted. Builds on (providers 24).
- Kimi's ratio map sends `used_ratio` with four decimals, e.g. `0.4372` and `0.5531` in the fixtures. That is a percentage with two decimals. Filbert rounds it to a whole number, so 43.72% and 44.49% both read "44%".
- `Sources/Core/QuotaFormatting.swift` — `percentage(_:)` always uses `fractionLength(0)`. It gains a fraction-length parameter that defaults to 0.
- `Sources/Core/ProviderProtocol.swift` — `UsageLine` gains `percentageFractionLength`, default 0. A provider cannot set the precision today, because the App formats every line's percentage itself. The default leaves every other provider unchanged (core 01).
- `Sources/App/UsageLineRow.swift` — the standard row formats `line.percentage`. It follows the line's fraction length.
- `Sources/App/PacedUsageLineText.swift` — the paced row's "%@%% used" follows the line's fraction length. The monthly line can be paced (ui 22). The allowance texts ("About %@%%/day available", "%@%% available until reset") are estimates and keep their precision.
- `Sources/App/AllowanceForecastPresentation.swift` — `valueText(for:)` formats a line's own percentage. It follows the line's fraction length.
- `Sources/App/CompactProviderStatus.swift` and `Sources/App/MenuBarStatusIcon.swift` — the collapsed card and the menu bar stay whole numbers. Both have little width, and they show a status, not a measurement.
- `Sources/Providers/KimiCode/KimiCodeProvider+Mapping.swift` — sets the fraction length on its lines and headline, and changes the merge (AC3).
- The merge in (providers 24 AC3) takes the higher of two readings. Legacy counters are whole percentages (`limit` is always `"100"`). In `usages-monthly-plan.json` the legacy 5-hour reading is 44 and the ratio is 0.4372, so the legacy 44 wins and the decimals are lost. Two decimals alone would print "44.00%".
- In the three captures where the ratio reads 0 against an exhausted legacy counter (providers 24, Evidence), the readings are 100 points apart. Readings that agree are under 1 point apart.

### Live capture, 2026-10-27

The user's own Kimi Code subscription (new plan), API key on `api.kimi.ai`, 20 reads one minute apart from 09:57 to 10:16 UTC. Stored outside the repository.
- Every read had the same body shape: `limits[]` with the 5-hour window, `usages` with `limit_5h`, `limit_month_total`, and `limit_month_code`, and `booster_wallet`. There was no `usage`, no `limit_7d`, and no `goods_version`.
- 5-hour: legacy `used` `"8"` against `used_ratio` `0.0841`. Monthly: `used_ratio` `0.033`, equal in total and code.
- Ratios are JSON numbers with up to four decimals, and trailing zeros are dropped (`0.033` is 3.30%).
- The legacy counter rounds to the nearest whole percent: 8.41 reads 8 here, and 43.72 reads 44 in `usages-monthly-plan.json`. Agreeing readings are therefore at most 0.5 points apart.
- Usage did not move during the capture, so this capture does not show how a change reaches each block.
- `limit_5h.reset_time` flips between `:50` and `:51` across reads, while the legacy `resetTime` stays fixed with microseconds.
- `booster_wallet` holds a user ID and wallet IDs. The fixture replaces them.
- The first read, from an earlier attempt, returned `401` with `{"error":{"message":"Invalid Authentication","type":"invalid_authentication_error"}}`. This is the first `/usages` error body on record (providers 24 AC6). It does not change this spec.
- Today, Filbert shows this account as 8% and 3%. After this change it shows 8.41% and 3.30%. Here the ratio already wins under the old rule. The new rule matters when the counter rounds up, as in the 43.72 fixture.

## Acceptance Criteria

### AC1: Core formats a percentage at a given precision

- **Given** a percentage and a fraction length
- **When** `QuotaFormatting.percentage(_:fractionLength:)` formats it
- **Then** it shows exactly that many decimals in the display language's percent style, e.g. `43.72%` in English and `43,72 %` in German
- **And** the fraction length defaults to 0, so existing callers keep their output.

### AC2: A usage line carries its percentage precision

- **Given** a `UsageLine` built without `percentageFractionLength`
- **When** the App shows it
- **Then** its percentage reads as a whole number, as before
- **And** a line built with `percentageFractionLength: 2` shows two decimals in the standard row, in the paced row's "used" text, and in `valueText(for:)`
- **And** the collapsed card and the menu bar show the percentage as a whole number for every line.

### AC3: The finer reading wins when two readings agree

- **Given** a window with a legacy reading and a ratio reading
- **When** the two are less than 1 percentage point apart
- **Then** the ratio reading wins, with its reset date, or the legacy reset date when the ratio has none
- **And** when they are 1 point or more apart, the higher reading wins, as in (providers 24 AC3)
- **And** `usages-monthly-plan.json` gives a 5-hour reading of 43.72, `usages-live-new-plan.json` gives 8.41 and a monthly 3.30, and `usages-api-key-contradiction.json` still gives 100.

### AC4: Kimi Code lines and headline use two decimals

- **Given** a mapped Kimi Code response
- **When** the provider builds its lines
- **Then** the 5-hour, weekly, and monthly lines set `percentageFractionLength` to 2
- **And** the headline reads `"<percentage> · <countdown>"` with two decimals, e.g. `43.72% · 2h 14m`, or the percentage alone without a reset date
- **And** whole legacy readings print with two decimals too, e.g. `100.00%`, so the rows line up.

### AC5: Activity metrics keep full precision

- **Given** a mapped response
- **When** the provider builds its activity observation
- **Then** each metric holds the merged percentage unrounded, as before.

### AC6: The package builds clean

- **Given** a fresh checkout after the change
- **When** the validation gate runs
- **Then** format, lint, both builds, and `swift test` pass with zero warnings.

## Plan

1. [x] Core: add `fractionLength: Int = 0` to `QuotaFormatting.percentage`, and `percentageFractionLength: Int = 0` to `UsageLine` and its initializer. Tests: 0 and 2 decimals in English and German, and the default. Finding: a default argument broke `usedPercent.map(QuotaFormatting.percentage)` in the Codex provider, so the one-argument function stays and a `percentage(_:fractionLength:)` overload is added instead. No other provider changes.
2. [x] App: pass the line's fraction length in `StandardUsageLineRow`, `PacedUsageLineText.used`, and `AllowanceForecastPresentation.valueText(for:)`. Leave `CompactProviderStatus` and `MenuBarStatusIcon` alone. Tests: the paced "used" text and `valueText` at 0 and 2. Findings: `BudgetPace` carries the line's fraction length to `PacedUsageLineText`. `FallbackPoolLayout.poolLine()` copies a line, so it copies the fraction length too. `valueText` is private, so its test goes through the limit-reached headline.
3. [x] Kimi Code: the agreement rule in `merge`, `percentageFractionLength: 2` on every line, and the headline with two decimals. Add `usages-live-new-plan.json`: one body from the 2026-10-27 capture, verbatim except that the IDs in `booster_wallet` become placeholders. Tests: the 43.72 fixture, the live fixture (8.41 and 3.30), the 100-versus-0 fixtures, a pair exactly 1 point apart (higher wins), a pair 0.99 apart (ratio wins), and the headline text.
4. [x] Update (providers 24 AC3) to point at this spec's AC3.

No new strings. "%@%% used" and the percent style already take any number.

## Risks

- **Smart refresh sees smaller changes.** The 5-hour metric now moves in hundredths when the ratio wins, where it used to move in whole points. A change of 0.03 points now counts as activity, so Smart refresh may wake sooner. This matches what Kimi reports, and it is not a false signal.
- **A rounded-up legacy counter hides a ratio bug under 1 point.** If the ratio wrongly reads 99.5 while the counter reads 100, the ratio wins and the line shows 99.50%. Kimi still blocks at 100. No capture shows this case. The counter rounds to nearest, so 0.5 would be a tight enough threshold. The spec keeps 1 point as a margin, because one rounding sample in each direction is thin evidence.
- **Unseen change timing.** Usage stayed flat during the capture. If the ratio map lags the counter after a request, a brief disagreement of 1 point or more lets the higher reading win until the two converge.
- **Wider text.** "100.00%" is three characters wider than "100%". The row has room, and the menu bar and collapsed card are unchanged.
- **Weekly line.** It is included for consistency. On legacy plans it usually comes from a whole-number counter and reads e.g. `29.00%`.

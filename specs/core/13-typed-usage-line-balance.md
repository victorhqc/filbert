## Objective

Give `UsageLine` a typed balance, so the App formats, shows, and ranks a balance from its declared unit, not from which optional fields are set.

## Context

- Status: draft for review. (providers 18) needs it for the Codex credits row. (providers 19) and (ui 28) build on it.
- `Sources/Core/ProviderProtocol.swift` — `UsageLine` has `used`, `total`, `percentage`, and `unit`. The App reads a line without a percentage as a currency balance: `total` is the amount and `unit` is a currency code (core 01, ui 08). No other shape can show a plain number.
- `Sources/App/FilteredBalanceLines.swift` — hides each line without a percentage unless `total > 0`. When two such amounts are equal, it keeps only the first line (ui 08 AC1). It compares amounts across currencies. A line with only details, e.g. Codex credits without windows, never renders.
- `Sources/App/QuotaStatusResolver.swift` — `amountText(for:)` formats `total` as currency. `resolve(for:)` reads the first positive `total` without a percentage as the balance status. The collapsed card, the menu bar, and VoiceOver read this status.
- `Sources/App/QuotaView.swift` — `headlineBalanceColor(for:)` colors the headline dot from the first `total` without a percentage (ui 08 AC3).
- `Sources/App/MenuBarProviderPresentation.swift` — the VoiceOver label formats the balance again with `unit: nil`. A CNY balance is read in the currency of the user's locale.
- `Sources/App/UsageLineRow.swift` — shows a percentage, or else `amountText`, in the trailing slot of a row.
- `Sources/App/AllowanceForecastPresentation.swift` — `valueText(for:)` uses `amountText` for a composed headline (core 12 AC9).
- `Sources/Providers/DeepSeek/DeepSeekProvider.swift` — sends the total, granted, and topped-up balances as `total` with a currency `unit` (providers 04). The headline finds the total line by its label.
- `Sources/Providers/Cursor/CursorProvider.swift` — the "Bonus credits" line puts `bonusSpend` in `total`. It is an amount spent, not a balance (providers 07).
- (core 12) rejects guesses from display rows and requires typed descriptors. This spec applies the same rule to the rows.

## Acceptance Criteria

### AC1: A line declares its balance

- **Given** a provider reports an amount that remains, e.g. a currency balance or a credit pool
- **When** it builds the `UsageLine`
- **Then** it sets an optional `balance` with an amount and a unit
- **And** the amount is finite, as a `Decimal`, or unlimited
- **And** the unit is a currency with its ISO 4217 code, or credits
- **And** `balance` defaults to `nil`, so a provider without balances needs no change
- **And** a line with a balance sets no `used`, `total`, or `percentage`; a debug assertion catches a line that sets both
- **And** `total` only means the limit of `used`, and `unit` only means the currency of `used` and `total`.

### AC2: The App formats each unit in one place

- **Given** a line with a balance
- **When** the App shows its amount
- **Then** a currency amount uses the localized currency format with the line's code, as today
- **And** a credits amount uses two localized decimals with grouping and no symbol, e.g. "1,159.57" in English and "1.159,57" in German
- **And** an unlimited amount shows "Unlimited"
- **And** the row shows the amount in its trailing slot and draws no bar, as balance rows do today
- **And** a line without a percentage and without a balance, but with `used` and a currency `unit`, shows `used` in that currency; this is an amount spent without a limit
- **And** a composed forecast headline (core 12 AC9) uses the same formatting.

### AC3: Only currency balances drive the balance status

- **Given** a quota without a percentage line
- **When** `QuotaStatusResolver` resolves its status
- **Then** the first line with a positive, finite currency balance gives the balance status, with its amount and formatted text
- **And** a credits balance, an unlimited balance, and an amount spent never give a status, because `BalanceThresholds` are tuned for currency; only (ui 28) promotion can change this
- **And** a percentage line still wins over every balance, as today
- **And** the headline dot uses the first finite currency balance (ui 08 AC3)
- **And** the menu-bar VoiceOver label uses the formatted amount with its currency, e.g. "DeepSeek: CN¥2.97 remaining".

### AC4: Providers decide which lines exist

- **Given** a quota with balance lines
- **When** the popover renders the card
- **Then** it renders every line that the provider sends, in order
- **And** the App no longer hides a line because of its amount, and no longer removes equal amounts
- **And** a line with nothing to show stays hidden, as today: it has no percentage, no amount, and no details, e.g. a window that reports no percentage
- **And** the rules of (ui 08 AC1) move into the DeepSeek provider (AC5).

### AC5: DeepSeek keeps its card

- **Given** a DeepSeek balance response
- **When** the provider maps it
- **Then** the total, granted, and topped-up balances are currency balances, parsed as `Decimal` with the POSIX locale, like its activity metrics
- **And** the provider omits a balance line that is zero, negative, or does not parse
- **And** within one currency, when two remaining amounts are equal, the provider keeps only the total balance of that currency (ui 08 AC1)
- **And** it compares amounts only within one currency; the App compares them across currencies today
- **And** the headline reads the first total balance from the response, not from the lines, so a zero balance still shows "$0.00 left" (ui 08 AC1)
- **And** for one currency, the card, the collapsed card, and the menu bar look the same as before.

### AC6: Cursor's bonus line is an amount spent

- **Given** Cursor reports a positive `bonusSpend`
- **When** the provider maps it
- **Then** the "Bonus credits" line sets `used` in USD and no `total` (providers 07)
- **And** the row still shows the amount, e.g. "$20.00"
- **And** the line never gives a balance status (AC3).

### AC7: Tests cover each shape

- **Given** the change is implemented
- **When** the tests run
- **Then** they cover:
  - `balance` defaults to `nil`
  - currency, credits, and unlimited formatting, in English and German
  - the row value for a percentage, a balance, and an amount spent
  - the status for a currency balance, a credits balance, an unlimited balance, a zero balance, an amount spent, and a percentage line next to a balance
  - the headline dot, and the menu-bar VoiceOver label with a CNY balance
  - a card that renders every line, including a line with only details
  - DeepSeek: zero, negative, and unparseable balances, equal amounts in one currency and in two currencies, the headline with a zero total, and an unavailable account
  - Cursor: the bonus line as an amount spent.

## Plan

1. [x] Add `UsageBalance` and `UsageLine.balance` to Core:

   ```swift
   public struct UsageBalance: Equatable, Sendable {
       public enum Amount: Equatable, Sendable {
           case finite(Decimal)
           case unlimited
       }
       public enum Unit: Equatable, Sendable {
           case currency(String) // ISO 4217 code
           case credits
       }
       public let amount: Amount
       public let unit: Unit
   }
   ```

2. [x] In the App, add one amount formatter. Use it in the row, in `valueText(for:)`, and in the status. Change `.balance(used:total:formattedAmount:)` to `.balance(amount:formattedAmount:)`, because no view reads `used`. Read the headline dot and the menu-bar label from the new status. Replace `FilteredBalanceLines.swift` with the rule for lines with nothing to show (AC4).
3. [x] Migrate DeepSeek: balances, the choice of lines, and the headline from the response.
4. [x] Migrate the Cursor bonus line to `used`.
5. [x] Add the tests from (AC7). Run the validation gate.
6. [ ] Manually check the DeepSeek and Cursor cards, the collapsed card, the menu bar, and VoiceOver.

### Implementation findings

- `FilteredBalanceLines.swift` also hid every window line without a percentage, because such a line has no `total`. Without a rule, those lines would render with only a label. `visibleUsageLines` keeps them hidden, so the card hides only a line with nothing to show (AC4).
- A Codex response without windows sends credits as a line with only details. The old filter hid it. It now renders, until (providers 18) gives it a balance.
- The DeepSeek USD fixture has a zero granted balance and equal total and topped-up balances. The provider now sends one line, which is the line the App showed before.

## Risks

- Every DeepSeek user sees a regression in the balance card. The tests in (AC5) pin the card for one currency.
- With two currencies, DeepSeek can show more rows than today, because equal amounts in different currencies are no longer merged.
- A Cursor on-demand line without `used` showed its limit as a balance. It now has nothing to show, so it is hidden (AC4).
- A Cursor bonus line gave the balance status when no percentage line was present. It no longer does.
- The Cursor headline showed a tier dot from the bonus spend. The dot is gone, because an amount spent has no tier.
- (providers 19 AC3) moves the DeepSeek headline lookup from the label to a line ID. After (AC5), the headline reads the response, so (providers 19) only adds the line IDs.

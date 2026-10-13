## Objective

Opt DeepSeek's per-currency total balance into balance forecasting (core 12).

## Context

- Status: implemented and on `main` (#79) (Evidence below). Depends on (core 12) and (core 13).
- `Sources/Providers/DeepSeek/DeepSeekProvider.swift` — emits `total-balance-<currency>` metrics plus typed balance lines (core 13). Zero, negative, and repeated amounts get no line. Before this spec, lines had no IDs and the quota named no headline line, so the app never replaced the provider's headline.
- Charges deduct granted credits first, then topped-up credits. Only `total_balance` reflects net consumption (providers 04).
- Each refresh is a live HTTPS request with no source timestamp. Before this spec, freshness was `.unknown`.
- Peak-hours pricing changes the cost per token (providers 08), so the rate can shift at peak boundaries.
- `Tests/DeepSeekProviderTests/` — mapping and fixture tests.

## Acceptance Criteria

### AC1: Total balance is the only forecast pool

- **Given** a balance response with one or more currencies
- **When** the provider maps it
- **Then** each currency's total balance carries a balance descriptor in that currency
- **And** granted and topped-up balances carry no descriptor and show no forecast
- **And** currencies are never combined (core 12 AC8).

### AC2: Timing and resolution are declared

- **Given** a successful live response
- **When** the provider maps it
- **Then** the observation is `.fresh` with approximate receipt timing
- **And** the resolution is the verified smallest change that `total_balance` can show, in the currency's major unit, e.g. 0.01 for a balance with two decimals (core 12 AC1)
- **And** recorded evidence shows how soon a charge appears in `total_balance`; a delay longer than a few minutes is documented as a limitation.

### AC3: Lines have stable IDs

- **Given** the provider builds balance lines
- **When** it assigns IDs
- **Then** each line has a stable ID per currency and component
- **And** the headline finds its line by ID, not by localized label
- **And** the headline line is the first currency's total balance, matching today's headline, so an estimate reads like "2,97 CN¥ · About 3 days of use remaining".

### AC4: Balance changes that are not spend are handled conservatively

- **Given** a top-up or new grant raises the total balance
- **When** Core receives it
- **Then** it re-baselines (core 12 AC3)
- **And** forecast text describes observed net depletion, not verified spend
- **And** a response with `is_available == false` and a positive balance carries no descriptor. Forecasting resumes only from the next available response, as a new baseline.

### AC5: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover steady depletion, top-ups, grants, multiple currencies, unavailable accounts, unparseable balances, and the ID-based headline lookup.

## Plan

1. [x] Record how quickly a known charge appears in `total_balance` and confirm each currency's minor unit. The API reference shows two decimals in its example but states no precision or update delay. A local script outside the repository polls `/user/balance` every 30 seconds and keeps only status codes and balance strings. Its `charge` command sends one chat completion and records only its token usage and timing. It reads the key from a dedicated Keychain item on every request. Done on 2026-10-13: a charge appears about three minutes after its request, in one step, and USD balances always have two decimals. CNY relies on the reference example, because the account has no CNY balance.
2. [x] Add line IDs and switch the headline lookup to IDs. Lines are `total-balance-<currency>`, `granted-balance-<currency>`, and `topped-up-balance-<currency>`, and the headline line is the first currency's total.
3. [x] Add balance descriptors to total-balance metrics only. Each total carries a balance descriptor in its currency, with resolution 0.01 and receipt timing, and the observation is `.fresh`. An unavailable account, or a currency that appears twice, carries no descriptor.
4. [x] Add the fixtures and tests from AC5. Mapping tests cover the descriptor, multiple currencies, unavailable accounts, unparseable totals, a repeated currency, steady depletion, top-ups, grants, and the ID-based headline lookup. `deepseek-capture-single-charge.json` replays the captured charge. It shows two decimals throughout and the drop about three minutes after the request. The balance shows nothing while it is flat, "learning" from the drop, an estimate from 10 minutes after the read before the drop, and quiet 15 minutes after the drop (core 12).

### Evidence

**Capture through the user's proxy, one read every 30 seconds, from 2026-10-13 09:08 UTC:**

- The account has one balance, in USD. Every read sends all three amounts with exactly two decimals, `0.00` included.
- The `charge` command sent one `deepseek-v4-pro` request with 60,097 uncached input tokens and 16 output tokens. It finished at 09:10:05. The total read 12.93 through 09:13:01 and 12.85 from 09:13:31. The charge appeared between 2 min 56 s and 3 min 26 s after the request finished, as one step of 0.08.

## Risks

- Granted credits that expire reduce the total exactly like spend. The forecast cannot tell them apart.
- A peak-hours boundary changes the rate immediately. The recent segment needs time to reflect it.
- A top-up and spend within one interval can cancel out and hide consumption.
- A charge reaches the balance about three minutes after its request. Receipt timing places it at the read that shows it, so the forecast trails real use by about three minutes. That is within the few minutes (AC2) allows.

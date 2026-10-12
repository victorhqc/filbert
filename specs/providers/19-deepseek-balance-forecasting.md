## Objective

Opt DeepSeek's per-currency total balance into balance forecasting (core 12).

## Context

- Status: draft for review. Depends on (core 12).
- `Sources/Providers/DeepSeek/DeepSeekProvider.swift` — emits `total-balance-<currency>` metrics plus granted and topped-up lines. The headline finds its line by matching the localized label.
- Charges deduct granted credits first, then topped-up credits. Only `total_balance` reflects net consumption (providers 04).
- Each refresh is a live HTTPS request with no source timestamp. Freshness is `.unknown` today.
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

1. Record how quickly a known charge appears in `total_balance` and confirm each currency's minor unit.
2. Add line IDs and switch the headline lookup to IDs.
3. Add balance descriptors to total-balance metrics only.
4. Add the fixtures and tests from AC5.

## Risks

- Granted credits that expire reduce the total exactly like spend. The forecast cannot tell them apart.
- A peak-hours boundary changes the rate immediately. The recent segment needs time to reflect it.
- A top-up and spend within one interval can cancel out and hide consumption.

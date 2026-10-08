## Objective

Opt Codex usage windows and finite credits into allowance forecasting (core 12), with credits on their own allowance row.

## Context

- Status: draft for review. Depends on (core 12).
- `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` — maps the `primary-window-usage`, `secondary-window-usage`, and `credits` metrics. Sets `lastUpdated` to `Date()`. Attaches credits as a detail of the first window row (providers 05 AC7).
- `Sources/Providers/OpenAICodex/CodexAppServerClient.swift` — `account/rateLimits/read` returns `usedPercent`, `resetsAt`, `windowDurationMins`, and `credits { balance, unlimited }` (providers 05).
- Activity freshness is `.unknown` today. Open question: does the read return live server state, or a snapshot cached from the last Codex turn?
- Credits are consumed only after the five-hour or weekly window runs out. They form a separate pool.
- `Tests/OpenAICodexProviderTests/` — mapping and fixture tests.

## Acceptance Criteria

### AC1: Freshness is verified before opting in

- **Given** the `account/rateLimits/read` response
- **When** its freshness is verified
- **Then** recorded evidence shows whether the read reflects live server state or a cached snapshot
- **And** if live, observations are `.fresh` with approximate receipt timing
- **And** if the read can return a cached snapshot without a source timestamp, windows carry no descriptor and show no forecast UI
- **And** the evidence is stored in provider fixtures and summarized in this spec.

### AC2: Window semantics are verified before opting in

- **Given** a primary or secondary window
- **When** the provider declares it a fixed period
- **Then** recorded evidence shows that `resetsAt` stays stable within one period
- **And** `windowDurationMins` never establishes fixed-period semantics on its own (core 12 AC2)
- **And** a verified window carries a fixed-period descriptor with limit 100, unit percentage points, and the verified resolution
- **And** its `UsageLine` ID equals its metric ID
- **And** the title line is the shortest window, matching today's title; the credits row is never the title line
- **And** the primary and secondary windows share one limit group (core 12 AC8).

### AC3: Credits are their own allowance row

- **Given** the snapshot reports credits
- **When** the provider maps it
- **Then** credits become a separate `UsageLine` with ID `credits`, no longer a detail of the first window row
- **And** finite credits carry a balance descriptor in the credits unit, with the verified upstream granularity as resolution
- **And** unknown granularity produces no descriptor
- **And** the row displays the balance with two localized decimals, e.g. "1,159.57", not the raw upstream string "1159.5692275000"; the metric keeps the unrounded value
- **And** unlimited credits show "Unlimited credits" and carry no descriptor
- **And** absent credit data produces no credits row, as today (providers 05 AC7)
- **And** the credit forecast reflects only observed credit depletion; while windows remain available, credits stay flat and the row shows no forecast text
- **And** no text predicts when consumption will switch from windows to credits (core 12 AC8)
- **And** a credit purchase is a balance increase and re-baselines (core 12 AC3)
- **And** the credits row is declared the candidate fallback pool for the window limit group; the app promotes it only after observing credits decrease while a window is exhausted (ui 28).

### AC4: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover live and cached freshness outcomes, stable resets, period rollover, finite, unlimited, and absent credits, a credit purchase, unparseable balances, and the separate credits row.

## Plan

1. Compare `account/rateLimits/read` results during a Codex session, after it ends, and after usage from another machine. Record whether values change without a local turn.
2. Record `resetsAt` stability and credit balance granularity.
3. Move credits to their own row. Add descriptors and line IDs only where the evidence supports them.
4. Add the fixtures and tests from AC4.

## Risks

- Moving credits to their own row is a visible UI change for Codex users.
- If the read returns cached snapshots, Codex windows may never be forecastable. Do not fall back to receipt time for cached data.
- Credits may stay flat for days, so the credits row usually shows no forecast text. A forecast appears only after the windows run out and credits start to move.

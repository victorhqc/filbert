## Objective

Opt Claude Code's five-hour and weekly windows into allowance forecasting (core 12).

## Context

- Status: draft for review. Depends on (core 12). (core 12) merges only together with this spec and (providers 18, providers 19, providers 20).
- `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift` — maps the `five-hour-usage` and `weekly-usage` metrics. A window's `written_at` falls back to the cache `written_at`. Freshness expires after one hour (providers 02, providers 06).
- `Sources/Providers/ClaudeCode/StatuslineCacheStore.swift` — has two writers: the statusline helper during Claude Code sessions (providers 02) and the proactive `/usage` refresh (providers 03, providers 15, providers 16).
- `percent` is an integer in the usage report (providers 15). The resolution is 1 percentage point unless verification shows finer statusline values.
- The statusline helper rewrites the cache only while Claude Code renders its statusline. Idle reads repeat the same `written_at`.
- `Tests/ClaudeCodeProviderTests/` — mapping and fixture tests.

## Acceptance Criteria

### AC1: Window semantics are verified before opting in

- **Given** a five-hour or weekly window
- **When** the provider declares it a fixed period
- **Then** recorded evidence shows that `resets_at` stays stable within one period, apart from sub-second jitter, and that the percentage only rises until reset
- **And** the evidence covers both writers: the statusline and `/usage`
- **And** a window whose `resets_at` slides with usage stays unsupported and carries no descriptor
- **And** the evidence is stored in provider fixtures and summarized in this spec.

### AC2: Windows map to typed descriptors

- **Given** a verified window with a usable percentage and `resets_at`
- **When** the provider maps the cache
- **Then** the metric carries a fixed-period descriptor with limit 100, the window's reset timestamp, unit percentage points, and the verified resolution
- **And** the timing is the window's `written_at`, or the cache `written_at` when the window has none, never `Date()`
- **And** the `UsageLine` ID equals the metric ID
- **And** the headline line is the five-hour window, or the weekly window when the five-hour window is absent, matching today's headline
- **And** both windows share one limit group, because either one blocks usage when it runs out (core 12 AC8)
- **And** a window without `resets_at` carries no descriptor.

### AC3: Idle cache reads pause rather than read as quiet

- **Given** Claude Code is idle and no proactive refresh rewrites the cache
- **When** the app reads the same cache again
- **Then** the read is a duplicate and adds no sample (core 12 AC4)
- **And** the forecast pauses once the maximum age passes; this is expected, not a defect
- **And** a proactive refresh that writes a new reading is a genuine observation, even when values are unchanged, so quiet can be detected
- **And** when only proactive refreshes write the cache, and two consecutive writes are more than the maximum gap apart, the row shows "Updates too far apart to estimate" (core 12 AC9); this is expected, because the source data changes that slowly
- **And** the next statusline writes during a session are close together again, so the row returns to learning from a new baseline
- **And** windows older than the one-hour freshness limit are excluded, as today.

### AC4: No new provider work

- **Given** forecasting is enabled for Claude Code
- **When** refreshes run
- **Then** the provider spawns no extra `/usage` process, reads no credentials, and changes no proactive refresh behavior (core 12 AC10).

### AC5: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover stable resets, sub-second reset jitter, period rollover, duplicate reads, per-window and cache-wide timestamps, a missing `resets_at`, stale windows, and both cache writers.

## Plan

1. Capture statusline and `/usage` cache samples across one five-hour period and one weekly reset. Record whether `resets_at` is stable and whether `used_percentage` carries fractions.
2. Add descriptors and line IDs in the provider mapping. Keep all Claude Code interpretation inside the module.
3. Add the fixtures and tests from AC5.

## Risks

- `claude /login` can switch accounts without a visible scope change. Same-shaped readings cannot be told apart; the forecast may briefly span two accounts until a reset or correction re-baselines.
- The five-hour window starts with the first message. Before first use, `resets_at` may be absent, so no forecast appears.
- The statusline may lag real consumption by one render, which can create an apparent burst.

## Objective

Opt Claude Code's five-hour and weekly windows into allowance forecasting (core 12).

## Context

- Status: draft for review. The evidence in Plan step 1 is recorded. Depends on (core 12). (core 12) merges only together with this spec and (providers 18, providers 19, providers 20).
- `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift` — maps the `five-hour-usage` and `weekly-usage` metrics. A window's `written_at` falls back to the cache `written_at`. Freshness expires after one hour (providers 02, providers 06).
- `Sources/Providers/ClaudeCode/StatuslineCacheStore.swift` — has two writers: the statusline helper during Claude Code sessions (providers 02) and the proactive `/usage` refresh (providers 03, providers 15, providers 16).
- `Sources/ClaudeCodeStatuslineHelper/main.swift` — replaces the whole cache file on each statusline render. It does not merge with the `/usage` values. Only the `/usage` writer stamps a `written_at` on each window.
- Both writers report whole percentages and `resets_at` in whole minutes. The resolution is 1 percentage point (Evidence below).
- The statusline helper rewrites the cache only while Claude Code renders its statusline in a terminal. Clients that use Claude Code through the Agent Client Protocol (ACP), e.g. Zed, never run the statusline. For them, `/usage` is the only writer. Idle reads repeat the same `written_at`.
- `Tests/ClaudeCodeProviderTests/` — mapping and fixture tests.

## Acceptance Criteria

### AC1: Window semantics are verified before opting in

- **Given** a five-hour or weekly window
- **When** the provider declares it a fixed period
- **Then** recorded evidence shows that `resets_at` stays within the reset tolerance of (core 12) during one period, and that the percentage of each writer only rises until reset
- **And** the evidence covers both writers: the statusline and `/usage`
- **And** a window whose `resets_at` slides with usage stays unsupported and carries no descriptor
- **And** the evidence is stored in provider fixtures and summarized in this spec.

### AC2: Windows map to typed descriptors

- **Given** a verified window with a usable percentage and `resets_at`
- **When** the provider maps the cache
- **Then** the metric carries a fixed-period descriptor with limit 100, the window's reset timestamp, unit percentage points, and resolution 1
- **And** the timing is the window's `written_at`, or the cache `written_at` when the window has none, never `Date()`
- **And** the `UsageLine` ID equals the metric ID
- **And** the headline line is the five-hour window, or the weekly window when the five-hour window is absent, matching today's headline
- **And** both windows share one limit group, because either one blocks usage when it runs out (core 12 AC8)
- **And** a window without `resets_at` carries no descriptor.

### AC3: Writers that disagree never look like a decrease

- **Given** the statusline and `/usage` both write the cache during one period
- **When** the statusline reports one point less than `/usage`
- **Then** the provider reports the highest percentage it saw for that window in the current period
- **And** the provider keeps that value in memory per window, with the first `resets_at` of the period
- **And** a `resets_at` within the reset tolerance of (core 12) belongs to the same period; a larger difference, or a window without `resets_at`, starts a new period with the current value
- **And** the provider reads the tolerance from Core; it does not repeat the number
- **And** the displayed percentage, the activity metric, and the forecast use the same value (core 12 AC1)
- **And** the displayed percentage no longer alternates between the two writers
- **And** the memory clears on app relaunch; it is never written to disk
- **And** a percentage drop inside one period is never reported; only a new period lowers the value.

### AC4: Idle cache reads pause rather than read as quiet

- **Given** Claude Code is idle and no proactive refresh rewrites the cache
- **When** the app reads the same cache again
- **Then** the read is a duplicate and adds no sample (core 12 AC4)
- **And** the forecast pauses once the maximum age passes; this is expected, not a defect
- **And** a proactive refresh that writes a new reading is a genuine observation, even when values are unchanged, so quiet can be detected
- **And** when only proactive refreshes write the cache, and two consecutive writes are more than the maximum gap apart, the row shows "Updates too far apart to estimate" (core 12 AC9); this is expected, because the source data changes that slowly
- **And** the next statusline writes during a session are close together again, so the row returns to learning from a new baseline
- **And** a statusline write without windows, e.g. before the first API response of a session, has no metrics; the history pauses until the next write (core 12 AC4)
- **And** windows older than the one-hour freshness limit are excluded, as today.

### AC5: No new provider work

- **Given** forecasting is enabled for Claude Code
- **When** refreshes run
- **Then** the provider spawns no extra `/usage` process, reads no credentials, and changes no proactive refresh behavior (core 12 AC10)
- **And** the statusline helper does not change.

### AC6: Fixtures cover real refresh patterns

- **Given** the mapping is implemented
- **When** provider tests run
- **Then** they cover:
  - stable resets, and the one-minute `resets_at` flip of `/usage`
  - a five-hour rollover, with a write without `resets_at` before the new period
  - a weekly rollover, with `resets_at` seven days later
  - duplicate reads
  - per-window and cache-wide timestamps
  - a missing `resets_at`, and stale windows
  - writer switches where the statusline is one point lower, in both directions
  - a statusline write without windows
  - a replay of the two captures in Evidence, which produces no correction and no re-baseline inside a period.

## Plan

1. [x] Capture statusline and `/usage` cache samples across one five-hour period and one weekly reset. Record whether `resets_at` is stable and whether `used_percentage` carries fractions.
2. [ ] Add the per-window highest-value memory from (AC3) to the provider. Keep it in the Claude Code module. `AllowanceForecastPolicy` is internal to Core, so Core adds one public, generic question: "are these two reset timestamps in the same period?", with its reset tolerance. No provider ID or Claude Code concept goes into Core.
3. [ ] Add descriptors, line IDs, the limit group, and the headline line ID in the provider mapping. Keep all Claude Code interpretation inside the module.
4. [ ] Convert the captures into fixture traces with only timestamps, percentages, and reset times. Add the fixtures and tests from (AC6).
5. [ ] Manually inspect the popover and VoiceOver for the states in (core 12) Plan step 9 with real Claude Code data.

### Evidence

Two captures copied each change of `~/.cache/filbert/claude-code.json` on 2026-10-09, with Filbert v0.17.1.

**Capture 1, Claude Code through Zed (ACP), 09:39–14:46, 229 writes:**

- All writes came from `/usage`. The statusline never ran.
- Percentages were whole numbers. `resets_at` values were whole minutes.
- `resets_at` flipped between two neighboring minutes on almost every write: 14:39:00 and 14:40:00 for the five-hour window, 12:59:00 and 13:00:00 for the weekly window. The spread was always 60 seconds.
- Percentages only rose inside a period. The only decreases were the 2 resets.
- Weekly reset at 13:00:49: 15% to 0%, and `resets_at` moved from 2026-10-09 13:00 to 2026-10-16 13:00.
- Five-hour reset at 14:41:23: 26% to 0% with no `resets_at`. At 14:46:25 a new period showed `resets_at` 19:40. Before the first use of the day, the window also had no `resets_at`.
- The time between writes was 47 seconds (median) and 16 minutes (maximum).

**Capture 2, Claude Code in a terminal, 14:56–16:13, 332 writes:**

- 294 statusline writes (median 2.8 seconds apart), 37 `/usage` writes, and 1 write without windows.
- The statusline had whole percentages and a steady `resets_at` of 19:40:00 and 13:00:00 on all writes.
- The statusline percentage was 1 point less than the `/usage` percentage for the same window. Examples: 3 and 4, and 6 and 7, within seconds. The weekly window showed 2 on the statusline and 3 on `/usage` from 15:14 to 16:12.
- Each switch from `/usage` to the statusline was a decrease: 21 decreases in 75 minutes (10 five-hour, 11 weekly). Without (AC3), each decrease is a correction under (core 12 AC3). The history would then restart every 3 minutes, and no estimate could form.
- The write without windows was `{"written_at":…}` at 14:58:20, before the first API response of the session.

## Risks

- `claude /login` can switch accounts without a visible scope change. Same-shaped readings cannot be told apart. The forecast can span two accounts until a reset re-baselines.
- The five-hour window starts with the first message. Before first use, and right after a reset, `resets_at` is absent, so no forecast appears.
- The statusline lags `/usage` by 1 point, or by one API response. The highest-value memory hides the lag in the value. But a statusline write restates the last value with a new timestamp, so a long statusline-only stretch can look like no consumption.
- The card shows the higher writer's value. It can be 1 point above the terminal statusline of Claude Code.
- The highest-value memory hides a real correction inside one period. The evidence shows no such correction.
- After a relaunch, the memory is empty. If the first read is the lower statusline value, the next `/usage` write raises it by 1 point. That is an increase, not a correction.

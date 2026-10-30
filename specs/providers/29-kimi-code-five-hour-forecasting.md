## Objective

Decide from a live capture whether Kimi Code's five-hour window is a fixed block or a sliding window, and opt it into allowance forecasting (core 12) only if it is a fixed block.

## Context

- Status: implemented and on `main` (#106). The manual check in Plan step 6 is open. The capture is done, and the verdict is a fixed block (Evidence). Builds on (core 12) only. It lands before (providers 28), which adds the weekly and monthly descriptors and needs the calendar-month rule from (ui 39). A 5-hour period needs neither.
- Why it matters: a sliding window drops old usage without a reset and moves its reset with each use. Core reads each drop as a correction and each move as a new period (core 12 AC3), and a straight-line forecast ignores the usage that expires. So a sliding window cannot carry a descriptor (core 12 AC2).
- Evidence before the capture was inconclusive:
  - Kimi's docs call the window "rolling" (providers 24, Evidence). A label alone does not decide (core 12 AC2).
  - Claude Code and Codex also say "rolling". Their captures showed fixed blocks that start at the first message and reset exactly 5 hours later (providers 17, providers 18).
  - In the capture of 2026-10-27 (providers 27, Live capture), usage did not move. `limit_5h.reset_time` flipped by 60 seconds, the same jitter as Claude Code. The legacy `resetTime` stayed fixed to the microsecond for 19 minutes.
- Capture tool: `~/filbert-captures/scripts/kimi_five_hour_capture.py`, outside the repository. It reads `/coding/v1/usages` once a minute and writes JSONL to `~/filbert-captures/kimi-five-hour/`. Each line has the receipt time, the ratio, both reset fields, and the raw `limits` and `usages`. It drops `booster_wallet`. The key comes from `KIMI_API_KEY` or a prompt and is never written. Typed notes mark prompts in the log.
- `Sources/Providers/KimiCode/KimiCodeProvider+Mapping.swift` — gives each window an optional forecast period length. Only the five-hour window has one here. (providers 28) adds the weekly and monthly lengths.
- `Tests/KimiCodeProviderTests/` — replay tests from the capture.

### Capture protocol

1. Start with an empty window: no Kimi Code use in the last 5 hours.
2. Send a burst of prompts. Note it as "A".
3. 60 to 90 minutes later, send a second burst of a different size. Note it as "B".
4. Stay idle until 15 minutes after the reported `reset_time`, and at least until A + 5 hours.
5. After the reset, send one prompt. Note it as "C". Keep reading for 5 minutes.

| Observation | Fixed block | Sliding window |
|---|---|---|
| `reset_time` after A and B | Stays within 5 minutes | Moves forward |
| Ratio while idle | Holds | Falls in steps as old usage expires |
| At `reset_time` | Drops to 0 at once | Drops by A's share and keeps B's |
| Next `reset_time` | 5 hours later | Depends on the remaining usage |

The protocol assumed that a block starts at the first use, as Claude Code's does. Kimi's blocks do not (Evidence), so step 5 was not needed.

## Evidence

**Capture of 2026-10-29.** The user's new-plan account on `api.kimi.ai`. Reads one minute apart from 18:27 UTC, through the reset at 23:15:51 and past it. All returned 200. Burst A was at 18:37 and burst B at 19:38, with steady use between and after them until 20:47. Stored outside the repository.

- **The reset never moved under use.** The ratio rose from 0 to 49.14% between 18:28 and 20:47. `reset_time` stayed `23:15:50Z` or `23:15:51Z` on all 285 reads before the reset.
- **The ratio held while idle.** It stayed at 49.14% from 20:47 until 23:15:36, the last read before the reset.
- **It dropped to 0 at once.** At 23:16:36 the ratio read 0, and `reset_time` moved to `2026-10-30T04:15:50Z`, exactly 5 hours later. The monthly pool stayed at 10.52%, so the drop was a reset, not a correction.
- **The block does not start at the first use.** At 18:27:40 the ratio was 0 and the block already ended at `23:15:51Z`. It started at 18:15:51, about 13 minutes before the first use.
- **The blocks follow a fixed 5-hour grid.** The legacy `resetTime` ends in `:15:51.331760Z` on every read, across three days:

| Read | Ratio | Legacy `resetTime` | Hours after the first |
|---|---|---|---|
| Live fixture, 2026-10-27 | 8.41% | `2026-10-27T11:15:51.331760Z` | 0 |
| 2026-10-29 08:55 UTC | 0% | `2026-10-29T13:15:51.331760Z` | 50 |
| 2026-10-29 18:27 UTC | 0% → 49.14% | `2026-10-29T23:15:51.331760Z` | 60 |
| 2026-10-29 23:16 UTC | 0% | `2026-10-30T04:15:51.331760Z` | 65 |

- **A reset is reported at 0%.** Unlike Claude Code (providers 17), an unused block still has a `reset_time`. At 0%, the legacy entry has `remaining` `"100"` and no `used`.
- `reset_time` keeps the same 1-second flip as in (providers 27). It is within the reset tolerance (core 12 AC3).

**Verdict: fixed block.** The five-hour window is a fixed 5-hour period on a grid anchored to the account. AC2 and AC4 apply. AC3 does not.

## Acceptance Criteria

### AC1: The capture records a verdict

- **Given** a capture that follows the protocol
- **When** it is reviewed
- **Then** this spec's Evidence lists the reset anchors, any reset moves above the tolerance, any drop before a reset, and a verdict: fixed block or sliding window.

### AC2: A fixed block carries a five-hour descriptor

- **Given** the verdict is a fixed block, and a five-hour window with a reset date
- **When** the provider maps it
- **Then** its metric carries a fixed-period descriptor with limit 100, the window's reset date, a length of 5 hours, percentage points at resolution 0.01, receipt timing, and the line's ID
- **And** it uses the recent pace, because its period is one day or less (core 12 AC5)
- **And** an unused window at 0% with a reset date carries one too, because Kimi's block starts on its grid, not at first use
- **And** a window without a reset date carries no descriptor
- **And** the weekly and monthly metrics keep no descriptor until (providers 28).

### AC3: A sliding window stays unsupported

- **Given** the verdict is a sliding window
- **When** the provider maps the five-hour window
- **Then** its metric carries no descriptor, and this spec closes with only the Evidence.

### AC4: Fixtures replay the capture

- **Given** the verdict is a fixed block
- **When** provider tests run
- **Then** a redacted trace of the capture replays the anchor, the reset, and the next period, and Smart refresh sees no change from reset jitter alone (core 11).

### AC5: The package builds clean

- **Given** a fresh checkout after the change
- **When** the validation gate runs
- **Then** format, lint, both builds, and `swift test` pass with zero warnings.

## Plan

1. [x] Run the capture per the protocol. Done on 2026-10-29.
2. [x] Record the Evidence and the verdict (AC1). Fixed block.
3. [x] Fixed block: add the descriptor (AC2). The weekly and monthly windows keep no descriptor until (providers 28). Each window has an optional forecast period length, and only the five-hour window sets it.
4. [x] Add the replay fixture and tests (AC4), and the mapping tests for (AC2). Three segments of the capture: `kimi-capture-five-hour-first-use.json` (18:27–18:47, 0% baseline and first use), `kimi-capture-five-hour-steady-use.json` (19:38–20:08), and `kimi-capture-five-hour-rollover.json` (22:55–23:23, idle jitter and the reset). Each read keeps only `limits` and `limit_5h`. Replay through Core: the 0% baseline already carries the descriptor; steady use learns, then estimates depletion around 22:15–22:25 at the recent pace, before the 23:15 reset; Smart refresh reports one change in the rollover segment, at the reset, and none for the jitter.
5. [x] Update (providers 28 AC1, AC4) and (providers 24, Out of scope) with the verdict.
6. [ ] Manual check with the user's account: during use, the five-hour row and the headline show "of use remaining" text, and the text clears at the next block.

## Risks

- **Quota cost.** The bursts use part of the window and the monthly pool.
- **One plan, one region.** The capture covers a new-plan account on `api.kimi.ai`. Legacy plans and `api.kimi.com` may differ.
- **Mixed signals.** The ratio and the legacy counter may disagree on the reset. The verdict uses `limit_5h`, because the merge keeps the ratio when they agree (providers 27 AC3).

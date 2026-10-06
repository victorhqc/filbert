## Objective
Read Claude Code usage from supported JSON output shapes without rejecting normal tool inventories at the previous 64 KiB limit.

## Context
- `Sources/Providers/ClaudeCode/SubprocessOutputCollector.swift` caps retained raw standard output and counts standard-error bytes.
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher+Parse.swift` currently requires one JSON object with a string `result` field.
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` validates output before it writes the cache.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherDiagnosticsTests.swift` covers output classification and Boolean error flags.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherSubprocessTests.swift` covers subprocess output and cache preservation.
- A user supplied Claude Code 2.1.280 output with session and weekly figures in both prose and `usage_report.rate_limits.limits`.
- In that output `usage_report` is a root-level key; usage rows live at `usage_report.rate_limits.limits`, and each row is `{kind, group, percent, resets_at, scope, severity, is_active}`.
- `usage_report.session` is a cost/duration object, not a usage window; only `limits` rows carry percentages.
- A real `percent` is an integer (e.g. `54`) and decodes as a `Double`; a string `percent` fails strict decoding.
- A real `resets_at` is ISO 8601 with six fractional digits and a `+00:00` offset (e.g. `2026-10-05T13:50:00.473061+00:00`). `ISO8601DateFormatter` parses it only with `.withFractionalSeconds`, and parses the non-fractional form only without it, so decoding needs both.
- A real prose `result` can include a `Current week (<model>)` line and a `Current session: N% used` line with no reset phrase; the existing exact-prefix parser already ignores or accepts these.
- The structured `usage_report` object is absent from Filbert's own 2.1.280 `--output-format json` output, which carries only the prose `result`. Supporting `usage_report` is compatibility for outputs that include it, not the shape Filbert currently receives.
- Filbert invokes only `--output-format json`, which emits a single result object. A verbose `stream-json` message array is deliberately not supported; an array root stays an `invalid-envelope` failure.
- The supplied JSON is an extract, not the complete output from Filbert's exact invocation.
- No additional user evidence is required for this change. Tests will cover the supplied report and the identified output shapes.
- This change extends (providers 14) and supersedes its 64 KiB capture limit and object-only envelope rule.
- Startup isolation, process lifecycle, cache preservation, and log privacy remain unchanged (providers 03, providers 06, providers 14, core 10).

## Acceptance Criteria

### AC1: A 20 MiB raw-output budget
- **Given** a subprocess with a large tool, MCP, or plugin inventory
- **When** Filbert collects standard output
- **Then** Filbert retains up to 20 MiB, exactly 20,971,520 bytes, rather than 64 KiB.
- **And** read buffers have a separate fixed chunk size, at most 64 KiB per stream.
- **And** standard-error text remains unretained.
- **And** byte counts represent observed stream bytes, not retained bytes.
- **Given** standard output exceeds 20 MiB
- **When** Filbert validates the collected output
- **Then** Filbert reports `output-too-large` and does not parse a partial response.
- **And** the existing drain, termination, and completion bounds remain in effect.

### AC2: Supported JSON envelopes
- **Given** complete JSON within the raw-output budget
- **When** Filbert validates the output
- **Then** Filbert accepts one object that carries a string `result` and/or a root-level `usage_report`.
- **And** the only usage positions Filbert reads are the `result` string and `usage_report.rate_limits.limits` rows.
- **And** any other JSON root, including a scalar or an array, is an invalid envelope. A message array is now also supported (providers 16 AC2, providers 16 AC3).
- **And** failure mapping uses the existing codes: a non-object root is `invalid-envelope`; an object with neither `result` nor `usage_report` is `result-missing`; a present `result` that is null or not a string is `result-invalid`; a present report or result with no usable window is `usage-windows-missing`.
- **And** Filbert does not search arbitrary nested objects for usage percentages.
- **And** an envelope without usable usage data produces a failure, not a successful empty cache write.

### AC3: Structured session and weekly windows
- **Given** `usage_report.rate_limits.limits` contains usage rows
- **When** Filbert maps those rows
- **Then** only rows inside that array are considered; `usage_report.session` is not a usage row.
- **And** `kind: "session"` supplies the five-hour window.
- **And** `kind: "weekly_all"` supplies the weekly window.
- **And** the numeric `percent` supplies the used percentage, decoded strictly as a number.
- **And** an ISO 8601 `resets_at` supplies the reset timestamp, accepting optional fractional seconds and a `Z` or `±HH:MM` offset.
- **And** the whole timestamp string and its calendar components are validated, so trailing text and impossible dates such as `2026-02-30` yield an invalid timestamp rather than a coerced one.
- **And** an absent or invalid reset timestamp does not discard an otherwise usable percentage.
- **And** missing or incorrectly typed percentages do not become zero.
- **And** `is_active: false` does not suppress a weekly window.
- **And** `weekly_scoped` and unknown row kinds do not replace the session or weekly windows.
- **And** malformed rows do not discard other valid rows.

### AC4: Deterministic selection and prose compatibility
- **Given** the output contains both structured windows and prose windows
- **When** Filbert selects the usage data
- **Then** structured data takes precedence for each reported window.
- **And** the existing prose parser supplies a window absent from the structured data.
- **And** when `limits` repeats a window kind, the last valid row for that kind wins.
- **And** a window absent from both sources retains the existing cache behavior.
- **Given** the existing single-object prose response
- **When** Filbert validates the output
- **Then** percentages and reset phrases retain their existing behavior.

### AC5: Explicit errors prevent cache writes
- **Given** the subprocess exits with a nonzero status or the envelope object carries Boolean `is_error: true`
- **When** Filbert validates the output
- **Then** the refresh fails even if the same object also carries usable usage data.
- **And** the failure leaves the cache unchanged.
- **And** Filbert preserves the existing diagnostic error codes and safe metadata.
- **And** incorrectly typed error flags do not become Boolean values.
- **And** truncated, incomplete, or invalid JSON never supplies cache data.

### AC6: Unrelated fields do not become provider state
- **Given** JSON contains MCP, tool, plugin, account, model, or session metadata
- **When** Filbert decodes the response
- **Then** typed decoding ignores unrelated fields.
- **And** Filbert retains only selected windows and safe diagnostic metadata after validation.
- **And** Filbert does not create a full dictionary or object tree of inventory data to remove fields afterward.
- **And** Filbert does not use regex to remove JSON fields.
- **And** raw stdout remains subject to the 20 MiB budget before decoding.
- **And** no response text or inventory enters logs, visible errors, preferences, or the usage cache.

### AC7: Regression tests include large inventories
- **Given** the updated collector and parser
- **When** the focused tests run
- **Then** fixtures cover the supplied structured report, the existing prose object, and an object carrying both.
- **And** a valid inventory larger than 64 KiB does not cause a refresh failure.
- **And** boundary behavior at the capture limit is verified with an injected capture limit, plus an assertion that the default limit is 20,971,520 bytes.
- **And** fixtures cover fractional reset times, invalid reset timestamps, inactive weekly rows, unknown kinds, malformed rows, and repeated rows.
- **And** fixtures cover an `is_error: true` object that also carries usable usage data.
- **And** sentinel inventory contents never reach the cache, log, or visible error.
- **And** subprocess tests use fake executables without Claude credentials or network requests.

### AC8: The superseded diagnostics spec is updated
- **Given** this change replaces the 64 KiB capture limit and the object-only envelope rule
- **When** a reader opens (providers 14 AC1, AC3)
- **Then** its capture limit, envelope rule, and output-failure list match this spec.

## Plan
1. [x] Raise raw stdout retention to 20 MiB (20,971,520 bytes) and give the reader a separate fixed chunk size of at most 64 KiB per stream.
2. [x] Add a typed envelope decoder for a single object with `result` and/or `usage_report`; add no array support.
3. [x] Decode `percent` strictly as a `Double` and `resets_at` against a strict ISO 8601 shape, validating the whole string and round-tripping its calendar components.
4. [x] Select structured windows per slot with the existing prose parser as a fallback, ranking structured above prose and taking the last valid row per kind.
5. [x] Preserve explicit error checks (nonzero exit, Boolean `is_error` on the envelope object) before cache writes.
6. [x] Update the ordered output-failure list in (providers 14 AC1) and the capture limit in (providers 14 AC3) to match this spec.
7. [x] Add synthetic large-inventory, envelope, boundary, privacy, and cache-preservation tests; update the existing tests that assume the 64 KiB cap, and add an injected-capture-limit seam for boundary tests.
8. [x] Run the complete repository validation gate and review memory bounds and lifecycle behavior.

## Findings
- `ISO8601DateFormatter` accepts trailing text after a valid instant and normalizes impossible dates such as `2026-02-30`, so `parseISOTimestamp` matches the whole ISO 8601 shape and round-trips the calendar components instead of trusting a formatter.
- `runSpawnOnce` reached six parameters and tripped the SwiftLint parameter-count rule; the spawn inputs are grouped in a `SpawnConfiguration` value instead.
- The packaging gate step `python3 scripts/test-local-signing.py` fails on `test_native_foundation_argument_bridge_preserves_temporary_persistent_domain` (`Foundation home is not isolated`) in this environment. (providers 14) records the same pre-existing failure.

## Risks
- A 20 MiB raw budget uses more memory than the previous cap. Decoder allocations add to the retained raw buffer.
- Unrelated fields remain in raw memory until validation completes, even though typed decoding ignores them.
- The supplied JSON is a trimmed fragment, so it does not prove the incident was 64 KiB truncation. The supported shapes address compatibility, not a proven cause.
- The structured `usage_report` is absent from Filbert's current output, so the structured path is unexercised in normal use. The prose fallback remains the primary source.
- Claude's structured report can change. The prose fallback preserves compatibility with the existing response shape.
- A message array is rejected as `invalid-envelope`. If a future Claude release emits an array for `--output-format json`, Filbert keeps stale data until this spec is revised.
- A valid report can exceed 20 MiB. Filbert must report that limit explicitly rather than silently truncate or accept partial data.

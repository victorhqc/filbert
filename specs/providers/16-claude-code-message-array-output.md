## Objective
Request the single-object JSON output from Claude Code, accept a message array when Claude Code still sends one, and identify unsupported JSON roots without exposing subprocess contents.

## Context
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher+Parse.swift` accepts one root object and rejects arrays.
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` defines `spawnArguments` and carries parse results and safe subprocess metadata to the refresh error.
- `Sources/Core/DiagnosticError.swift` defines the shared, typed subprocess metadata.
- `Sources/Core/ErrorLog.swift` writes that metadata at the existing app failure boundary.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherTests.swift` derives the expected argv from `spawnArguments`.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherDiagnosticsTests.swift` covers object responses and rejects array roots.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherSubprocessTests.swift` covers subprocess output, cache updates, and private data.
- `Tests/CoreTests/ErrorLogSubprocessDiagnosticsTests.swift` covers subprocess fields in the error log.
- This change extends the diagnostics (providers 14) and structured report support (providers 15).
- This change supersedes the object-only rule (providers 14 AC1, providers 15 AC2).
- This change adds one argument pair to the documented argv (providers 03 AC1, providers 06 AC4).
- The capture limit, process lifecycle, startup isolation flags, and refresh schedule remain unchanged (providers 03, providers 06, providers 14, providers 15).

### Confirmed incident evidence
- The supplied logs export contains 648 complete JSON records, one record per line.
- All 648 records describe `app`, `proactive-refresh`, `claude-code`, and `usage-data-missing`.
- The first 614 records lack subprocess diagnostics. Their timestamps span `2026-10-02T14:42:36Z` through `2026-10-05T14:13:49Z`.
- The remaining 34 records contain subprocess diagnostics. Their timestamps span `2026-10-05T14:19:25Z` through `2026-10-05T17:07:33Z`.
- Every diagnostic record contains the values below.

| Field | Observed value |
|---|---|
| `exitStatus` | `0` |
| `outputFailure` | `invalid-envelope` |
| `stdoutBytes` | Between 8,677 and 9,017 |
| `stdoutTruncated` | `false` |
| `stderrBytes` | `0` |

- No diagnostic record contains `cliReportedError`.
- The output size is below both 64 KiB and 20 MiB. The capture limit does not explain these 34 failures.
- The log contains no raw response, root shape, Claude version, or Filbert version.
- The first diagnostic record occurs after the merge of providers 14 (`0b6562a`, `13:22Z`) and the `v0.17.0` tag (`df0bd12`, `13:53Z`).
- `v0.17.0` is the only tagged release with subprocess diagnostics. The 34 records probably come from that release, which already parses `usage_report`. The log does not prove this.
- The log does not prove a successful provider API request. Exit status 0 describes the subprocess, not the provider API.
- The log does not establish the cause of the older 614 failures.

### Supplied report and parser evidence
- The user supplied successful text from `claude -p /usage`: session 54%, weekly all-model usage 18%, and scoped weekly usage 20%.
- The text also contains local activity statistics and tool, skill, and MCP information.
- The prose lines match the existing prose parser. A `result` string with this text produces both windows.
- The session reset in the text is `Oct 5 at 3:50pm (Europe/Berlin)`, which is `2026-10-05T13:50Z`. The user captured the text and JSON before that time.
- The capture is earlier than the first diagnostic record (`14:19:25Z`). It is not a capture of a failed Filbert refresh.
- The user supplied a trimmed JSON report from a command with `--output-format json`.
- The user removed the remainder of the output and described it as "the whole tool/MCP/plugin inventory".
- The trimmed object contains these direct fields: `usage_report`, `claude_code_version` (`2.1.280`), and `model` (`claude-opus-5-5[1m]`).
- The `model` value shows that the user did not use the Filbert arguments, which include `--model haiku`. The complete command arguments are unavailable.
- The outer wrapper is unavailable. The user can have removed an enclosing array or merged fields from more than one message during the trim.
- The report includes these rows under `usage_report.rate_limits.limits`:

```json
[
  {
    "kind": "session",
    "percent": 54,
    "resets_at": "2026-10-05T13:50:00.473061+00:00",
    "is_active": true
  },
  {
    "kind": "weekly_all",
    "percent": 18,
    "resets_at": "2026-10-09T06:00:00.473081+00:00",
    "is_active": false
  },
  {
    "kind": "weekly_scoped",
    "percent": 20,
    "resets_at": "2026-10-09T06:00:00.473239+00:00",
    "is_active": false
  }
]
```

- This example retains only fields relevant to the proposed tests. It is not the complete response or the complete supplied report.
- The supplied rows also contain `group`, `scope`, and `severity`. The `weekly_scoped` row has `scope.model.display_name: "Fable"`. It matches the text line `Current week (Fable)`, and Filbert ignores it.
- The report also contains `usage_report.session` and `usage_report.rate_limits.extra_usage`. Filbert ignores both.
- Providers 15 records that the nonverbose object output of Claude Code `2.1.280` for the Filbert arguments contained no `usage_report`.
- At revision `df0bd12`, the built parser accepts the supplied report as a root object and selects 54% and 18%.
- A synthetic array containing the same report produces `invalid-envelope`.
- A banner-only object produces `usage-windows-missing`. An unrelated object produces `result-missing`.
- Two newline-separated objects produce `invalid-json`. These objects are not a JSON array.
- All 14 focused parser and diagnostics tests passed during the investigation.
- The earlier diagnostic parser also distinguishes unsupported roots from malformed JSON. Both diagnostic implementations reject array roots.
- In both revisions, `invalid-envelope` requires two results: `JSONDecoder` rejects the data, and `JSONSerialization` accepts it with fragments allowed.
- `UsageEnvelope` decodes every field with `try?`. For a root object, only a document-level `JSONDecoder` failure can reject the data.
- A local probe compared both APIs on object roots with lone UTF-16 surrogate escapes, an out-of-range number, duplicate keys, and a byte order mark. `JSONDecoder` accepted each object.
- The independent assessment found one object root that `JSONDecoder` rejects and `JSONSerialization` accepts: an object with nesting exactly 512 levels deep. That object produces `invalid-envelope`.
- A 512-level nesting is implausible in an output of approximately 9 KB. The limit can change between macOS versions.

### Documented Claude Code behavior
- The Agent SDK reference documents `claude_code_version`, `model`, `tools`, `mcp_servers`, and `plugins` as top-level fields of the `system` message with `subtype: "init"`. The documented result message has none of these fields.
- The Agent SDK reference states that the `/usage` output arrives as an assistant message. No source documents `usage_report`.
- The Agent SDK reference describes `SDKResultMessage` as the "Final result message". It does not state that every run emits one.
- The CLI reference describes `--verbose` as an override of the `viewMode` setting.
- The settings reference documents `viewMode` (`"default"`, `"verbose"`, or `"focus"`) and the Boolean `verbose`. `viewMode` takes precedence when both are set.
- The settings precedence is: managed settings, then command-line arguments including `--settings`, then local, project, and user settings.
- The CLI reference states that `--settings` values override the same keys in `settings.json` files for one session.
- The CLI reference lists what `--safe-mode` disables: CLAUDE.md, skills, plugins, hooks, MCP servers, custom commands and agents, output styles, and similar customizations. Ordinary settings such as `viewMode` are not in that list.
- User report: `anthropics/claude-code#84784` (Claude Code `2.1.220`) states that `-p --output-format json` returns an array with `--verbose` or with `"viewMode": "verbose"` in `~/.claude/settings.json`.
- In that report, the array elements are `system` (`init`), `rate_limit_event`, `assistant`, and `result`. The `result` element is last. A second user reproduced the behavior.
- A bot closed that issue as inactive. No maintainer replied. The behavior is not documented as a contract.

### Hypothesis and limits
- A top-level message array is the leading explanation for the 34 diagnostic failures.
- Inference: a `viewMode: "verbose"` or `verbose: true` setting in the user's configuration changes the Filbert output into an array. `--safe-mode` probably does not prevent this.
- A valid scalar root, a `null` root, the nesting-depth disagreement, or an unknown build also fit `invalid-envelope`. The existing log does not distinguish these cases.
- The trimmed report is not proof that Filbert received that report inside an array.
- Inference: the supplied output contained `init` message content, so it was probably a message array.
- The supplied `usage_report` appeared beside `init` fields. This is consistent with a report on the `system` message, but does not prove it. The trim can have merged messages.
- The report can also be nested in a message, for example under `message`. Filbert reads only a direct `usage_report` field.
- Array support is a compatibility measure, not a confirmed repair of the incident.
- No additional user JSON is available. The plan must not require access to the missing response.
- The user can run a probe that returns only the root shape, message types, and top-level keys (Plan step 2). The result can confirm the hypothesis without raw output.

### Independent assessment and decisions
- An independent Claude assessment reviewed this document, the referenced code, and public documentation on 2026-10-06. It recommended implementation after the changes below.
- The user approved these decisions on 2026-10-06:
  - Filbert passes `--settings '{"viewMode":"default"}'` and also accepts message arrays (AC1, AC2).
  - Array success requires a `type: "result"` element. Untyped objects are valid only as the single-object root (AC3).
  - Report and prose sources have a fixed rank, so an `init` report cannot override the final result (AC4).
  - One `JSONDecoder` pass decides validity and root shape. `JSONSerialization` is removed (AC7, AC8).
  - `process-failed` records also carry the root shape (AC7).
  - The fixtures from the assessment are added (AC9).

## Acceptance Criteria

### AC1: Request the default view mode
- **Given** a user configuration with `viewMode: "verbose"` or `verbose: true`
- **When** the refresher spawns Claude Code
- **Then** argv includes the pair `--settings` and `{"viewMode":"default"}`.
- **And** the pair overrides the user, project, and local `viewMode` and `verbose` settings for that session only.
- **And** Filbert does not read, write, or inspect any Claude Code settings file.
- **And** the variadic `--tools ""` argument still has another flag to its right, and `-p "/usage"` stays last (providers 06 AC4).
- **And** all other arguments, the environment, and the working directory remain unchanged.
- **And** managed settings can still force verbose output. AC2 through AC5 handle that case.

### AC2: Explicit supported roots
- **Given** complete JSON within the existing capture limit
- **When** Filbert validates the response
- **Then** Filbert accepts the existing single-object envelope with its current rules, independent of its `type` field.
- **And** Filbert also accepts a nonempty array in which every element is an object.
- **And** any non-object array element makes the array an `invalid-envelope`, including a nested array.
- **And** an empty array, a scalar root, or a `null` root produces `invalid-envelope`.
- **And** JSON that `JSONDecoder` rejects, including newline-separated JSON objects, produces `invalid-json`.
- **And** truncated output produces `output-too-large` before JSON validation.
- **And** Filbert does not extract a valid prefix from incomplete output.

### AC3: Fields that Filbert reads from an array
- **Given** a supported message array
- **When** Filbert reads its elements
- **Then** Filbert reads structured rows from a direct `usage_report.rate_limits.limits` field on any element, independent of its `type`.
- **And** Filbert reads a direct `result` field and a direct `is_error` field only from elements with string `type: "result"`.
- **And** Filbert ignores `result` and `is_error` on all other elements, including `assistant`, `system`, untyped, unknown, and non-string `type` values.
- **And** Filbert ignores all other fields, including `subtype`, `message.content`, tool results, inventory fields, and arbitrary nested objects.
- **And** an array without a `type: "result"` element fails with `result-missing`, even when other elements contain usable reports.
- **And** Filbert reads all `type: "result"` elements when more than one is present.

### AC4: Deterministic selection across messages
- **Given** a supported array with at least one `type: "result"` element
- **When** Filbert selects each window
- **Then** Filbert uses the first source in this list that supplies the window:
  1. Structured rows from `usage_report` on a `type: "result"` element.
  2. Prose from the `result` string of a `type: "result"` element.
  3. Structured rows from `usage_report` on any other element.
- **And** in one source rank, the last valid value in array order wins.
- **And** row order inside each report remains significant.
- **And** malformed rows do not replace earlier valid rows.
- **And** an `init` report cannot replace a window that the result element supplies.
- **And** session, weekly, percentage, and reset-time rules remain unchanged (providers 15 AC3, providers 15 AC4).
- **And** the single-object envelope keeps its current rule: structured rows take precedence over prose.
- **And** an absent window retains the existing cache behavior.

### AC5: Errors prevent partial success
- **Given** usable windows and a Boolean `is_error: true` that AC3 permits Filbert to read
- **When** Filbert validates the complete array
- **Then** the refresh fails with `cli-reported-error` and writes no cache data.
- **And** the position of the error element does not change the result.
- **And** a later successful element does not cancel an earlier explicit error.
- **And** nested tool errors and `is_error` fields that AC3 ignores do not become a CLI error.
- **And** incorrectly typed error flags do not become Boolean values.
- **And** aggregate `cliReportedError` is `true` if any readable flag is true.
- **And** aggregate `cliReportedError` is `false` if at least one readable flag is false and none is true.
- **And** aggregate `cliReportedError` is absent if no element supplies a readable Boolean flag.
- **And** a nonzero process exit retains `process-failed`, even when output contains usable windows.
- **And** every failure leaves the existing cache unchanged.

### AC6: Stable failure classification
- **Given** a supported array that does not produce usable windows
- **When** Filbert classifies the failure
- **Then** Filbert applies the first matching rule in this list:
  1. Structural failures from AC2.
  2. No `type: "result"` element: `result-missing`.
  3. A readable `is_error: true`: `cli-reported-error`.
  4. Any element with a direct `usage_report` field: `usage-windows-missing`.
  5. A readable string `result`: `usage-windows-missing`.
  6. A readable non-string `result`: `result-invalid`.
  7. Otherwise: `result-missing`.
- **And** existing single-object failure classification remains unchanged.
- **And** Filbert does not interpret `subtype` values such as `error_max_turns`.
- **And** Filbert does not infer authentication errors, provider rate limits, or HTTP status from these failures.

### AC7: Safe root-shape diagnostics
- **Given** a completed subprocess that fails with `process-failed` or `usage-data-missing`
- **When** Filbert records the failure
- **Then** the record includes `stdoutJSONShape` when `JSONDecoder` accepts the complete, untruncated output.
- **And** the shared subprocess contract exposes this field as an optional typed enum.
- **And** the only enum values are `object`, `array`, `scalar`, and `null`.
- **And** the shape describes the complete root, even when the envelope is unsupported.
- **And** invalid JSON, empty output, truncated output, and incomplete output omit the shape.
- **And** strings, numbers, and Boolean roots all use `scalar`.
- **And** existing error codes and subprocess fields retain their meanings.
- **And** other providers require no changes and omit the field unless they supply it.
- **And** raw output, previews, message types, keys, and inventory contents never enter the log or visible error.
- **And** the existing app boundary records the failure once.

### AC8: Bounded parsing and unchanged subprocess behavior
- **Given** a response with large unrelated inventories or many messages
- **When** Filbert decodes the response
- **Then** one typed `JSONDecoder` pass decides validity, root shape, and the selected fields.
- **And** no path uses `JSONSerialization` or builds an untyped object tree.
- **And** typed decoding skips unrelated fields without decoding them into typed values.
- **And** array traversal retains selected windows and fixed diagnostic state, not a second collection of complete messages.
- **And** the retained raw-output limit remains 20,971,520 bytes.
- **And** reader chunks remain at most 64 KiB per stream.
- **And** Filbert examines the complete array before cache writes or success.
- **And** apart from AC1, command arguments, environment, working directory, timeout, cancellation, debounce, and refresh schedule remain unchanged.
- **And** the change makes no additional Claude invocation, network request, or credential read.
- **And** captured output is not persisted for diagnostics.

### AC9: Regression and privacy evidence
- **Given** the updated parser, argv, and diagnostics
- **When** the focused and subprocess tests run
- **Then** the argv test still derives its expected value from `spawnArguments` and confirms the `--settings` pair and the flag order from AC1.
- **And** fixtures cover the supplied report as an object and in a synthetic message array.
- **And** fixtures cover the documented order: `system` `init`, `rate_limit_event`, `assistant`, then `result`.
- **And** fixtures cover a report on a `system` `init` message with synthetic inventory fields, a report on a `result` element, and a prose-only `result` element.
- **And** fixtures cover `/usage` text only in `assistant` `message.content`. This fixture must fail.
- **And** fixtures cover an array without a `result` element, including one with a usable `init` report.
- **And** fixtures cover a `result` element with `subtype: "error_max_turns"`, an `errors` field, and no `result` field.
- **And** fixtures cover two `result` elements.
- **And** fixtures cover an `init` report that conflicts with a result report and with result prose.
- **And** fixtures cover `result` and `is_error` on `system`, `assistant`, untyped, and unknown elements, which Filbert ignores.
- **And** fixtures cover `is_error` as a string on a `result` element.
- **And** fixtures cover repeated windows, prose fallback, and the source ranks from AC4 in both message orders.
- **And** fixtures cover errors before and after usable data, and nested tool errors.
- **And** fixtures cover empty arrays, mixed non-object elements, nested arrays, scalar roots, `null`, and newline-separated objects.
- **And** fixtures cover the nesting-depth limit, which produces `invalid-json`.
- **And** fixtures cover every failure classification from AC6 and aggregate Boolean metadata.
- **And** log tests verify root-shape values, `process-failed` with an array root, and omitted optional fields.
- **And** private sentinel contents never reach the cache, log, or visible error.
- **And** fake subprocess tests cover array success, nonzero exits, malformed output, and cache preservation.
- **And** a representative array below 10 KiB proves that compatibility does not depend on the larger capture limit.
- **And** fixtures with unrelated inventories above 64 KiB retain successful parsing within the existing 20 MiB limit.
- **And** test descriptions identify synthetic wrappers as synthetic, not as recovered user output.
- **And** tests use fake executables without user credentials or provider requests.

## Plan
1. [x] Obtain an independent Claude assessment of the evidence and proposed array contract before implementation.
2. [ ] Ask the affected user to run the shape probe below. This step is optional. Implementation does not wait for the result. Skipped on 2026-10-06: the probe result is not obtainable.
3. [x] Resolve the assessment findings with the user. Record the decisions in this document.
4. [x] Add the `--settings` pair to `spawnArguments` before `--tools ""`. Update the argv in providers 03 AC1 and the reasoning in the `spawnArguments` comment.
5. [x] Replace the `JSONDecoder` and `JSONSerialization` sequence with one typed root decoder. The decoder reports the root shape and has explicit object and array paths.
6. [x] Reuse the row rules across elements. Traverse arrays without retaining complete message collections.
7. [x] Aggregate windows by source rank, error flags, field presence, and failure classification before any cache write.
8. [x] Add optional typed root-shape metadata to the Core contract and existing error record.
9. [x] Carry root-shape metadata through `process-failed` and `usage-data-missing` errors without changing visible errors.
10. [x] Add argv, parser, subprocess, cache-preservation, memory-bound, and log-privacy tests.
11. [x] Update the superseded envelope rules, argv, and diagnostic fields (providers 03, providers 06, providers 14, providers 15).
12. [x] Run `swiftformat --lint .`, `swiftlint`, `swift build`, `swift build -c release`, and `swift test`.
13. [x] Run `python3 scripts/test-automatic-updates.py` and `python3 scripts/test-local-signing.py`.
14. [x] Ask the user to run the new argv against a local Claude Code once, with and without `"viewMode": "verbose"` set, and to confirm a successful refresh. The user ran the check on 2026-10-06 (see "Local argument check"). The check compared root shapes. It did not run a refresh in the app.
15. [x] Review the diff for error precedence, private data, decoder allocations, and process lifecycle changes.

### Implementation findings
- `JSONDecoder` accepts string, number, Boolean, and `null` roots. Root-shape detection does not need `JSONSerialization`.
- `JSONDecoder` rejects an object nested 600 levels deep. That output is now `invalid-json`.
- Validation moved to `ClaudeCodeRefresher+Validate.swift`. `ClaudeCodeRefresher+Parse.swift` keeps prose, timestamp, and cache-write logic.
- A deliberate reversal of the source ranks made the rank tests fail, so the tests detect a rank regression.

### Local argument check
The maintainer ran a script on 2026-10-06 with Claude Code `2.1.280`. The script set `"viewMode": "verbose"` in the user settings for two runs and then restored the file. It printed only root shapes, message types, and top-level keys.

| Run | Arguments | User `viewMode` | Root |
|---|---|---|---|
| 1 | New | Unset | Object |
| 2 | Previous | `"verbose"` | Array: `system`, `assistant`, `result` |
| 3 | New | `"verbose"` | Object |

- Run 2 reproduces an array root with the previous arguments, including `--safe-mode`. This confirms the leading hypothesis for this CLI version.
- Run 3 confirms that the `--settings` pair restores the single object (AC1).
- The array in run 2 contains a `type: "result"` element. Array support (AC3) can still read it when managed settings force the verbose view.
- Runs 1 and 3 return the same top-level keys: `result`, `is_error`, `type`, `subtype`, and metadata. Neither object has a top-level `usage_report`, which matches providers 15.
- The check did not show where the affected user's supplied `usage_report` came from.
- With `"viewMode": "verbose"` set, the maintainer also tested a build of this change. It recorded no Claude Code failure.
- During that test, the installed release (`/Applications/Filbert.app`, probably `v0.17.0`) recorded one failure at `2026-10-06T12:10:35Z`: `exitStatus` 0, `outputFailure` `invalid-envelope`, `stdoutBytes` 8,932, `stderrBytes` 0, and no `stdoutJSONShape`.
- These values match the 34 diagnostic records of the incident, and the byte count is in their range (8,677 to 9,017). The verbose view mode reproduces the incident with the previous release.

### Shape probe for the affected user
The probe uses the current Filbert arguments in an empty directory.
It prints the root shape and, for each element, `type`, `subtype`, and top-level keys.
It prints no field values, usage text, or inventory contents.

```sh
cd "$(mktemp -d)" && claude --model haiku --max-turns 1 --no-session-persistence \
  --safe-mode --strict-mcp-config --no-chrome --tools "" --output-format json -p /usage \
  | jq -c 'if type == "array" then {root: "array", elements: map(if type == "object" then {type, subtype, keys: keys} else {kind: type} end)} elif type == "object" then {root: "object", keys: keys} else {root: type} end'
```

The user runs the same command a second time with `--settings '{"viewMode":"default"}'` before `--tools ""`.
The user also reports the result of `claude --version`.
The user also reports whether `viewMode` or `verbose` is set in their Claude Code settings.

The probe result decides these questions:
- An `array` root from the first command confirms the leading hypothesis for the current CLI version.
- An `object` root from the second command confirms the AC1 override.
- The element that contains `usage_report` shows which source rank in AC4 supplies data for this user.
- An `object` root from the first command shows that the failure no longer reproduces. The incident root then remains unknown.
- A scalar root rejects the array hypothesis.

## Risks
- The actual failing root remains unknown. The override and array support cannot guarantee resolution of this incident.
- An older Claude Code version can reject or warn about `viewMode` in `--settings`. A rejection fails every refresh with `process-failed`. Plan step 14 checks one current version only.
- Managed settings take precedence over `--settings` and can still force an array.
- The override depends on undocumented behavior: no documentation states that `viewMode` changes the JSON root. The local argument check confirms the behavior for Claude Code `2.1.280` only.
- A scalar response will remain unsupported. Root-shape metadata will distinguish that case after a new failure.
- Claude Code can change its message types and report positions. Filbert reads reports on any element type. `result` and `is_error` on other types remain ignored until the contract changes.
- A report on a non-result element can be older than the `/usage` run. AC4 ranks it last, but Filbert still stamps it with the current time when it fills a window.
- If the supplied trim merged fields from different messages, the `system` report rule has no direct evidence. The rule is then a compatibility allowance only.
- Requiring a `result` element rejects a future array format that omits it.
- Rejecting any readable explicit error is conservative. Claude's message semantics could require a narrower rule later.
- Strict rejection of non-object array elements can reject a future mixed-format array.
- Multiple reports can disagree. Deterministic selection does not prove that the selected report is the newest provider snapshot.
- `JSONDecoder` indexes the whole document before typed decoding. The 20 MiB limit bounds bytes, not total process memory.
- Validity now follows `JSONDecoder`. Inputs that only `JSONSerialization` rejected, such as lone surrogate escapes, become valid JSON.
- New metadata does not explain historical records. It only applies to failures after the updated app runs.

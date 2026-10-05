## Objective
Make Claude Code refresh failures distinguishable in the private error log without recording subprocess text or changing the usage data source.

## Context
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` launches Claude, discards standard error, and reports `usage-data-missing` after an unsuccessful parse.
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher+Parse.swift` returns an empty array for several different output failures.
- `Sources/Core/DiagnosticError.swift` exposes a constant error code and an optional exit status.
- `Sources/Core/ErrorLog.swift` records approved error metadata at the existing failure boundary.
- `Tests/ClaudeCodeProviderTests/ClaudeCodeRefresherTests.swift` uses fake executables to exercise the subprocess path.
- `Tests/CoreTests/ErrorLogTests.swift` covers error records and private data.
- The reported log contains 557 `usage-data-missing` records. It does not distinguish invalid output from a valid response without usage figures.
- Static inspection of a local Claude Code 2.1.280 executable shows a headless `/usage` path that can return a subscription banner without usage figures.
- That local evidence does not establish the affected user's version or the cause of their missing data.
- This change extends the refresh path (providers 03), preserves startup isolation (providers 06), and obeys the error-log privacy rules (core 10).

## Acceptance Criteria

### AC1: Distinct output failure reasons
- **Given** a Claude subprocess that exits with status 0
- **When** Filbert cannot obtain usage windows
- **Then** the error record retains `causeCode: "usage-data-missing"`.
- **And** the record contains exactly one `outputFailure` value, selected in this order:
  1. `output-too-large`: standard output exceeds the capture limit.
  2. `empty-output`: standard output contains no bytes or only whitespace.
  3. `invalid-json`: the captured output is not valid JSON.
  4. `invalid-envelope`: the JSON root is not an object.
  5. `cli-reported-error`: the object contains the Boolean `is_error: true`.
  6. `result-missing`: the object has no `result` field.
  7. `result-invalid`: the `result` field is null or is not a string.
  8. `usage-windows-missing`: the string contains no supported usage windows.
- **And** Filbert does not infer an authentication failure, HTTP status, or rate limit from missing usage figures.
- **And** an error response never writes usage windows, even if its text matches the usage parser.

### AC2: Safe subprocess metadata
- **Given** a subprocess that exits with a nonzero status or fails output validation
- **When** the app records the refresh failure
- **Then** the record includes `exitStatus`, `stdoutBytes`, `stderrBytes`, and `stdoutTruncated`.
- **And** `stdoutBytes` and `stderrBytes` count bytes observed from each stream, not the retained buffer length.
- **And** `stdoutTruncated` reports whether standard output exceeds the capture limit.
- **And** a decoded Boolean `is_error` is recorded as `cliReportedError`, including `false`.
- **And** the record omits `cliReportedError` when the field is absent, has another type, or cannot be decoded.
- **And** existing process-failure codes remain unchanged.
- **And** other providers need no code changes and receive no new fields unless they supply this metadata.

### AC3: Bounded output collection
- **Given** a subprocess that writes output before it exits
- **When** Filbert collects the output
- **Then** Filbert drains standard output and standard error while the subprocess runs.
- **And** Filbert retains at most 64 KiB of standard output for JSON parsing.
- **And** Filbert counts standard-error bytes without retaining the standard-error text.
- **And** output beyond the capture limit does not block the subprocess or increase the retained buffer.
- **And** Filbert rejects truncated standard output rather than parsing a partial response.
- **And** output collection preserves the existing timeout, termination grace, cancellation, debounce, and shared-process behavior.
- **And** a descendant that retains a pipe does not extend the refresh beyond its bounded lifecycle.

### AC4: No private subprocess content
- **Given** subprocess output that contains sentinel credentials, prompts, account identifiers, paths, or settings contents
- **When** the app records a refresh failure
- **Then** none of those values appear in the log or the visible error.
- **And** no raw output, output preview, JSON result, external error message, or arbitrary subtype enters the log.
- **And** metadata uses typed numbers, Boolean values, and a fixed set of output-failure identifiers.
- **And** Filbert does not persist captured output in a temporary file.
- **And** log records retain the permissions, size limits, and local-only storage defined in (core 10).

### AC5: Existing refresh behavior remains intact
- **Given** a valid JSON response with supported usage windows and no Boolean `is_error: true`
- **When** the refresh completes
- **Then** Filbert updates the cache with the existing percentage and reset-time rules.
- **And** a successful refresh produces no error record.
- **Given** any failed refresh and a readable previous cache
- **When** Filbert displays the result
- **Then** the failed refresh leaves the cache unchanged.
- **And** the app retains the previous figures, timestamp, refresh warning, and `Show Logs` action (core 10 AC5).
- **And** the app retains the current localized error messages.
- **And** Filbert records the failure once at the existing app boundary, not again inside the refresher.

### AC6: Scope remains diagnostic
- **Given** the existing provider and refresh preferences
- **When** Filbert performs a refresh with the new diagnostics
- **Then** the command arguments, working directory, environment, and data source remain unchanged.
- **And** Filbert makes no additional Claude invocation, network request, or credential read for diagnostics.
- **And** Filbert does not change retry timing, automatic-refresh preferences, or helper installation.
- **And** Filbert does not record the resolved executable path or the user's environment.

### AC7: Regression tests cover real failure shapes
- **Given** the diagnostic implementation
- **When** the focused tests run
- **Then** fixtures cover every output-failure reason, including a banner-only response and an error response with matching usage text.
- **And** fixtures cover explicit `is_error: false`, absent `is_error`, and an incorrectly typed `is_error`.
- **And** fake executables cover successful usage, nonzero exit, large standard output, large standard error, timeout, and cancellation.
- **And** large-output tests prove that pipe capacity does not cause a hang.
- **And** tests cover a descendant that retains a pipe.
- **And** error-log tests verify field values, omitted optional fields, and the absence of sentinel private data.
- **And** tests prove that failed refreshes preserve existing cache contents.
- **And** tests use injected files and fake executables, not the user's Claude binary or credentials.

## Plan
1. [x] Add a typed optional subprocess-diagnostic value to the Core error contract.
2. [x] Extend the error record with only the approved fields from that value.
3. [x] Replace the empty-array failure path with a typed output-validation result.
4. [x] Preserve the existing window parser and expose the fixed output-failure reasons.
5. [x] Add bounded output collection with concurrent stream drains and lifecycle cleanup.
6. [x] Carry safe metadata through Claude refresh errors to the existing app log boundary.
7. [x] Add parser, subprocess, cache-preservation, and error-log privacy tests.
8. [x] Run the repository validation gate and review the diff for privacy and lifecycle regressions.

## Findings
- Standard error can no longer be `/dev/null`; (AC3) counts its bytes, so the
  child's stderr is drained through a pipe. (providers 03 AC1) is updated to
  match.
- Output collection no longer uses per-stream callbacks. One reader thread owns
  both streams, and `finish` joins it before taking the snapshot, so a read
  cannot race finalization. A final non-blocking drain is bounded by a deadline,
  and a stream that reaches end-of-file is retired, so neither a descendant that
  keeps writing nor an already-closed stream can extend or spin the refresh.
- `DiagnosticError.diagnosticExitStatus` is replaced by
  `diagnosticSubprocess.exitStatus`, so an exit-0 output failure records
  `exitStatus: 0`.
- The packaging gate step `scripts/test-local-signing.py` fails on
  `test_native_foundation_argument_bridge_preserves_temporary_persistent_domain`
  (`Foundation home is not isolated`) in this environment. The same failure
  reproduces on a clean `HEAD` checkout, so it predates this change.

## Risks
- A valid response without usage figures still does not identify the upstream cause. The diagnostic must not claim otherwise.
- JSON `is_error` is an external field. An absent or differently typed field must not imply success.
- Concurrent stream drains can introduce cancellation races or blocked readers. Timeout and retained-pipe tests are required.
- The 64 KiB capture limit rejects a larger otherwise valid response. The log must identify this condition explicitly.
- A broad metadata dictionary would permit private values to enter the log. The Core contract must remain typed and restricted.
- More diagnostic fields do not fix the missing usage data. The affected user's evidence remains necessary.

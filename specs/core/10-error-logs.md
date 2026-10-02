## Objective
Give users a persistent, private error log that they can open from each error shown by Filbert.

## Context
- `Sources/App/QuotaViewModel+Lifecycle.swift` writes diagnostic messages to standard error.
- `Sources/App/QuotaViewModel+Results.swift` handles failed refreshes and retains previous results.
- `Sources/App/QuotaViewModel+Setup.swift` handles helper installation, removal, and credential import.
- `Sources/App/QuotaViewModel.swift` catches proactive refresh failures before it reads cached data.
- `Sources/App/QuotaView.swift` shows provider errors and refresh errors.
- `Sources/App/SettingsView.swift` and `Sources/App/APIKeyFreeSettingsRow.swift` show setup and credential errors.
- `Sources/Providers/ClaudeCode/StatuslineCacheStore.swift` currently treats unreadable and malformed caches as absent data.
- Several providers write routine diagnostic messages to standard error.
- Provider modules must depend only on Core (core 01).
- Failed refreshes must retain previous results (ui 07).

## Acceptance Criteria

### AC1: Persistent log path
- **Given** a writable user log directory
- **When** Filbert encounters an error
- **Then** Filbert appends an error record to `~/Library/Logs/Filbert/errors.log`.
- The record contains a UTC timestamp, a component, an operation, and a stable error code.
- The record contains a provider ID when the error concerns a provider.
- The directory has mode `0700`. Log files have mode `0600`.
- Tests use an injected directory instead of the user's log directory.

### AC2: Errors only
- **Given** a successful operation or an expected setup state
- **When** Filbert installs a helper, reads data, refreshes data, or updates its presentation
- **Then** Filbert writes no diagnostic record.
- Missing first-run data, absent credentials, unsupported optional operations, and intentional cancellation are not errors.
- Existing routine diagnostic output must not remain on standard error.

### AC3: Errors from each operation
- **Given** a failed operation
- **When** Filbert handles the failure
- **Then** Filbert records the failure once at the boundary that handles it.
- This includes helper installation, helper removal, credential operations, quota fetches, and proactive refreshes.
- A provider that suppresses an internal failure records that failure before it returns a fallback.
- An unreadable or malformed existing Claude Code cache is an error, not an absent first-run cache.
- A failure does not require a running app to produce an error record from the Claude Code helper.

### AC4: Link beside errors
- **Given** an error in the popover or settings
- **When** Filbert shows the error
- **Then** Filbert also shows an accessible, localized `Show Logs` action beside the error.
- The action reveals the current log file in Finder.
- The same action appears beside a refresh error when previous results remain visible.
- The action also appears when a setup message reports a failed operation.
- Ordinary setup instructions and first-run absence of data do not show an error link.

### AC5: Proactive refresh failures remain visible
- **Given** a failed proactive refresh and a readable previous cache
- **When** Filbert reads the cache after the failure
- **Then** Filbert retains the previous results and timestamp.
- Filbert shows the refresh failure and `Show Logs`.
- A successful cache read must not erase the failure from that refresh attempt.
- A later successful refresh clears the visible failure.

### AC6: Private diagnostic content
- **Given** an error that contains private data
- **When** Filbert creates an error record
- **Then** Filbert records only approved diagnostic fields.
- Records must not contain API keys, tokens, prompts, transcripts, request headers, response bodies, or settings contents.
- Records must not contain raw cache previews or unfiltered subprocess output.
- Safe details can include an exit status, an operating-system error code, a decoding field name, or a known resource name.
- Tests use sentinel secrets to verify that private data never reaches the log.

### AC7: Bounded and reliable storage
- **Given** concurrent errors or a log at the size limit
- **When** Filbert appends a record
- **Then** records remain complete and the log storage remains bounded.
- Each file has a 1 MiB limit. Filbert retains the current file and one previous file.
- The app and the helper coordinate file writes and rotation.
- **Given** an unwritable log directory
- **When** an operation fails
- **Then** Filbert retains the original error without a crash or recursive log attempt.
- The error presentation states that the log is unavailable instead of offering a broken file link.

## Plan
1. Add a shared error writer in Core with an injectable destination and a small set of safe diagnostic fields.
2. Reuse the same file contract for the standalone Claude Code helper.
3. Replace routine diagnostic output with error records at the appropriate failure boundaries.
4. Keep error records separate from localized messages shown to users.
5. Add one shared UI action for the log location.
6. Retain proactive refresh failures through the subsequent cache read.
7. Add tests for error coverage, privacy, file permissions, concurrent writes, rotation, and unavailable storage.

## Risks
- Error descriptions from external systems can contain credentials or user data.
- The helper runs outside the app process. Unsynchronized writes can damage records during rotation.
- A cache read after a failed proactive refresh can falsely indicate that the refresh succeeded.
- A missing cache is normal on first install. Treating absence as an error would create misleading logs.
- Logs must remain local. This change does not upload diagnostic data.

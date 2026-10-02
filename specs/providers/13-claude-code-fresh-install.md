## Objective
Verify and repair the complete Claude Code setup and data flow from a fresh Filbert installation.

## Context
- `Sources/Providers/ClaudeCode/StatuslineHelperInstaller.swift` compiles the helper at installation time and modifies Claude Code settings.
- `Sources/Providers/ClaudeCode/Resources/statusline_helper.swift` receives status-line input and writes the usage cache.
- `Sources/Providers/ClaudeCode/StatuslineCacheStore.swift` reads the usage cache.
- `Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift` detects setup and maps the cache to Filbert results.
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift` runs Claude Code for a proactive refresh.
- `Sources/App/QuotaViewModel+Setup.swift` connects installation and removal to app state.
- `scripts/build-dmg.sh` packages app resources.
- Existing behavior covers the status-line helper, proactive refresh, and quiet execution (providers 02, providers 03, providers 06).
- Error records and links use the shared error-log contract (core 10).
- The current helper path is `~/.claude/filbert-statusline`.
- The current settings path is `~/.claude/settings.json`.
- The current cache path is `~/.cache/filbert/claude-code.json`.
- Development and installed builds currently share these paths.
- Initial inspection found a running `/Applications/Filbert.app` and existing helper, settings, and cache files.
- No user files were removed during initial inspection.
- The baseline command `swift test --filter ClaudeCodeProviderTests` passed all 78 tests on macOS with Swift 6.4.
- The helper source passed `swiftc -typecheck`.
- A Bash syntax check failed for the generated chained command. Its unquoted `#` markers start a shell comment.
- The helper currently converts invalid input to an empty payload and writes that payload over the previous cache.
- Existing tests do not execute the generated wrapper or the actual helper from a packaged app.

## Acceptance Criteria

### AC1: Safe reset scope
- **Given** existing Claude Code configuration and a possible installed Filbert app
- **When** a developer prepares the fresh-install test
- **Then** the developer identifies the development executable and all affected paths before the reset.
- Isolated automated tests use temporary settings, helper, cache, and log paths.
- A live reset requires user confirmation for the identified shared paths.
- The developer backs up affected files before the live reset.
- The reset removes only Filbert's helper integration and usage cache.
- The reset preserves Claude Code, authentication, projects, transcripts, unrelated settings, and other providers.
- The developer stops any app that can write to the shared files before the live reset.

### AC2: Complete helper installation
- **Given** Claude Code is available and Filbert's helper is absent
- **When** the user selects `Install Helper`
- **Then** Filbert installs an executable helper and verifies the effective status-line integration.
- Unrelated settings remain unchanged.
- An existing status-line command retains its output and receives the original input.
- The generated command passes a shell syntax check and an execution test through the invoking shell.
- The original command and the helper receive the same input bytes without premature shell expansion.
- Paths with spaces and shell metacharacters work.
- A second installation does not duplicate the integration.
- The installer does not report success for an executable helper with missing or incorrect settings.

### AC3: No compiler prerequisite for distributed apps
- **Given** a supported Mac without Xcode or Command Line Tools
- **When** the user installs the helper from a packaged Filbert app
- **Then** the installation succeeds without a compiler download or prompt.
- The helper is built and packaged for the app's supported architecture and minimum macOS version.
- Packaged validation uses the packaged helper, not a source file from the development checkout.

### AC4: Installation failure and recovery
- **Given** an unavailable helper resource, invalid settings, or a filesystem failure
- **When** helper installation fails
- **Then** Filbert shows the failed operation and `Show Logs`.
- Existing helper and settings contents remain recoverable.
- Filbert does not report that the helper is active.
- The user can retry after the cause is corrected.
- The same recovery path works after an interrupted or partial installation.

### AC5: Status-line input reaches results
- **Given** a fresh helper installation without a usage cache
- **When** Claude Code sends status-line input with usage windows
- **Then** the installed helper writes the expected cache.
- Filbert displays the 5-hour and weekly usage values and reset times from that cache.
- Filbert displays the cache timestamp instead of inventing a successful refresh timestamp.
- Automated coverage executes the actual helper with representative JSON input.
- A live test verifies the same path with a new Claude Code session.

### AC6: Empty and failed data states
- **Given** a fresh installation, a session without usage windows, or a failed cache operation
- **When** Filbert requests usage results
- **Then** Filbert distinguishes expected absence of data from a failed operation.
- Missing first-run data shows the action that can populate the cache.
- A valid payload without usage windows does not appear as populated usage.
- Invalid input must not replace previous usage data or advance its timestamp.
- Absent percentage and reset fields must not become a fabricated zero percentage or an epoch reset time.
- Invalid input and cache read or write failures produce safe error records.
- Errors offer a recovery action and `Show Logs` where the app can present the failure.

### AC7: Refresh flow
- **Given** a fresh installation or previous usage data
- **When** the user requests a refresh
- **Then** the proactive refresh writes usable data or returns an actionable failure.
- Tests cover binary discovery, working-directory selection, subprocess failure, timeout, cancellation, parsing, and cache writes.
- Failed refreshes retain previous results and their timestamp.
- Cache reads must not hide proactive refresh failures (core 10 AC5).
- Automatic refresh continues to obey the existing opt-in behavior (core 08).

### AC8: Removal and reinstall
- **Given** an installed helper with an existing chained status-line command
- **When** the user removes the helper
- **Then** Filbert restores the original command and preserves unrelated settings.
- Filbert removes its helper and cache, then returns to the setup state.
- Removal failures do not report successful removal.
- A subsequent installation and data refresh succeed without old cache data.

### AC9: Recorded verification
- **Given** the proposed repairs
- **When** the developer completes verification
- **Then** the developer records each scenario, its environment, its result, and any remaining limitation.
- Verification includes isolated tests, a packaged-app test, and the confirmed live fresh-install test.
- Existing unit tests alone are not evidence that a fresh installation works.
- The report distinguishes reproduced failures from hypotheses.
- The developer restores the user's original files after the live test unless the user requests the new installation.

## Plan
1. Run existing Claude Code tests to establish a baseline.
2. Trace binary discovery, helper installation, status-line invocation, cache creation, and the app's result state.
3. Exercise a clean temporary installation with the actual helper and representative input.
4. Record failures before changes. Add regression tests for each reproduced defect.
5. Build the helper with the app instead of compiling the helper on the user's Mac.
6. Verify installation state from the executable and effective settings.
7. Run packaged validation without access to development resources or a runtime compiler.
8. Obtain confirmation for the live reset. Back up the shared files and stop conflicting writers.
9. Remove Filbert's integration, install through the development app, and start a fresh Claude Code session.
10. Verify displayed results, manual refresh, failure presentation, removal, and reinstall.
11. Restore the original files and record the results.

## Risks
- A live reset affects the installed app because development and installed builds share the same paths.
- Claude Code authentication or a subscription without usage windows can limit live verification.
- A proactive Claude Code command can contact the provider or consume usage.
- Status-line command changes can damage a user's existing integration if input and shell quoting are incorrect.
- A packaged helper must retain executable permissions and comply with release signing requirements.
- A test on a development Mac with Xcode does not prove that installation works without Command Line Tools.

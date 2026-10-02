## Objective
Verify and repair the complete Claude Code setup and data flow from a fresh Filbert installation.

## Context
- `Sources/Providers/ClaudeCode/StatuslineHelperInstaller.swift` installs the prebuilt helper and modifies Claude Code settings.
- `Sources/ClaudeCodeStatuslineHelper/main.swift` receives status-line input and writes the usage cache.
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
- The original helper converted invalid input to an empty payload and replaced the previous cache.
- Baseline tests did not execute the generated wrapper or the actual helper from a packaged app.

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
- A successful debounce reuses data only while a usable cache exists.
- Removal or an empty cache must not make the next refresh report success without data.
- The failure cooldown and concurrent request coalescing remain unchanged.
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
- [x] Establish the baseline with the existing Claude Code tests.
- [x] Trace binary discovery, installation, status-line input, cache creation, and the app state.
- [x] Exercise a temporary installation with the actual helper.
- [x] Record reproduced failures and add regression tests.
- [x] Build and package the helper with the app.
- [x] Verify the executable and effective settings.
- [x] Run isolated checks on the helper from the completed DMG.
- [x] Obtain live-reset permission, make a private backup, and stop installed Filbert.
- [x] Exercise fresh installation and refresh through the real development app state model and installed Claude CLI.
- [x] Verify cache-error recovery and removal/reinstall in the same app session.
- [x] Restore the original current files and attempt to restart installed Filbert.
- [x] Resolve the installed local build's Sparkle loader failure and restart it.
- [ ] Verify actual menu-bar actions and a normal interactive Claude Code session.
- [ ] Verify installation on a clean Mac without Command Line Tools.

## Verification

### Live environment and results
- Environment: macOS 27, Swift 6.4, Apple Silicon, Claude Code 2.1.280.
- The user authorized removal of current and legacy Filbert Claude Code artifacts.
- A private backup retained the original files before removal.
- The test used the real installer and `QuotaViewModel`, with an isolated preference suite that enabled only Claude Code.
- Fresh installation reached the configured state without an old usage cache.
- The exact proactive command returned real usage. The app state contained 2 usage windows with a current cache timestamp.
- A deliberately malformed cache produced a safe error record.
- The app retained the previous usage and timestamp. A successful read cleared the visible error.
- An immediate removal/reinstall exposed a successful debounce without a cache.
- The repaired debounce repeated the real refresh after removal. The same-session reinstall then passed.
- The configured status-line command passed a replay with rate-limit values from the real CLI refresh.
- The replay did not establish that an interactive Claude Code session invoked the helper.
- The replay restored the real cache bytes afterward, without a fabricated update timestamp.
- Error files had mode `0600`. The log directory had mode `0700`.
- Error records excluded the malformed input marker. Successful operations did not add routine records.
- Original current settings, helper, and cache bytes and permissions were restored and verified.
- Legacy `ai-usage` artifacts and old per-invocation helper logs remained removed.
- Restart of installed Filbert failed before app startup. The loader rejected the Sparkle framework signature.
- The installed local build reported version `0.0.0`, with ad-hoc signing and Hardened Runtime.
- Both app and framework signatures passed on-disk verification. Runtime library acceptance remained a failure.
- A subsequent private-copy experiment confirmed that a host-only library-validation exception permits local startup.
- The installed app was backed up and re-signed with that local exception. It restarted successfully.
- The permanent packaging repair is tracked separately (ci 06).
- Authentication and project data were not removed.

### Packaged verification
- The ad-hoc-signed DMG passed nested signature and resource checks.
- The helper from the completed DMG created a first cache.
- Invalid helper input retained the good cache and produced a private error record.
- Normal Finder decoration failed because the generated image remained busy.
- Verification succeeded with a temporary `create-dmg --skip-jenkins` wrapper.
- The wrapper changed only the validation environment. Production packaging code remained unchanged.
- App launch remained disabled during packaged checks.
- Developer ID signing, notarization, clean-Mac installation, and GUI interaction remain separate verification gates.
- Signature verification alone did not establish that the ad-hoc build could launch with its Sparkle framework.
- After the local signing repair, a newly built DMG passed the actual launch check with a `.app` verification copy (ci 06).
- Persistent provider, refresh, and updater preferences remained unchanged during that launch.

### Live regression
- `ClaudeCodeRefresher` retained a successful debounce after helper removal deleted the cache.
- The next immediate refresh returned success without a new request or cache.
- Successful debounce now requires a populated window, consistent with quota mapping.
- Missing, empty, malformed, or unreadable cache data triggers a repair attempt.
- Cache read failures retain their safe diagnostic records.
- Eight isolated tests cover repair, ordinary debounce, failure cooldown, and concurrent callers.
- Final validation passed SwiftFormat, SwiftLint, debug and release builds, and all 560 tests.

## Risks
- A live reset affects the installed app because development and installed builds share the same paths.
- Claude Code authentication or a subscription without usage windows can limit live verification.
- A proactive Claude Code command can contact the provider or consume usage.
- Status-line command changes can damage a user's existing integration if input and shell quoting are incorrect.
- A packaged helper must retain executable permissions and comply with release signing requirements.
- A test on a development Mac with Xcode does not prove that installation works without Command Line Tools.

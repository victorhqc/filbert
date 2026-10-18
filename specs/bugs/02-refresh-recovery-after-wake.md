## Objective

Make Filbert recover by itself after wake or a network outage, let the user
retry a failed refresh at any time, and log enough detail to diagnose a failed
fetch.

## Context

- **Reported bug.** After the Mac wakes, a provider shows a warning, and
  Refresh and Retry do nothing. Only a relaunch recovers. The user runs Smart
  mode with a 5-minute slow interval. The error log shows only
  `fetch-quota` / `operation-failed` records for `openai-codex`, `deepseek`,
  and `zai`, with no cause. The overnight failures match the dark wakes that
  `pmset -g log` shows about every 15 minutes.
- `Sources/App/QuotaViewModel+SmartRefresh.swift` — after any failure in Smart
  mode, `recordSmartFailure` sets `smartRefreshNotBefore` to the slow interval
  from now. `isWithinSmartSafetyDeadline` treats this scheduler hold the same
  as the provider's `ProviderRetryGate`.
- `Sources/App/QuotaViewModel+Fetch.swift` — `manualRefresh` and
  `performFetch` return without feedback during that hold. A relaunch clears
  the hold, so the relaunch is the only recovery.
- `Sources/App/QuotaView.swift` — the Refresh button and the error panel's
  Retry button stay enabled during the hold, so a click looks broken.
- `Sources/App/QuotaViewModel+Activity.swift` — the only wake handler. It
  resets activity and forecast state but does not schedule a refresh. A
  timer that comes due during sleep fires at wake, before Wi-Fi returns. That
  request fails and starts a new hold.
- `Sources/App/QuotaViewModel+Lifecycle.swift` — `updateAutomaticRefreshScheduling`
  and `startAutoRefresh` own the automatic loop. The new connectivity gate
  goes here.
- `Sources/Core/ErrorLog.swift` — `addSafeErrorMetadata` records a domain
  and code only for top-level `NSError` values in approved domains. Provider
  errors wrap `URLError` (`DeepSeekError.network`, `ZAIError.network`,
  `OpenCodeGoError.network`, `CursorError.network`), so the useful code is
  lost. `GeminiCLIError.network` drops the `URLError`.
- `Sources/Providers/OpenAICodex/CodexAppServerClient.swift` —
  `CodexAppServerError` does not adopt `DiagnosticError`, so the log cannot
  tell a time-out from a child exit. The client also never reads the child's
  stderr pipe. A child that writes more than one pipe buffer to stderr
  blocks and then times out.
- `Sources/Core/DiagnosticError.swift`, `Sources/Core/ErrorClassification.swift`
  — the existing provider-neutral hooks for safe diagnostics and error
  classification.
- Clarifies (core 11) line "explicit user actions can replace a deadline, but
  cannot bypass the provider's safety limits". The failure hold is a scheduler
  deadline. The provider's safety limits are its retry deadline, `429`
  backoff, and minimum interval (core 11 AC8).
- Amends (core 11 AC9) for connectivity failures and (core 11 AC11) for wake.
- Keeps the quiet-refresh semantics of (ui 07) and the private log rules of
  (core 10 AC6).
- Provider modules depend only on Core (core 01). Each provider change stays
  inside its own module.

## Acceptance Criteria

### AC1: A manual refresh is not blocked by the failure hold
- **Given** a provider in Smart mode whose last automatic refresh failed, so a
  failure hold is active
- **When** the user selects Refresh in the card header, or Retry in the error
  panel
- **Then** Filbert starts one quota fetch at once, and its proactive refresh
  where applicable
- **And** the refresh icon shows progress while the request runs (ui 07)
- **And** a success clears the failure hold and the visible refresh error
- **And** a failure keeps last-known data and sets a new failure hold for the
  automatic loop only
- **And** "Keep checking" keeps its current admission rule (core 11 AC5).

### AC2: Provider safety limits still block a manual refresh, visibly
- **Given** a provider whose `ProviderRetryGate` is open for a duration
  (`429`, `Retry-After`, or provider backoff)
- **When** the popover shows that provider
- **Then** Refresh and Retry are disabled
- **And** their help text says that the provider asked Filbert to wait, with
  the coarse remaining time
- **And** the buttons become enabled when the gate expires, without a popover
  reopen
- **And** no click starts a request before the gate expires.

### AC3: A click never starts overlapping work
- **Given** a fetch is in flight for a provider
- **When** the user selects Refresh or Retry
- **Then** the button is disabled and no second request starts
- **And** each enabled click starts at most one request.

### AC4: Automatic refresh waits for the network
- **Given** an opted-in provider whose automatic refresh comes due
- **When** the network path is not satisfied
- **Then** Filbert sends no request and records no failure or failure hold
- **And** the provider's next automatic refresh runs once, when the path
  becomes satisfied
- **And** a provider retry gate still delays that request until it expires.

### AC5: Connectivity failures do not start a failure hold
- **Given** a fetch fails while the network path is not satisfied, or with a
  connectivity error (AC9)
- **When** the scheduler processes the failure
- **Then** it keeps last-known data and shows the refresh error (ui 07)
- **And** it records the failure in the error log
- **And** it sets no failure hold
- **And** the next automatic attempt runs when the path next becomes
  satisfied, or after the slow interval, whichever comes first
- **And** a failure that repeats while the path stays satisfied cannot make
  a loop faster than the slow interval.

### AC6: Wake refreshes stale and failed providers once
- **Given** the Mac posts `NSWorkspace.didWakeNotification`
- **When** Filbert handles the wake
- **Then** it sends no automatic request until the network path reports
  satisfied after the wake, or 30 seconds pass, whichever comes first
- **And** it then refreshes once each opted-in provider that is due, shows a
  refresh error, or is in an error state
- **And** it clears failure holds set before the wake for those providers
- **And** it keeps provider retry gates
- **And** providers that are not due and have no failure keep their current
  schedule
- **And** no provider gets more than one request from a single wake.

### AC7: Codex failures carry a safe cause code
- **Given** a Codex quota fetch fails
- **When** Filbert records the failure
- **Then** the record has a `causeCode` for the failure: `launch-failed`,
  `unsupported-version`, `signed-out`, `child-exited`,
  `malformed-response`, `timed-out`, or `binary-not-found`
- **And** a failure after launch also records the child's exit status (when
  known) and stderr byte count
- **And** the record never contains stderr or stdout text (core 10 AC6).

### AC8: The Codex client drains stderr
- **Given** a Codex child that writes more than 64 KiB to stderr before it
  answers
- **When** Filbert reads rate limits
- **Then** the read completes normally
- **And** Filbert counts the stderr bytes and discards them.

### AC9: Wrapped network errors expose their system code
- **Given** a provider error that wraps a `URLError` (DeepSeek, Z.ai,
  OpenCode Go, Cursor, Gemini CLI)
- **When** Filbert records the failure
- **Then** the record has `errorDomain` `NSURLErrorDomain` and the `URLError`
  code
- **And** the record never contains the failing URL, headers, or body
- **And** Core classifies these codes as connectivity errors:
  `notConnectedToInternet`, `networkConnectionLost`, `cannotFindHost`,
  `cannotConnectToHost`, `dnsLookupFailed`, `timedOut`,
  `internationalRoamingOff`, and `dataNotAllowed`
- **And** Core reads the wrapped error through a provider-neutral protocol,
  with no provider-ID branch.

### AC10: Fetch failure records state their context
- **Given** a fetch or proactive refresh fails
- **When** Filbert records the failure
- **Then** the record has `trigger`: `initial`, `manual`, `automatic`, or
  `wake`
- **And** the record has `networkPath`: `satisfied` or `unsatisfied`
- **And** both fields are fixed values that never contain user or provider
  data.

### AC11: Tests cover the reported trace
- **Given** an injected clock, sleeper, network path observer, and provider
  spies
- **When** the App, Core, and provider suites run
- **Then** they cover: manual refresh during a failure hold, manual refresh
  during a retry gate, the gate-expiry re-enable, deferral while offline,
  a connectivity failure with no hold, wake with a late network, wake with
  the 30-second cap, wake with a provider that is not due, and the
  single-request-per-wake limit
- **And** they cover the reported trace: a failure before sleep, wake, the
  network returns, one refresh, and the warning clears
- **And** they cover cause codes, the stderr drain, and wrapped `URLError`
  logging with sentinel secrets in the URL and body
- **And** tests make no real network request, Keychain mutation, child-process
  spawn of the real Codex CLI, or wall-clock sleep.

## Plan

1. **Core: network path.** Add a `NetworkPathObserving` protocol: the
   current `isSatisfied` and an async stream of changes. Add a
   `SystemNetworkPathObserver` that wraps `NWPathMonitor`. The view model
   gets the observer through its initializer, so tests can inject one. [x]
2. **Core: wrapped errors.** Add
   `public protocol UnderlyingErrorProviding: Error { var underlyingError: (any Error)? { get } }`.
   Add `isConnectivityError(_:)` to `ErrorClassification.swift`. It unwraps
   through that protocol and matches the AC9 codes. In `ErrorLog`,
   `addSafeErrorMetadata` reads the domain and code from the innermost
   approved error. [x]
3. **Core: log context.** Add optional `trigger` and `networkPath` fields to
   the log record, with fixed enum values. Old call sites keep compiling. [x]
4. **Providers.** Each module adopts `UnderlyingErrorProviding` for its own
   network case: DeepSeek, Z.ai, OpenCode Go, Cursor. Gemini CLI keeps the
   `URLError` in its `network` case. Codex adopts `DiagnosticError` for
   `CodexAppServerError` and `OpenAICodexError`. It also reports a
   `SubprocessDiagnostic` with the exit status and stderr byte count. The
   Codex client drains stderr in a child task while it reads stdout. [x]
5. **App: split the deadlines.** Replace `isWithinSmartSafetyDeadline` with
   `isWithinProviderRetryGate` and `isWithinFailureHold`. Manual refresh and
   Retry check only the retry gate. Automatic refresh checks both. "Keep
   checking" keeps its current check. `performFetch` takes the origin into
   account for admission. [x]
6. **App: button state.** The view model exposes the retry-gate end for each
   provider and refreshes that state when the gate expires. `QuotaView`
   disables Refresh and Retry and shows the localized help text. The new
   strings go in `Localizable.xcstrings`. [x]
7. **App: connectivity gate.** Add `QuotaViewModel+Connectivity.swift`. A due
   automatic refresh while offline waits for the path instead of fetching.
   `applyResults` skips the failure hold for connectivity failures (AC5). A
   path change to satisfied starts waiting providers once. [x]
8. **App: wake.** On `didWakeNotification`, set an "awaiting network" state
   that holds automatic requests until a satisfied path update arrives or the
   30-second cap ends. Then apply AC6. Pass `trigger: .wake` to the log. [x]
9. **Spec upkeep.** Add a note to (core 11) that cites this spec for the
   manual-refresh, connectivity, and wake changes. [x]
10. **Tests.** As in AC11. [x]

### Implementation notes

- **Wake settle delay.** `NWPathMonitor` can still report the pre-sleep
  status when the wake handler runs. The wake flow waits 5 seconds. If the
  path then reads satisfied, the wake refresh runs. If not, it waits for a
  satisfied update until the 30-second cap. After the cap, AC4 still defers
  each request until the path is satisfied.
- **Due providers.** A provider is due at wake if its automatic loop fired
  during the wait. That loop defers instead of fetching, so the deferred set is
  the due set. No separate "last check" clock is needed.
- **Origin.** `RefreshOrigin` gains `.wake`. It behaves as `.automatic` for
  proactive refresh, failure accounting, and the network gate.
- **Gemini CLI.** Its `network` cases keep only the `URLError.Code`. The code
  is enough for the log and the connectivity rule, and the error never holds
  the failing URL.
- **Codex diagnostics.** The client throws `CodexAppServerFailure`, which
  carries the reason and a `SubprocessDiagnostic`. It waits up to one second
  for the exit status and stderr EOF. Without an exit status it omits the
  subprocess fields and keeps the `causeCode`. `SubprocessDiagnostic` stays
  unchanged, so the Claude Code module needs no edit.
- **Error chain.** `UnderlyingErrorProviding` and `errorChain` live in
  `Sources/Core/DiagnosticError.swift`. The standalone log-writer test
  compiles that file with `ErrorLog.swift`.
- **Default network observer.** `QuotaViewModel` defaults to an
  always-satisfied observer, so tests never depend on the machine's network.
  `AppMain` passes `SystemNetworkPathObserver`.
- **Tests.** `RefreshRecoveryTests`, `WakeRefreshTests`,
  `ErrorLogContextTests`, the Codex tests in `CodexErrorLoggingTests`, and one
  wrapped-error test in each URL provider suite.

## Risks

- **More manual requests during a failure.** The user can click Refresh after
  each failure. Each click sends one request, with no overlap. Provider
  retry gates still apply, so a provider that sends `429` still holds the
  user back.
- **Dark-wake requests are still possible.** `didWakeNotification` is not
  posted for a dark wake, and a due timer can fire during one. AC4 stops
  the request when the path is not satisfied. A request can still start
  during a dark wake and fail when the Mac sleeps again. AC6 replaces that
  failure at the next full wake. Implementation must check, on hardware,
  which notifications a dark wake posts. If a reliable signal exists, a
  follow-up can skip requests during a dark wake.
- **A satisfied path does not prove DNS works.** Just after wake, a path can
  be satisfied before name resolution works. AC5 then applies: no failure
  hold, and the slow interval bounds the retry. A wake refresh can still
  show one transient error, which the next refresh clears.
- **The connectivity code set is a judgement.** `timedOut` can also mean a
  slow server. If that server is slow over a long period, AC5 retries at the
  slow interval with no hold. That rate is the same as the current
  behaviour.
- **NWPathMonitor runs for the app's lifetime.** It is cheap, but it adds a
  new long-lived system object that must start and stop with the view model.
- **Log format change.** The new fields are optional and additive. Old log
  readers ignore them.

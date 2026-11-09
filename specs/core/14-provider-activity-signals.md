## Objective

Let a provider report local activity from its own client, so Smart refresh enters fast mode without a manual refresh.

## Context

- Status: picked up 2026-11-09, awaiting review. First drafted 2026-10-23. The first adopter is OpenAI Codex, through Codex hooks. Its provider and UI specs are still unnumbered drafts, so this spec does not depend on them.
- `Sources/Core/ProviderProtocol.swift` — `AIProvider` has no way to push events to the app. `ProactiveRefreshable` is the precedent for an optional capability protocol.
- `Sources/Core/SmartRefreshPolicy.swift` — `recordActivityHint` already starts or renews the quiet window and discards hints during an inference lockout (core 11 AC8). No policy change is needed.
- `Sources/App/QuotaViewModel+SmartRefresh.swift` — `recordManualActivityHint` is the only hint source today (core 11 AC4). `startSmartExtension` shows how an action reschedules a provider within its safety deadline.
- `Sources/App/QuotaViewModel+Lifecycle.swift` — owns per-provider start, stop, enablement, and request deadlines.
- `Tests/CoreTests/SmartRefreshPolicyTests.swift` and `Tests/AppTests/AutoRefreshViewModelTests.swift` — cover hints and scheduling.
- (core 11 AC1) keeps the first baseline slow "unless the user supplies an explicit activity hint". This spec adds a second hint source: a provider signal. A signal is evidence of local work, not a usage change.
- (core 11 AC2) says a phase boundary alone does not move a request deadline. Without a reschedule, a signal during a 5-minute slow wait would change the cadence label but not the next request. AC4 below fixes this.
- Signals reach Smart refresh only. Regular mode and providers with automatic refresh off ignore them (core 11 AC4).

## Acceptance Criteria

### AC1: Activity signals are an optional provider capability

- **Given** a provider wants to report local client activity
- **When** it conforms to a new `ActivitySignaling` protocol in Core
- **Then** it exposes a stream of signal times, its signal setup status, and install and remove actions for the signal source
- **And** providers that do not conform behave exactly as today
- **And** the App never checks a provider ID to decide whether signals exist
- **And** the existing `installHelper`, `removeHelper`, and `canInstallHelper` contract is unchanged, because the popover offers "Install Helper" instead of "Retry" wherever `canInstallHelper` is true.

### AC2: Setup status is provider-owned and neutral

- **Given** a provider conforms to `ActivitySignaling`
- **When** the App asks for its signal setup status
- **Then** the provider returns one of: `notInstalled`, `awaitingFirstSignal`, `active`, or `unavailable(reason)`
- **And** `unavailable` covers cases where install cannot work, such as a missing client binary
- **And** each status other than `active` can carry a provider-supplied `DisplayText` with the next step for the user
- **And** the status reflects changes made outside Filbert, such as a user deleting the hook, at the next status read.

### AC3: A signal is an activity hint

- **Given** a provider is enabled, configured, opted into automatic refresh, and the mode is Smart
- **When** the provider emits a signal
- **Then** the App records an activity hint for that provider at the signal's receipt time
- **And** the hint follows every rule a manual hint follows in (core 11), including the quiet window, cooldown, and inference lockout
- **And** a first baseline that receives a signal enters fast mode, as a manual hint does (core 11 AC1)
- **And** in Regular mode, with automatic refresh off, or with the provider disabled, the App discards the signal and does no work.

### AC4: A signal pulls the next request forward, never past a safety limit

- **Given** a signal produces a hint under AC3
- **When** the provider's next request deadline is later than receipt time plus the effective fast interval
- **Then** the App moves that deadline to receipt time plus the effective fast interval
- **And** an earlier existing deadline stays as it is
- **And** an in-flight request absorbs the signal without a second request
- **And** the provider's minimum interval, retry gate, `429` backoff, and failure hold still apply (core 11 AC8, bugs 02 AC2)
- **And** a burst of signals produces at most one pending request.

### AC5: The signal stream follows the provider's lifecycle

- **Given** a provider conforms to `ActivitySignaling`
- **When** the provider is enabled and configured
- **Then** the App subscribes to its signal stream
- **And** the subscription does not depend on the refresh mode or the automatic refresh opt-in, because AC3 discards signals that cannot apply
- **And** disabling the provider, its setup becoming incomplete, or app shutdown cancels the subscription
- **And** re-enabling it subscribes again without duplicate subscriptions
- **And** a signal never starts a request for a provider in the `.setup` or `.unconfigured` state.

### AC6: Signals are content-free

- **Given** any provider emits signals
- **When** Core and the App handle them
- **Then** a signal carries only its time
- **And** no prompt, transcript, path, or payload from the client crosses the protocol
- **And** diagnostics may count signals but never record client data.

### AC7: Filbert's own requests never produce a signal

- **Given** a provider conforms to `ActivitySignaling`
- **When** Filbert fetches that provider's usage, by any path
- **Then** the provider emits no signal as a result of that fetch
- **And** the provider emits signals only for work the user starts in the provider's client
- **And** a test proves that a fetch alone produces no signal.

### AC8: Existing refresh behavior holds

- **Given** no provider emits a signal, including a conforming provider whose signal status is `notInstalled` or `unavailable`
- **When** Smart refresh, manual refresh, "Keep checking", and failure handling run
- **Then** their behavior and tests from (core 11) and (bugs 02) are unchanged
- **And** semantic changes and manual hints still start fast mode, so signals are an optional addition and never a requirement.

## Plan

1. [x] Add `ActivitySignaling: AIProvider` in `Sources/Core/ActivitySignaling.swift`, with an `ActivitySignalStatus` enum:
   ```swift
   public protocol ActivitySignaling: AIProvider {
       func activitySignals() -> AsyncStream<Date>
       func activitySignalStatus() async -> ActivitySignalStatus
       func installActivitySignal() async throws
       func removeActivitySignal() async throws
   }
   ```
   Each call to `activitySignals()` returns a new stream. The provider stops watching its source when that stream terminates.
2. [x] Expose the capability through `ProviderRegistry`, the same way the registry exposes `ProactiveRefreshable` today: `activitySignals(for:)`, `activitySignalStatus(for:)`, `installActivitySignal(for:)`, and `removeActivitySignal(for:)`. Non-conforming providers throw `ProviderSetupError.notSupported` or return no stream.
3. [x] Store each provider's next request deadline when `startAutoRefresh` schedules it. Today the deadline lives only inside the sleeping task, so AC4 cannot compare against it.
4. [x] In the App, add `recordActivitySignal(for:)` next to `recordManualActivityHint`. It applies the AC3 gate, calls `recordActivityHint`, then reschedules under AC4 with the existing safety checks.
5. [x] Tie the subscriptions to provider start and stop in `QuotaViewModel+Lifecycle.swift` (AC5).
6. [x] Tests: policy-level hint parity, gating per mode and enablement, deadline pull-forward, an earlier deadline kept, the in-flight case, the retry gate, the inference lockout, burst coalescing, and resubscription.

## Findings

- 2026-11-09: implemented. The full validation gate passes. The new tests passed 15 repeated runs.
- `ActivitySignaling` lives in its own file. `ProviderProtocol.swift` was already 401 lines, over the SwiftLint limit, so the protocol did not go there.
- The deadline is part of the `refreshLoops` entry (`ScheduledRefresh`). It exists exactly as long as the scheduled loop. A loop that fires now clears its entry before the eligibility check, so a stale past deadline cannot block a pull-forward.
- The App reuses `automaticRefreshInterval` for the AC4 candidate. That value already includes the minimum interval, the retry gate, and the failure hold, so a signal cannot move a request past a safety limit. During the inference lockout, the hint is discarded and the slow candidate never replaces an earlier deadline.
- Subscriptions start after setup resolves and the first fetch begins. They stop in `invalidateProviderWork` (disable, key removal, helper actions), when setup resolves to `.setup` or `.unconfigured`, and when a fetch finds the provider no longer configured. The App has no explicit shutdown hook. Process exit ends the subscription task, which terminates the provider's stream.
- AC6 is enforced by the stream type: `AsyncStream<Date>`. No diagnostics record signals.
- AC7 is a contract on conforming providers, stated on the protocol. Its test belongs with the first conforming provider, because Core has no real signal source to test.
- No user-visible change until a provider conforms. No manual check is needed for this spec.

## Risks

- **Self-triggering.** A provider whose own refresh writes to the watched source would loop. AC7 makes this a contract for every conforming provider.
- **Idle watching.** Following AC5, a provider watches its signal source in Regular mode and with automatic refresh off too. The user accepted this cost on 2026-11-09, because the source only changes when the client does work.
- **More requests.** Every signal can start fast mode. Fast mode is still bounded by the quiet window, so the cost matches a user who presses refresh at every prompt.
- **Stale status.** Status is read on demand. A hook removed while Settings is open shows as installed until the next status read. The user accepted on-demand reads on 2026-11-09. Settings does not poll the status or re-read it when its window becomes active.

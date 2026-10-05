## Objective

Improve Smart refresh for delayed allowance updates and long-running work without uncontrolled request volume or hidden quota costs.

## Context

- Status: draft for review. No production changes accompany this proposal.
- `Sources/Core/SmartRefreshPolicy.swift` — ends fast mode after 3 unchanged results, regardless of elapsed time.
- `Sources/Core/AutoRefreshPreferences.swift` — stores shared intervals and per-provider opt-in.
- `Sources/Core/ProviderProtocol.swift` — defines semantic observations but does not describe refresh cost, source freshness, or safe intervals.
- `Sources/App/QuotaViewModel+Lifecycle.swift` — schedules each provider after request completion.
- `Sources/App/QuotaViewModel+Fetch.swift` — runs proactive refresh before both manual and automatic fetches.
- `Sources/App/RefreshSettingsView.swift` — explains the current exit rule and discloses possible Claude Code quota use.
- `Sources/Providers/` — owns upstream requests, authentication, precision, cache behavior, and rate limits.
- `Tests/CoreTests/SmartRefreshPolicyTests.swift`, `Tests/CoreTests/AutoRefreshPreferencesTests.swift`, and `Tests/AppTests/AutoRefreshViewModelTests.swift` — cover transitions, preferences, and request scheduling.
- This proposal replaces the count-based exit rule (core 08 AC6, core 09 AC7).
- It extends manual-refresh behavior (core 08 AC14). Semantic comparison and provider isolation remain authoritative (core 09).
- It extends observation precision beyond the displayed precision where reliable upstream values exist (core 09 AC9).
- Fast status also affects menu-bar presentation and selection. Those consumers need regression coverage (ui 23, ui 24).

### Problem

An unchanged allowance is not proof that a job stopped. Providers can publish usage late or expose only coarse percentages.
Large allowances make small usage changes harder to detect. A long job can continue between visible allowance changes.

The current defaults allow roughly 90 seconds before fast mode ends, plus request time.
With a 10-second fast interval, that period falls to roughly 30 seconds.
Thus, a shorter interval also shortens the activity window.
A manual refresh with unchanged usage does not start fast mode.

Filbert cannot infer job completion from allowance data alone.
More requests can reduce detection delay after an upstream update. More requests cannot force the provider to publish that update.

## Acceptance Criteria

### AC1: Elapsed time replaces the unchanged-result counter

- **Given** an opted-in provider uses Smart mode
- **When** a successful result contains a semantic change as defined by (core 09)
- **Then** that provider enters fast mode and records the activity time with an injected monotonic clock
- **And** each later semantic change renews that provider's activity time, subject to AC8
- **And** unchanged results do not renew the activity time
- **And** the number of unchanged results does not determine when fast mode ends
- **And** the first successful baseline remains slow unless the user supplies an explicit activity hint.

### AC2: A quiet window and cooldown tolerate delayed updates

- **Given** the quiet window is `Q`, the fast interval is `F`, and the slow interval is `S`
- **When** the scheduler chooses the next interval after a successful result or a timer wake
- **Then** it uses `F` while elapsed time since the activity hint is less than `Q`
- **And** it uses `min(S, max(2 × F, 60 seconds))` from `Q` through less than `2 × Q`
- **And** it uses `S` at or after `2 × Q`
- **And** a semantic change during cooldown immediately restores fast mode
- **And** each boundary uses elapsed time, not the number of responses
- **And** every interval remains subject to the provider's minimum interval and retry deadline
- **And** slow mode remains the starting state and the state after cooldown.

The activity time includes semantic changes and manual hints. An explicit extension has a separate deadline.
After each completed cycle, the scheduler records the next request deadline from that completion and the then-current effective interval.
Policy-boundary timers update cadence and UI state without requests or additional sleeps.
A phase boundary alone does not move an existing request deadline.
At the request deadline, the scheduler validates eligibility and safety again before the request.
The result determines the next completion-to-start gap.
Settings edits and explicit user actions can replace a deadline, but cannot bypass the provider's safety limits.

### AC3: Quiet duration is independent of request frequency

- **Given** the user opens Refresh Settings in Smart mode
- **When** the user sets the quiet window
- **Then** the available durations are 2, 5, 10, and 15 minutes, with a default of 5 minutes
- **And** cooldown lasts one additional quiet window
- **And** the existing fast and slow interval ranges and defaults remain unchanged (core 09 AC11)
- **And** edits persist across relaunch and reschedule eligible providers without duplicate requests
- **And** invalid stored durations resolve to 5 minutes
- **And** interval edits do not create activity or restart the quiet window
- **And** duration edits evaluate the existing activity time against the new duration.

### AC4: A manual refresh supplies a bounded activity hint

- **Given** a provider is opted into Smart automatic refresh
- **When** the user requests a manual refresh
- **Then** that provider receives an activity hint even if the allowance does not change
- **And** the hint records the time of the user action, not the time that the request completes
- **And** the hint starts or renews the quiet window without inventing a usage change
- **And** an existing in-flight request absorbs the hint without a second request
- **And** a result failure follows AC9 rather than forcing another fast attempt
- **And** a manual refresh in Regular mode or with automatic refresh off does not create ongoing automatic work.

### AC5: Long jobs have an explicit, finite option

- **Given** a provider is opted into Smart automatic refresh
- **When** the user selects “Keep checking” for 15, 30, or 60 minutes
- **Then** that provider uses its effective fast interval until the selected deadline, even with unchanged allowance
- **And** the action requests an immediate refresh only when no request is in flight and the safety deadline permits it
- **And** the UI shows the remaining duration and a “Stop extension” action
- **And** Stop extension removes the explicit deadline and resumes the policy from the automatic activity time and any safety lockout
- **And** expiry also resumes that policy without resetting its activity time or safety lockout
- **And** the explicit deadline does not itself manufacture a new activity time
- **And** the UI explains that Stop extension does not disable automatic refresh
- **And** a later user selection replaces the deadline rather than adding durations
- **And** this action does not enable automatic refresh or switch modes implicitly
- **And** the deadline does not survive relaunch.

### AC6: Unknown freshness does not become false evidence

- **Given** a provider returns cached data, a debounced result, missing activity metrics, or an unknown source timestamp
- **When** Smart refresh receives the result
- **Then** cached or missing data does not supply a new activity hint merely because a request completed
- **And** identical metrics remain unchanged even when the fetch timestamp changes
- **And** a provider-known stale result neither renews the activity window nor replaces the last accepted semantic baseline
- **And** transport source alone does not decide freshness: a cache read after successful proactive refresh can contain a new accepted observation
- **And** an unknown source timestamp permits semantic comparison, but does not support a claim that the source is current
- **And** absent observations retain the last accepted comparison baseline without manufacturing a change
- **And** elapsed time can still end the activity window without proof of job completion
- **And** the UI retains last-known data and its source timestamp where available
- **And** diagnostics distinguish a network fetch, a cache read, and unknown freshness without recording payloads.

### AC7: Provider observations preserve usable precision

- **Given** an upstream response contains a finer consumption or balance value than the rounded display percentage
- **When** the provider constructs its activity observation
- **Then** the observation preserves that consumption precision without parsing localized display text
- **And** equivalent numeric encodings compare equally
- **And** allowances, reset dates, and other configuration values do not masquerade as consumption
- **And** if the upstream response exposes only coarse percentages, the provider does not invent finer values
- **And** fixtures cover delayed updates, small changes under a large allowance, and percentage-only responses
- **And** Core contains no provider-specific tolerance or field-name rule.

### AC8: Cost and request safety are provider-owned

- **Given** a registered provider participates in automatic refresh
- **When** Core or App requests its refresh characteristics
- **Then** the provider supplies a neutral description of its request path and quota-cost evidence
- **And** the cost evidence distinguishes documented non-consumption, possible consumption, and unknown cost
- **And** absence of a billing statement never becomes “free”
- **And** the provider supplies any verified minimum interval and retry deadline
- **And** automatic, manual, and “Keep checking” paths obey these limits without overlapping work
- **And** `429`, `Retry-After`, and exponential backoff take precedence over every cadence and user hint
- **And** a refresh that can invoke inference has a 10-minute maximum automatic fast episode, even if observations continue to change
- **And** the episode starts on entry to automatic fast mode and its start time never renews with activity
- **And** at that cap, the provider clears the automatic activity time and starts a separate lockout of `Q` minutes
- **And** during lockout, the provider uses slow cadence and discards automatic or manual activity hints while still updating accepted semantic baselines
- **And** a failure or explicit extension cannot clear, shorten, or restart that lockout
- **And** an explicit extension still records the underlying episode cap and lockout, even while it overrides their cadence
- **And** after lockout ends, only a new activity hint can start another automatic fast episode
- **And** only an explicit “Keep checking” selection can extend that episode, after a visible cost disclosure
- **And** adding a provider requires no provider-ID branch in Core, App, or another provider.

The cap limits time in the automatic fast phase. It does not guarantee a lower request rate when `S` equals `F`.
The UI must show this limitation when the effective intervals are equal.

### AC9: Failures do not trigger a fast retry loop

- **Given** proactive refresh or quota fetch fails
- **When** the scheduler processes the failure
- **Then** it preserves the last successful semantic baseline and last-known UI data
- **And** it clears the automatic activity window and explicit “Keep checking” deadline for that provider
- **And** it schedules no earlier than the slow interval or the provider's retry deadline, whichever is later
- **And** it exposes the failure without claiming that the job stopped
- **And** an authentication or setup failure pauses requests until the provider is ready
- **And** a new user action cannot bypass backoff or authentication requirements.

Each refresh cycle includes proactive refresh and quota fetch where applicable.
A proactive failure remains the cycle failure even if a later local cache read succeeds.
After that failure, the pipeline can read local last-known data but must not start an outbound stage before its safety deadline.
Quota-fetch admission therefore applies independently of proactive-refresh admission.

### AC10: Settings explain the effective behavior and cost

- **Given** the user views refresh controls or a provider's current refresh status
- **When** the UI renders
- **Then** it describes the fast interval, quiet window, cooldown interval, and slow interval
- **And** it distinguishes recent activity from the explicit “Keep checking” deadline
- **And** it shows the effective interval when a provider limit overrides the shared interval
- **And** it discloses possible or unknown quota cost before opt-in and before an explicit extension
- **And** it retains the Claude Code command disclosure until a separate approved change removes that command
- **And** it never equates a non-inference request with unlimited or unthrottled access
- **And** fast status means the policy selected fast cadence, not proof that an LLM is active
- **And** cooldown does not emit a new fast-entry event for menu-bar selection
- **And** manual hints and explicit extensions intentionally retain the existing one-time fast-entry score boost (ui 24 AC4)
- **And** renewing an active window or extension does not award that boost again
- **And** all controls and status text support localization and accessibility.

### AC11: Lifecycle and provider isolation remain predictable

- **Given** providers have independent windows, deadlines, requests, and baselines
- **When** settings, eligibility, sleep, wake, or app lifecycle change
- **Then** one provider's activity does not renew another provider's window
- **And** automatic refresh remains off by default and Regular mode retains its fixed cadence
- **And** provider safety limits and per-stage admission also apply in Regular mode
- **And** disable, credential change, removal, or a mode switch clears that provider's temporary activity state
- **And** app relaunch starts with slow baselines and no explicit deadline
- **And** sleep produces no requests or catch-up burst
- **And** wake expires windows according to elapsed time, including time asleep, before scheduling the next request
- **And** an expired or cancelled request cannot restore old activity state.

### AC12: Tests and traces cover the reported failures

- **Given** an injected clock, sleeper, provider spies, and recorded synthetic observations
- **When** the Core, App, and provider regression suites run
- **Then** they cover the traces in the Plan with no authenticated network request, Keychain mutation, child-process spawn, or real sleep
- **And** they cover exact duration boundaries, backoff, cache reads, failures, opt-out, manual coalescing, explicit expiry, sleep, and late-result rejection
- **And** changing `F` from 30 to 10 seconds does not shorten the quiet window
- **And** safe diagnostics report trigger category, cadence, freshness category, and deadline changes without metric values, credentials, or account identifiers
- **And** menu-bar activity scores remain presentation state, not input to the refresh policy.

## Plan

### Options and recommendation

| Option | Benefit | Cost and limitation | Recommendation |
| --- | --- | --- | --- |
| Increase the unchanged-check count | Small change with longer fast episodes | Still ties duration to interval and request latency. No evidence of job completion. | Reject as the main rule. |
| Use a quiet-time window only | Predictable duration despite interval edits | Ends fast mode during a job with no visible usage changes beyond the window. | Use as the automatic foundation. |
| Add a cooldown cadence | Detects late changes sooner than slow cadence | Adds requests and one policy phase. Still cannot prove activity. | Use one derived interval, not another slider. |
| Poll at a fixed fast interval | No heuristic exit during long work | Constant request load, possible quota use, battery cost, and rate-limit exposure. | Offer only as the finite “Keep checking” action. |
| Detect local processes or session files | Can signal activity before allowance changes | A process can be idle. Work can run elsewhere. Requires provider-specific integration and privacy review. | Defer to a separate provider-owned capability. |
| Learn cadence from recent deltas | Could adapt to repeated update patterns | Coarse or delayed data biases the estimate. Requires evidence and more state. | Defer until traces show a stable benefit. |
| Poll sooner near quota exhaustion | Can reduce uncertainty near a limit | Low balance does not prove activity. Coarse data still applies. | Defer. Do not spend remaining quota merely because it is low. |

The recommendation is a quiet window, one cooldown phase, and an explicit finite extension.
The durations are proposed defaults, not measured provider latency guarantees.
The user can choose a longer quiet window without a shorter request interval.

### Safety and cost findings

Research date: 2026-10-05. Evidence comes from the current Filbert code and public documentation.
No provider CLI, authenticated request, or account experiment ran during this research.

Research must distinguish allowance cost from HTTP request limits and local process cost.
A successful status request does not prove that the request has no billing effect.
The actual Filbert refresh path matters more than an unrelated provider API.

| Provider | Current automatic or manual cycle | Allowance-cost evidence | Freshness and request limits |
| --- | --- | --- | --- |
| Claude Code | One bounded `claude` process with Haiku, one turn, JSON output, and `-p "/usage"`, then a local cache read. The 10-second debounce can reuse a result. | Possible consumption. Anthropic describes `-p` as a non-interactive prompt. No reviewed documentation guarantees that this exact command avoids inference or quota use. | Cache has `written_at`; Filbert marks it stale after one hour. Parsed percentages can be integer-only. No verified polling interval. |
| Cursor | One `POST` to `DashboardService/GetCurrentPeriodUsage`. An expiring token adds an OAuth refresh request. | Account-usage RPC, not an inference request. Billing effect remains unknown. The endpoint is undocumented. | No upstream freshness guarantee found. Filbert's `429` backoff starts at 5 minutes and doubles to one hour. |
| DeepSeek | One `GET /user/balance`. | Officially documented balance read. No inference request. The documentation does not explicitly guarantee zero charge or quota consumption. | No numeric polling limit or freshness guarantee found. General error documentation describes `429` for excessive requests. |
| Gemini CLI | Two `POST` requests: `loadCodeAssist`, then `retrieveUserQuota`. An expiring token adds an OAuth refresh request. | Account, project, and quota operations, not generation requests. Quota-read billing effect remains unknown. | No verified quota-read interval or freshness guarantee. The individual-account service status requires separate review. |
| OpenAI Codex | One `codex app-server --stdio` process, protocol initialization, then `account/rateLimits/read`. Upstream HTTP count depends on the installed CLI version. | OpenAI documents a rate-limit read without a message. No inference request is apparent. No zero-charge or unlimited-polling guarantee found. | CLI owns authentication and upstream calls. Newer versions can fetch reset-credit details as well as usage. No verified polling interval. |
| OpenCode Go | One `GET /zen/go/v1/usage`. | Usage read, not inference. Public token-pricing documentation does not establish quota-read cost. | No published quota-read freshness or interval found. Traffic is abuse-monitored. Filbert's `429` backoff starts at 5 minutes and caps at one hour. |
| z.ai | Two `GET` requests: `/api/monitor/usage/quota/limit`, then best-effort `/api/biz/subscription/list`. | Neither request asks for inference. Exact endpoint billing and polling contracts remain unknown. | No verified quota-read freshness or polling interval. Coding Plan policy restricts supported tools, but does not explain third-party status reads. |

“No inference request” describes the request shape. It is not a provider promise that the operation is free.
No reviewed source provides a safe fast interval for these exact allowance paths.
Model-generation rate limits do not establish quota-read limits.
Unknown limits remain unknown. Implementation must not invent a verified provider floor.

#### Source record

- Claude Code: [Filbert refresh and cache path](../../Sources/Providers/ClaudeCode/ClaudeCodeProvider.swift#L154-L178), [process arguments](../../Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift#L83-L93), [debounce](../../Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift#L139-L159), and [percentage parser](../../Sources/Providers/ClaudeCode/ClaudeCodeRefresher+Parse.swift#L47-L59). Public evidence: [programmatic CLI](https://code.claude.com/docs/en/headless) and [usage costs](https://code.claude.com/docs/en/costs).
- Cursor: [usage request](../../Sources/Providers/Cursor/CursorProvider.swift#L86-L112), [conditional token refresh](../../Sources/Providers/Cursor/CursorTokenStore.swift#L160-L223), and [backoff](../../Sources/Providers/Cursor/CursorRateLimitBackoff.swift#L13-L40). Public evidence: [CLI authentication](https://cursor.com/docs/cli/reference/authentication), not a contract for the dashboard RPC.
- DeepSeek: [Filbert balance request](../../Sources/Providers/DeepSeek/DeepSeekProvider.swift#L106-L155). Public evidence: [balance endpoint](https://api-docs.deepseek.com/api/get-user-balance/) and [error codes](https://api-docs.deepseek.com/quick_start/error_codes).
- Gemini CLI: [Filbert fetch sequence](../../Sources/Providers/GeminiCLI/GeminiCLIProvider.swift#L194-L231) and [token refresh](../../Sources/Providers/GeminiCLI/GeminiCLIAuth.swift#L101-L123). Public evidence: [Google CLI source](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/code_assist/server.ts) and [service status](https://docs.cloud.google.com/gemini/docs/codeassist/overview).
- OpenAI Codex: [Filbert process launch](../../Sources/Providers/OpenAICodex/CodexAppServerClient.swift#L62-L70) and [RPC sequence](../../Sources/Providers/OpenAICodex/CodexAppServerClient.swift#L124-L178). Public evidence: [app-server protocol](https://developers.openai.com/codex/app-server.md), [upstream backend paths](https://github.com/openai/codex/blob/main/codex-rs/backend-client/src/client/rate_limit_resets.rs), and [reset-detail change](https://github.com/openai/codex/pull/30395). Upstream links describe the researched version, not every installed CLI.
- OpenCode Go: [Filbert fetch](../../Sources/Providers/OpenCodeGo/OpenCodeGoProvider.swift#L148-L156), [endpoint](../../Sources/Providers/OpenCodeGo/OpenCodeGoProvider.swift#L238-L255), and [backoff](../../Sources/Providers/OpenCodeGo/OpenCodeGoProvider.swift#L93-L127). Public evidence: [Go usage policy](https://opencode.ai/docs/go/).
- z.ai: [Filbert request sequence](../../Sources/Providers/ZAI/ZAIProvider.swift#L88-L160). Public evidence: [Coding Plan usage policy](https://docs.z.ai/devpack/usage-policy). Billing-history delay is not a freshness guarantee for the quota endpoint.

Google's current notice says Gemini CLI stopped serving individual, Google AI Pro, and Google AI Ultra requests on June 18, 2026.
That notice does not establish whether Filbert's private quota calls still work.
Support for that account path requires separate provider review, not more frequent requests.

#### Additional options before more requests

- Investigate a supported, non-inference Claude allowance read as a separate provider change. Do not substitute an undocumented OAuth endpoint without a policy review.
- Preserve passive Claude statusline updates as a source of new observations. Passive updates avoid an extra prompt, but stop when no session publishes data.
- Consider a slower cache for z.ai subscription metadata. Fast allowance checks currently repeat the metadata request even when the subscription is unchanged.
- Consider reuse of Gemini's resolved project within the same credential context. Project or authentication changes must invalidate that cache.
- Defer a persistent Codex app-server connection unless process overhead is material. It introduces process lifecycle and reconnection state.
- Audit provider precision and field semantics first. The z.ai observation fallback can select `usage`, which represents an allowance in some response shapes.

These provider changes are candidates, not implicit additions to this implementation.
They require fixtures and separate approval under the provider's own spec.

No authenticated experiment or inference request is authorized by this document.
Any later account experiment requires explicit permission and cannot prove non-consumption from a coarse percentage alone.
For Claude, a permitted experiment can inspect usage and cost fields in the existing JSON result without an additional prompt.
Those fields remain local. Their absence does not prove zero subscription consumption.

### Proposed policy examples

The following traces use `F = 30 seconds`, `S = 5 minutes`, and `Q = 5 minutes`.
Request duration can lengthen the gaps. Filbert never schedules overlapping work to match a theoretical frequency.

| Trace | Expected behavior |
| --- | --- |
| Usage changes at `t = 0`, then remains equal | Fast until 5 minutes, 60-second cooldown until 10 minutes, then slow. |
| Usage changes at `t = 0` and `t = 4 minutes` | The second change renews fast mode until 9 minutes. |
| A delayed update appears at `t = 7 minutes` | A cooldown request detects the update and restores fast mode. |
| A manual result at `t = 0` is unchanged | The user action starts the window. No additional manual click is necessary during that window. |
| A 30-minute job publishes no intermediate usage | Automatic inference cannot identify the job. A 30-minute explicit deadline maintains fast checks until expiry. |
| The job continues beyond the explicit deadline | Filbert resumes the automatic policy. It does not silently extend the deadline. |
| Only a cache timestamp changes | No semantic activity or window renewal. |
| Fresh value `10`, known-stale value `9`, then fresh value `10` | The stale result does not replace the baseline. The final result is unchanged. |
| A fresh cache read follows proactive refresh | New semantic values can renew the activity time. Cache transport alone does not suppress activity. |
| Fine credit use changes but the display percentage stays equal | The provider's canonical observation detects the change. |
| A request receives `429` during an explicit deadline | The provider's backoff wins. The failure clears the extension and preserves last-known quota. |
| A potentially inferential refresh keeps changing usage | The automatic episode ends at 10 minutes. A separate 5-minute lockout prevents renewal from its own observations. |
| An extension ends during that lockout | The provider resumes slow cadence until lockout ends, not automatic fast cadence. |
| Stop extension follows a recent manual hint without lockout | The normal quiet window can remain fast. Stop extension does not disable automatic refresh. |
| A completion occurs just before a phase boundary | The phase timer updates status. One already-scheduled request remains due; its completion uses the new cadence. |
| `S = F = 60 seconds` | Phases can have the same interval. The UI does not imply a higher request rate. |

At negligible request duration, continuous 30-second refresh allows at most 120 cycles per hour.
Five-minute refresh allows at most 12 cycles per hour.
One quiet window and cooldown allow approximately 15 subsequent cycles across 10 minutes with these defaults.
The initial request is separate. Each cycle can contain multiple HTTP requests or a child process.
These figures are request counts, not monetary or token estimates.

| Current path | Approximate outbound volume at 30 seconds | At 5 minutes |
| --- | --- | --- |
| One-request HTTP cycle | Up to 120 requests per hour | Up to 12 requests per hour |
| z.ai or Gemini two-request cycle | Up to 240 requests per hour | Up to 24 requests per hour |
| Conditional OAuth refresh | Additional requests when required | Additional requests when required |
| Claude Code | Up to 120 process attempts per hour; actual spawns depend on debounce and duration | Up to 12 process attempts per hour |
| OpenAI Codex | Up to 120 process cycles per hour; HTTP count depends on CLI version | Up to 12 process cycles per hour |

The proposed policy does not lower the shared fast interval.
The larger opportunity is a longer useful activity window with fewer unnecessary metadata requests.
Any shorter provider-specific interval requires stronger evidence than the absence of documented charges.

### Implementation sequence after review

1. Confirm the policy, proposed durations, and acceptable request cost with the user.
2. Record provider evidence, freshness, precision, and rate-limit gaps with fixtures for each actual refresh path.
3. Extend the provider-neutral contract for verified refresh characteristics and source freshness where available.
4. Replace the counter with clock-driven per-provider state and explicit activity hints.
5. Integrate the policy through the existing completion-driven request pipeline.
6. Add the quiet-window control, explicit deadline, effective status, and provider-owned disclosures.
7. Run deterministic traces and existing provider, refresh, and menu-bar suites.
8. Compare synthetic request counts before any user-authorized real-account evaluation.

## Risks

- Longer windows increase requests even when the user stops work immediately.
- A refresh that invokes inference can consume allowance and cause its own apparent activity. The automatic episode cap limits this feedback.
- An unknown billing contract is not a reason to assume zero cost.
- Upstream snapshots can remain unchanged longer than every proposed duration.
- Explicit extensions are user intent, not evidence that a process is active.
- A transient failure clears an extension. The UI must make this visible.
- Coarse percentage-only responses cannot reveal small usage changes, regardless of request frequency.
- New provider contracts and retry enforcement can reveal missing guarantees in existing providers.
- Undocumented endpoints and provider usage policies can constrain third-party status reads even when those reads do not invoke inference.
- The researched Gemini individual-account path has a support warning. Refresh frequency cannot repair unsupported service behavior.
- Longer fast status can affect automatic menu-bar selection. Existing scoring must not feed back into refresh scheduling.
- Clock behavior across system sleep needs explicit tests. Wall-clock edits must not renew activity windows.
- The proposed defaults require user review. They are not results from a production benchmark.

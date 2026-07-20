## Objective

Stop swapping the popover to a full-height loading view on manual refresh;
keep the last-known quota visible and signal progress by animating the
Refresh icon instead.

## Context

- `Sources/App/QuotaViewModel.swift` — `manualRefresh(for:)` currently calls
  `setState(.loading, for: providerId)` then `refreshDerived()`. That flips the
  section to `.loading`, which `QuotaView.loadingContent` renders as a
  ProgressView in place of the quota. The popover's intrinsic height collapses
  to the loading row's height and snaps back when data returns — visible jump.
- `Sources/App/QuotaView.swift` — `providerSection(providerId:state:)` switches
  on `ProviderState`; `.loading` discards the previously rendered quota.
  `quotaContent(_:providerId:)` owns the Refresh button, whose icon is a static
  `arrow.clockwise` SF Symbol today (ui 04 AC5).
- `Sources/Core/ProviderProtocol.swift` — `ProviderState` stays as-is. The new
  "refreshing, but keep showing data" signal lives in the view model, not in
  `ProviderState`, so Core and the providers are untouched.
- Builds on (ui 01 AC5), (ui 04 AC5), (providers 03 AC3). The initial app-launch
  fetch and first-ever fetch per provider (where there is genuinely no data to
  show) still use `.loading` — that case is correct and stays as-is.

## Acceptance Criteria

### AC1: Manual refresh never swaps an loaded section to a loading view
- **Given** a provider section currently in `.loaded(quota)` (or `.error`)
- **When** the user clicks the Refresh control
- **Then** the section continues to render the existing quota (or error) for
  the entire duration of the refresh — no ProgressView, no height collapse

### AC2: First-ever fetch still shows a loading view
- **Given** a provider section is in `.loading` because no quota has ever been
  fetched (e.g. just configured, or app launch with a configured provider)
- **When** that section renders
- **Then** it shows the existing ProgressView loading row — unchanged from
  (ui 01 AC6)

### AC3: Refresh icon animates while a refresh is in flight
- **Given** a manual refresh has started for a provider
- **When** the Refresh icon renders
- **Then** the `arrow.clockwise` glyph rotates continuously for the duration of
  the refresh and stops when the refresh completes (success or failure)

### AC4: Refresh control is disabled while a refresh is in flight
- **Given** a refresh is already running for a provider
- **When** the user clicks the Refresh icon again
- **Then** the click is ignored — no second concurrent fetch is scheduled
  (preserves the click-debounce guarantee from providers 02 AC9)

### AC5: UI updates only when the new quota arrives
- **Given** a manual refresh completes successfully
- **When** the registry returns the new `ProviderQuota`
- **Then** the section transitions from `.loaded(old)` to `.loaded(new)` (or
  from `.error` to `.loaded`) and SwiftUI re-renders the new values — no
  intermediate loading state is visible

### AC6: Failed refresh retains last-known data with a non-blocking indicator
- **Given** a manual refresh fails AND the section currently shows a
  `.loaded(quota)` (i.e. there is last-known data to retain)
- **When** the registry returns a `.failure` for a non-Keychain error
- **Then** the section continues to render the existing `ProviderQuota` — no
  swap to `.error`, no height collapse — AND a small non-blocking error
  indicator appears next to the last-updated label surfacing the failure.
  The indicator clears on the next successful refresh
- **And** if the failure is a `KeychainError` (key was deleted externally),
  the section still transitions to `.unconfigured` — genuine state change,
  nothing to retain
- **And** if the failure happens when the section is **not** `.loaded`
  (e.g. first-ever fetch, or section was already in `.error`), the section
  still transitions to `.error(message)` per (ui 01 AC6) — no last-known
  data exists to retain

### AC7: Auto-refresh uses the same quiet path AND the same retain-on-error
rule
- **Given** the 5-minute auto-refresh loop fires for a provider in `.loaded`
- **When** `fetchQuota(for:)` runs
- **Then** it follows the same quiet-refresh semantics as manual refresh — no
  swap to `.loading`, icon animates if the popover happens to be open, and a
  failure retains last-known data with the non-blocking indicator (AC6)

### AC8: Orthogonality — providers and Core are untouched
- **Given** this change lands
- **When** `git diff Sources/Core Sources/Providers` is inspected
- **Then** the diff is empty — `ProviderState`, `ProviderRegistry`,
  `ProactiveRefreshable`, ZAI, and Claude Code are all unchanged

## Plan

View-model + view changes; Core and providers untouched.

1. **New view-model state** — add per-provider refresh state to
   `QuotaViewModel`:
   - `private(set) var isRefreshing: [String: Bool] = [:]`
   - `private(set) var refreshErrors: [String: String] = [:]`
   - Mutate them through `setRefreshing(_:for:)` and
     `setRefreshError(_:for:)` helpers that copy-write the dictionary (same
     pattern as `setState(_:for:)` — @Observable needs the setter to fire).
2. **Quiet path in `manualRefresh(for:)`** — when the current state is
   `.loaded` or `.error`, do **not** call `setState(.loading, …)`. Set
   `isRefreshing[id] = true` instead, then run the existing
   proactive-refresh + `performFetch` pipeline.
3. **Quiet path in `fetchQuota(for:)`** (auto-refresh) — same rule: if state is
   `.loaded` or `.error`, keep the state and flip `isRefreshing[id] = true`
   instead of swapping to `.loading`.
4. **Branch in `applyResults(_:)` on retain-vs-replace** — for every returned
   id:
   - On `.success`: set `isRefreshing[id] = false`, clear any existing
     `refreshErrors[id]`, and transition to `.loaded(quota)`.
   - On `.failure(KeychainError)`: set `isRefreshing[id] = false`, transition
     to `.unconfigured`, stop auto-refresh (existing behavior).
   - On `.failure(other)` with current state `.loaded`: set
     `isRefreshing[id] = false`, keep state as `.loaded`, write
     `refreshErrors[id] = message` so the view can render the non-blocking
     indicator (AC6).
   - On `.failure(other)` with any other current state: set
     `isRefreshing[id] = false`, transition to `.error(message)` (AC6
     fall-through).
5. **Refresh control in `QuotaView.swift`** — bind the `arrow.clockwise` glyph
   to `viewModel.isRefreshing[providerId] ?? false`. While true, rotate
   continuously using `.repeatForever(autoreverses: false)`; stop on false.
   Replace `.disabled(ifLoadingState(providerId))` with
   `.disabled(viewModel.isRefreshing[providerId] ?? false)` so the click
   debounce follows the new flag (AC4).
6. **Non-blocking error indicator in `QuotaView.swift`** — in the
   `quotaContent(_:providerId:)` footer, render a small yellow
   `exclamationmark.triangle.fill` glyph with `.help(message)` when
   `viewModel.refreshErrors[providerId]` is non-nil. The glyph sits next to
   the last-updated label; it adds minimal height (one line, .caption2 size).
7. **Leave `ifLoadingState(_:)` in place** only if still referenced elsewhere
   (it gates the initial-load ProgressView at AC2). If nothing else uses it,
   delete it.

No changes to `ProviderProtocol`, `ProviderState`, the registry, ZAI, or
Claude Code.

## Risks

- SwiftUI's `repeatForever` animation can leave the icon mid-rotation when the
  flag flips back to false. If this is observed during implementation, fix it
  then; the `value:`-driven implicit animation is the first thing to try.
- `applyResults(_:)` runs on the **fetchAll** path, which returns one result
  per registered provider. Clearing `isRefreshing[id]` for every returned id
  is correct today (only one manual refresh runs at a time per provider), but
  if a future spec introduces staggered per-provider fetches, the
  clear-on-each-result rule must be revisited.
- The popover's height still changes when a quota arrives with a different
  number of lines than before. Out of scope — the user's complaint is the
  loading-screen jump, not legitimate data-driven height changes.
- Retaining stale data on error means the user could be looking at numbers
  that are hours old without realizing it. Mitigation: the non-blocking
  indicator (yellow triangle + tooltip) is always visible while an error is
  pending, and the existing `lastUpdated` label already shows the relative
  age. If the user clears the error implicitly by triggering another
  successful refresh, the indicator disappears.
- The retain-on-error rule changes a long-standing behavior: today, a failed
  refresh visibly swaps the section to the error view; after this spec, the
  swap is suppressed when last-known data exists. Users who relied on the
  swap as a signal that "something went wrong" will see a subtler signal
  instead. The tooltip carries the full message for anyone who hovers.

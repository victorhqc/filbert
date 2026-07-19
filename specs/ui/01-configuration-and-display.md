## Objective

Let the user configure their z.ai API key and see live quota data in the menu-bar
popover.

## Context

- `Sources/App/AppMain.swift` — the `MenuBarExtra` popover; currently a static
  placeholder + Quit. Gains configuration entry, live rendering, and refresh.
- `Sources/Core/Keychain.swift` — key storage, service `ai-usage`, account
  `provider-zai` (core 01 AC3).
- `Sources/Core/ProviderRegistry.swift` — `fetchAll()` drives the provider
  (core 01 AC4).
- `Sources/Providers/ZAI/ZAIProvider.swift` — the live query (providers 01).
- Scope: **z.ai only**. The settings surface holds one key. Generalizing to
  multiple providers is deferred until a second provider lands.
- Reset countdowns use the shared `QuotaFormatting` helper introduced in
  (providers 01) so the per-line countdowns and the headline share one identical,
  localized format.
- i18n: all UI chrome (prompts, buttons, state messages) uses `String(localized:)`
  against the String Catalog (providers 01) — no English literals in views.

## Acceptance Criteria

### AC1: Enter and save the API key
- **Given** the popover is open
- **When** the user pastes a key into the settings field and saves
- **Then** the key is written to Keychain under `provider-zai` (core 01 AC3) and
  the popover switches to showing quota data

### AC2: Clear the API key
- **Given** a saved key
- **When** the user clears it
- **Then** the Keychain item for `provider-zai` is deleted and the popover
  returns to the unconfigured prompt

### AC3: Unconfigured prompt
- **Given** no key stored for `provider-zai`
- **When** the popover opens
- **Then** it shows a "configure your z.ai key" prompt with the entry field —
  no fetch is attempted

### AC4: Render live quota
- **Given** a stored key and a successful fetch (providers 01)
- **When** the popover displays the result
- **Then** it shows the `headline`, and each `UsageLine` as a row with its
  label, percentage, a reset countdown rendered from `resetDate` via the shared
  `QuotaFormatting` helper (providers 01) — identical format to the headline —
  and any `UsageDetail` rows; nil fields are omitted, not shown blank

### AC5: Manual and automatic refresh
- **Given** a configured provider
- **When** the user clicks Refresh, or 5 minutes elapse
- **Then** `fetchQuota` runs again and the popover updates with the new data and
  a "last updated" indicator from `lastUpdated`

### AC6: Loading and error states
- **Given** a fetch in flight or a failed fetch (providers 01 AC6)
- **When** the popover renders
- **Then** an in-flight fetch shows a loading indicator, and a failure shows the
  error (distinguishing an auth failure — "check your key" — from a transient
  network failure) with a Retry affordance, never a blank or stale-as-fresh view

### AC7: UI chrome is localized
- **Given** the app running under a non-English locale
- **When** any popover text renders (unconfigured prompt, buttons, state and
  error messages, "last updated")
- **Then** it appears in the active language via `String(localized:)` — no
  hard-coded English literals in the views

## Plan

Introduce an `@Observable` view model that owns the current
`Result<ProviderQuota, Error>`, the loading flag, and a `Timer`/`Task`-based
5-minute refresh loop; it reads the key from Keychain and calls the provider
through `ProviderRegistry` (core 01 AC4). The popover switches on three states:
unconfigured (AC3), loading (AC6), loaded/error (AC4/AC6). Keep the settings
field and the quota view as separate SwiftUI subviews so the multi-provider
generalization later is additive. Quit button stays.

## Risks

- Storing/clearing keys hits the real Keychain; a first save may trigger a macOS
  keychain-access prompt — expected, not a bug.
- The 5-minute timer must not fire while unconfigured or stack duplicate
  in-flight fetches; the view model gates on state.
- Popover dismissal shouldn't cancel an in-flight refresh mid-write; the view
  model, not the view, owns the fetch task.

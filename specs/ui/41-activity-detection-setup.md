## Objective

Show each provider's activity-detection setup in Settings, and give the popover a button that opens Settings at that provider when the user needs to act.

## Context

- Status: implemented 2026-11-09, uncommitted. Manual popover and Settings check and native string review pending. First drafted 2026-10-23. Presents the status from (core 14 AC2). Codex is the first provider with it (providers 30). Both are merged, so the registry already exposes status, install, and remove.
- `Sources/App/QuotaView.swift` — provider cards. The error state already has an "Open Settings" link through `openAndRaiseSettings()`. That link always opens the last-used tab.
- `Sources/App/SettingsWindowActivation.swift` — `openAndRaiseSettings()` opens and raises the Settings window but takes no destination.
- `Sources/App/AppMain.swift` — owns `@State settingsTab` and passes it to `SettingsView` as a binding. A deep link can set it there.
- `Sources/App/SettingsView.swift` — the Providers tab lists every provider with `ForEach(viewModel.registeredProvidersOrdered)` and `ProviderSetupCard`.
- `Sources/App/ProviderSetupCard.swift` — builds each provider's Settings card and picks `APIKeyFreeSettingsRow` for API-key-free providers.
- `Sources/App/APIKeyFreeSettingsRow.swift` — the API-key-free card (ui 05). It shows install and remove only in `.setup` and `.error`, because the Claude Code helper is required. Activity detection is optional, so it needs its own section in `.loaded`.
- `Sources/App/RefreshSettingsProviderRow.swift` — the Smart status per provider (core 11 AC5). The Refresh tab's label is now "Usage Checks", and its modes read "Smart" and "Regular" schedule.
- `Sources/App/QuotaView.swift` and `Sources/App/QuotaView+HeadlineAndRows.swift` — the loaded popover card, now inside the provider tabs (ui 40).
- `Sources/App/QuotaViewModel.swift` — its class body is at SwiftLint's 250-line limit, so new stored state cannot go there.
- `Sources/App/Resources/Localizable.xcstrings` — every new string in every shipped language (ui 31, ui 36).
- The user asked on 2026-10-23 for a button that takes Codex users to Settings when something on their side is missing.
- 2026-11-09 amendment (AC8): the card's bottom action row from (ui 25 AC2) showed "Remove Helper" in `.loaded` for every API-key-free provider, even one with no helper, such as Codex. It also repeated buttons that the state content already showed: Remove Helper in `.loaded`, Install Helper in `.setup`, and the credential import in `.error`. That button would sit next to the new activity-detection "Remove", so the user asked to fix it here.
- 2026-11-09 amendment (AC1 wording): after seeing the section, the user asked for clearer copy. The section must say the helper is optional and what it improves, and the waiting state must read as a step to finish, not as "Waiting for the first signal". Codex's texts changed with it (providers 30 AC6).
- 2026-11-09 amendment (AC1 layout): the user confirmed the wording but asked to move the "Optional…" explanation into a popover behind an info button, so the card stays uncluttered. The user also confirmed that the provider's install text goes away once the first hook run arrives.
- 2026-11-09: the user decided the popover never prompts a user who has not opted in. The notice shows only after an install, while it waits for its first signal. Discovery of the feature stays in Settings.

## Acceptance Criteria

### AC1: Settings shows an Activity detection section

- **Given** a provider conforms to `ActivitySignaling` and is enabled
- **When** the user opens its card in Settings → Providers
- **Then** the card shows an "Activity detection" section in every state except `.setup` and `.unconfigured`
- **And** an info button next to the "Activity detection" heading toggles a popover that explains the helper is optional, that it tells Filbert when the user starts and finishes a task so the Smart schedule checks usage while they work, and that without it Filbert checks on its normal schedule. The explanation is not shown in the card itself, to keep it uncluttered. The button's VoiceOver label and tooltip read "About activity detection" (amended 2026-11-09)
- **And** it shows the status from (core 14 AC2) with the provider's text
- **And** `notInstalled` shows "Off", an "Install" button, and the provider's text, which says what install adds or why the last read failed
- **And** `awaitingFirstSignal` shows "Installed. Finish setup in <provider>", the provider's next steps, and a "Remove" button (amended 2026-11-09)
- **And** `active` shows "On" and a "Remove" button
- **And** `unavailable` shows its reason and no buttons
- **And** install and remove errors show inline (ui 05 AC7), with the error-log link (core 10)
- **And** the App records install and remove failures in the error log with their diagnostic code only, never file content (providers 30 AC3)
- **And** the section refreshes its status after install, after remove, and when the Settings window becomes key.

### AC2: The section tells the user when signals have no effect

- **Given** the section is visible
- **When** the schedule is Regular, or automatic checks are off for that provider
- **Then** the section adds one line saying activity detection takes effect only with the Smart schedule
- **And** that line opens the Usage Checks tab.

### AC3: The popover offers a button when an opted-in user must act

- **Given** a provider conforms to `ActivitySignaling`, is enabled, and is in the `.loaded` state
- **When** its status is `awaitingFirstSignal`
- **And** the schedule is Smart and automatic checks are on for that provider
- **And** the user has not dismissed the notice for that provider
- **Then** its popover card shows a one-line notice under the usage lines
- **And** the notice reads like "Finish setting up activity detection"
- **And** that text is a fixed App label that names no provider mechanism, such as hooks (AC6)
- **And** a provider whose status is `notInstalled`, `active`, or `unavailable` shows no notice, so the popover never prompts a user who has not opted in
- **And** the App reads each status when the popover opens, so the notice reflects changes made outside Filbert
- **And** the notice has a "Set Up…" button that opens Settings at that provider (AC4)
- **And** the notice never replaces or hides usage, errors, or the stale-data hint.

### AC4: Settings opens at the provider

- **Given** the user clicks "Set Up…" in a popover notice
- **When** Settings opens, or is already open
- **Then** the window is raised as in (ui 16)
- **And** the Providers tab is selected
- **And** the provider's card is scrolled into view and briefly highlighted
- **And** the highlight respects Reduce Motion
- **And** VoiceOver focus moves to the Activity detection section.

### AC5: The notice can be dismissed

- **Given** the popover notice is visible
- **When** the user clicks its "Not Now" button
- **Then** the notice hides for that provider and stays hidden after relaunch
- **And** Settings still shows the section with its status and next step
- **And** a new install clears the dismissal, so the notice can show again while that install waits for its first signal.

### AC6: The App stays provider-agnostic

- **Given** any provider conforms to `ActivitySignaling`
- **When** the App renders the section, the notice, or the deep link
- **Then** all text other than the fixed labels comes from the provider
- **And** the App contains no Codex-specific condition.

### AC7: Strings are localized and accessible

- **Given** the new labels, notice texts, and buttons
- **When** the app runs in any shipped language
- **Then** each string has a translation in `Localizable.xcstrings`
- **And** the notice and its buttons have VoiceOver labels that name the provider.

### AC8 (amendment 2026-11-09): Each helper action shows once, and only when it applies

- **Given** an enabled API-key-free provider card in Settings
- **When** the card renders in any state
- **Then** "Remove Helper" shows in `.loaded` only when the provider can remove a helper, so Codex and other providers without a helper show none
- **And** the bottom action row from (ui 25 AC2) is the only place for Remove Helper in `.loaded`, Install Helper in `.setup`, and the credential import in `.setup` and `.error`
- **And** the state content keeps its texts, such as "Helper installed and active." and the install explanation, without repeating those buttons
- **And** the Remove Helper in `.setup` and the Install Helper and Remove Helper in `.error` (ui 05 AC7) stay in the state content, because the action row does not show them in those states.

## Plan

1. [x] Add a `SettingsDestination` (tab plus optional provider ID) and an observable `SettingsNavigation` that owns the selected tab, kept in `AppMain.swift` where `settingsTab` was. Give `openAndRaiseSettings()` an optional destination.
2. [x] Wrap the Providers tab list in a `ScrollViewReader` and scroll to the requested provider ID. Then clear the destination.
3. [x] Add `ActivityDetectionSection` (AC1, AC2). The Providers tab passes it into `ProviderSetupCard` through a supplement slot, so it shows for either auth shape, and the Welcome window's cards stay unchanged. This replaces the draft's plan to add it to `APIKeyFreeSettingsRow` and the API-key row separately.
4. [x] Add an `@Observable` activity-detection model, owned by `QuotaViewModel`, with each provider's signal status, refreshed per AC1 and AC3, and install and remove actions that call the registry and record failures. It is a separate type because `QuotaViewModel`'s class body is at the SwiftLint limit.
5. [x] Add the popover notice to the loaded card in `QuotaView.swift`, gated by AC3, with a persisted dismissal per provider ID (AC5).
6. [x] Seed strings in every shipped language. Ask for a native review of the new strings, as with (ui 34).
7. [x] Tests: status-to-UI mapping, notice gating, dismissal persistence and reset, and the destination round trip.
8. [x] Amendment (AC8): derive the action row's buttons from the state, `canInstall`, `canRemove`, and import availability in one place, and remove the repeated buttons from the state content. Test each state.

## Risks

- **Popover height.** A notice adds one row to the Codex card. Check the popover with every provider enabled.
- **Nagging.** `awaitingFirstSignal` cannot tell "not trusted yet" from "trusted but Codex not used yet". A user who trusted the hooks sees the notice until their next Codex prompt. "Not Now" covers this.
- **Deep-link timing.** Settings may build its view after the destination is set on first open. Keep the destination until the providers list reads it, not just for one run-loop tick.

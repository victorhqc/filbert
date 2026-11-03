## Objective

Let the user choose a stacked or a tabbed layout for the provider cards in Filbert's panel.

## Context

- Status: approved 2026-11-03. Plan steps 1–8 are done on 2026-11-03, not committed. The manual check in step 9, the native review of the new strings, and the user's second feedback round are open.
- The user asked on 2026-11-03 for a setting with two layouts:
  - **Stacked** is the layout of today: one card per provider, each collapsible (ui 14).
  - **Tabs** shows one tab per provider. A tab has the provider logo, the current allowance, and the refresh button, but no name. A click on a tab shows that provider's full card. Only one card shows at a time. This helps users with many providers.
- Decisions the user made on 2026-11-03:
  - Tabs wrap into a grid at the current 280 pt panel width. A tab is about 110 pt wide, so two tabs fit in one row. Filbert has 10 providers, so the grid can have 5 rows. The panel width does not change.
  - The panel opens on the tab the user selected last, also after a restart.
  - Kimi Code and Kimi API use the same glyph files. z.ai Coding Plan and z.ai API do too. The API tab shows a small "API" label after the logo. The subscription tab shows no label.
  - A wide amount that does not fit in a tab is an accepted risk.
  - The panel height can change when the user selects a different tab.
  - Five rows of tabs with 10 providers is acceptable.
- Feedback round 1, 2026-11-03: the first build worked. The user asked for tabs sized to their content, with a maximum width, instead of equal columns. Claude Code, Codex, Kimi Code, and DeepSeek tabs were wider than their content needs.
- `Sources/App/QuotaView.swift` — `body` puts one `providerSection` for each ID in `configuredProviderIds`. `providerHeader` keeps the collapse `Button` and the refresh `Button` as sibling hit targets (ui 14 Risks). `providerBody` draws the full content for each `ProviderState`. The tabs layout reuses `providerBody` without a change.
- `Sources/App/CompactProviderStatus.swift` — the ring and percentage, the balance dot and amount, or the credits amount (ui 14 AC5). A tab shows this view without a change, so a tab, a stacked card, and the menu bar icon always agree (ui 10).
- `Sources/App/ProviderVisualStyle.swift` — `ProviderLogoBadge`, `neutralContainerFill`, `cardCornerRadius`. Tabs use the same badge and fill.
- `Sources/App/QuotaView+HeaderAccessibility.swift` — `headerAccessibilityLabel` makes "Claude Code: 12% used" and similar sentences. A tab reuses it.
- `Sources/App/AppearanceSettingsView.swift` — the Appearance tab. A new "Panel layout" card goes here.
- `Sources/App/QuotaViewModel+Presentation.swift` — `isCollapsed(_:)`, `toggleCollapsed(_:)`, `setVintageMacIconEnabled(_:)`. The layout and the selected tab go here with the same pattern.
- `Sources/Core/VintageMacIcon.swift`, `Sources/Core/ProviderCollapseState.swift` — the UserDefaults store pattern: private key, `defaults`, `setUserDefaults(_:)` test hook. The new store copies it. The layout is presentation state, not a secret, so it stays out of the Keychain (AGENTS.md §3).
- Builds on (ui 14) for cards, badges, and the compact status, (ui 09) for order, (ui 17) for enablement, (ui 10) for the status sentences, and (ui 32) for the live language switch. New strings follow (ui 29) and go to every language from (ui 31) and (ui 36).
- `Sources/Core/ProviderProtocol.swift`, `Sources/Core/ProviderMetadata.swift`, `Sources/Core/ProviderRegistry.swift` — `AIProvider.providerGlyph` goes to `ProviderInfo.glyph` through the registry. The tab label follows the same path, with a `nil` default, so a provider without a label needs no change.
- `Sources/Providers/KimiAPI/KimiAPIProvider.swift`, `Sources/Providers/ZAIAPI/ZAIAPIProvider.swift` — the only providers that declare a tab label. Each provider declares its own label, and the App has no `switch` on a provider ID (core 01, AGENTS.md §4).
- `docs/localization-glossary.md` — product names stay in English. "API" is part of the product names "Kimi API" and "z.ai API", so the label is not translated.

## Acceptance Criteria

### AC1: Settings has a Panel layout choice

- **Given** the Appearance tab in Settings
- **When** it opens
- **Then** it shows a "Panel layout" card with a segmented picker: "Stacked" and "Tabs"
- **And** below the picker, one caption describes the selected layout:
  - Stacked: "Show every provider as a card."
  - Tabs: "Show one provider at a time. Select a tab to see its details."

### AC2: Stacked is the default

- **Given** a fresh install, or an upgrade from a version without this setting
- **When** the panel opens
- **Then** it uses the stacked layout, the same as today
- **And** each card keeps its saved collapse state (ui 14 AC7).

### AC3: The panel changes at once

- **Given** the panel and Settings are both open
- **When** the user changes the layout
- **Then** the panel changes to the new layout without a restart and without a network request.

### AC4: The selection persists

- **Given** the user selected a layout
- **When** Filbert quits and launches again
- **Then** the panel uses that layout
- **And** an unknown stored value gives the stacked layout.

### AC5: Tabs mode shows a grid of tabs

- **Given** the tabs layout and two or more configured providers
- **When** the panel opens
- **Then** the top of the panel shows one tab for each configured provider, in the order of `configuredProviderIds` (ui 09, ui 17)
- **And** each tab is as wide as its content, up to a maximum of half the row width minus the spacing
- **And** the tabs flow from leading to trailing, and a tab that does not fit in the row goes to the next row. All tabs show without a scroll
- **And** a tab whose content is wider than the maximum gets the maximum width, and its status text scales down and then truncates
- **And** the panel width stays 280 pt.

### AC6: A tab shows the logo, the allowance, and the refresh button

- **Given** a tab
- **When** it renders
- **Then** it shows, from leading to trailing: the provider logo badge, the tab label when the provider has one (AC7), the status for the provider state, and the refresh button
- **And** it does not show the provider name
- **And** the status for each state is:
  - `.loaded`: `CompactProviderStatus`, the same view as a collapsed stacked card (ui 14 AC5). A `.fallback` status shows nothing
  - `.loading`: a small progress indicator
  - `.error`, or a refresh error: the yellow warning triangle, with the message as help text
  - `.setup`: nothing
- **And** the refresh button works as in a stacked card: it is disabled while a refresh runs and while the provider asks Filbert to wait, with the same help text
- **And** the provider name shows as help text when the pointer is on the tab.

### AC7: API providers show an "API" label

- **Given** the tabs layout
- **When** the Kimi API tab or the z.ai API tab renders
- **Then** it shows "API" after the logo badge, in `.caption2` semibold and the secondary color
- **And** the Kimi Code tab and the z.ai Coding Plan tab show no label
- **And** a provider declares its label with `static var providerTabLabel: String?`. The default is `nil`. Only Kimi API and z.ai API return "API"
- **And** the label is the same in every language
- **And** the label is decorative for VoiceOver, because the provider name already has "API" (AC14)
- **And** the stacked layout does not show the label.

### AC8: A click on a tab selects it

- **Given** the tabs layout
- **When** the user clicks a tab outside its refresh button
- **Then** that tab becomes the selected tab
- **And** the selected tab has a highlighted background. The other tabs use the neutral card fill
- **And** a click on the refresh button starts a refresh and does not change the selected tab.

### AC9: The selected provider's full card shows below the grid

- **Given** a selected tab
- **When** the panel renders
- **Then** below the grid, the panel shows one card for the selected provider
- **And** the card header shows the logo badge, the provider name, and "Fast checks on" when it applies. It shows no chevron, no compact status, and no refresh button, because the tab has them
- **And** the card body is the same as an expanded stacked card for every state (ui 14 AC6, AC8), with the refresh error label and the error log link
- **And** the card cannot collapse.

### AC10: The panel opens on the last selected tab

- **Given** the user selected a tab
- **When** the panel opens again, or Filbert launches again
- **Then** that tab is selected
- **And** when that provider is not configured or not enabled anymore, the first tab is selected
- **And** that fallback does not change the saved tab. If the provider is configured again later, its tab is selected again.

### AC11: One provider still shows a tab

- **Given** the tabs layout and exactly one configured provider
- **When** the panel opens
- **Then** it shows one tab and that provider's card below it.

### AC12: The two layouts do not change each other's state

- **Given** saved collapse states for the stacked layout
- **When** the user changes to tabs, selects tabs, and changes back to stacked
- **Then** every stacked card has the collapse state it had before
- **And** a collapse toggle in the stacked layout does not change the saved tab.

### AC13: Other parts of the panel do not change

- **Given** either layout
- **When** the panel renders
- **Then** the empty state, the Keep Mac Awake row, and the footer are the same as today
- **And** the menu bar icon and its provider selection do not change (ui 10, ui 23).

### AC14: Accessibility

- **Given** VoiceOver on a tab
- **When** it reads the tab
- **Then** it reads the provider name and the status sentence from `headerAccessibilityLabel` (for example "Claude Code: 12% used"), and "Fast checks on" when it applies
- **And** the selected tab has the selected trait
- **And** the refresh button is a separate element with its own label
- **And** each tab can get keyboard focus, and Space selects it.

### AC15: Localization

- **Given** any language that Filbert supports (ui 31, ui 36)
- **When** the new Settings card and the tab help text render
- **Then** each string comes from the Core lookup with the display locale (ui 29 AC1, ui 32 AC9)
- **And** each string has a translation in `Sources/App/Resources/Localizable.xcstrings` for every supported language.

## Plan

1. [x] **Core: `PanelLayoutPreferences` store.** New `Sources/Core/PanelLayoutPreferences.swift`, with the pattern of `VintageMacIcon`:
   ```swift
   public enum PanelLayout: String, Sendable, CaseIterable { case stacked, tabs }

   public enum PanelLayoutPreferences {
       public static var layout: PanelLayout { get }      // unknown or missing → .stacked
       public static func setLayout(_ layout: PanelLayout)
       public static var selectedTabProviderId: String? { get }
       public static func setSelectedTabProviderId(_ id: String)
       public static func setUserDefaults(_ defaults: UserDefaults)
   }
   ```
   The store has no fallback for the selected tab. The App layer owns it, because only the App knows the configured providers. `ProviderCollapseState` does the same.
2. [x] **Core and providers: tab label.** Add `static var providerTabLabel: String? { get }` to `AIProvider`, with a `nil` default in the protocol extension. Add `tabLabel: String?` to `ProviderInfo`, with a `nil` default in `init`. `ProviderRegistry.registeredProviders` passes it, as it does for `providerGlyph`. `KimiAPIProvider` and `ZAIAPIProvider` return `"API"`. No other provider changes.
3. [x] **App: view-model wiring.** `QuotaViewModel` gains a published `panelLayout`, `setPanelLayout(_:)`, a resolved `selectedTabProviderId`, and `selectTab(_:)`. A static `resolvedSelectedTab(saved:configured:)` returns the saved ID when it is in `configuredProviderIds`, else the first ID, else `nil` (AC10). Only `selectTab(_:)` writes the store.
4. [x] **App: `ProviderTab` view.** New `Sources/App/ProviderTab.swift`. An `HStack` of two sibling hit targets, the same as `providerHeader`: a select `Button` with the badge, the tab label (AC7), and the status, then the refresh button. The background is on the `HStack`. The refresh button, its help text, and its disabled rule move from `QuotaView` to a shared view, so a stacked card and a tab use one implementation.
5. [x] **App: tabs layout in `QuotaView`.** `body` switches on `viewModel.panelLayout`. The tabs branch draws the tabs in `ProviderTabFlowLayout`, a SwiftUI `Layout` that sizes each tab to its ideal width, caps it at the maximum width, and wraps rows (feedback round 1; it replaces a two-column `LazyVGrid`). Then it draws one card for the selected provider. That card uses a header without the chevron and refresh, and the existing `providerBody`. No `ScrollView`, because `MenuBarExtra` collapses it to zero height.
6. [x] **App: Settings card.** Add the "Panel layout" card to `AppearanceTab`, after "Provider order". It uses a segmented `Picker` bound to `viewModel.panelLayout` and the caption from AC1.
7. [x] **Strings.** Add the new strings to `Localizable.xcstrings` for every supported language. A native speaker reviews them, as for (ui 36). The "API" label is not in the catalog, because it is part of a product name.
8. [x] **Tests.**
   - `Tests/CoreTests/PanelLayoutPreferencesTests.swift`: the default is `.stacked`, an unknown raw value gives `.stacked`, layout and selected tab round-trip, `setUserDefaults` swaps the store.
   - `Tests/CoreTests`: `ProviderInfo.tabLabel` comes from the registry, and is `nil` for a provider that does not declare one.
   - Provider tests: `KimiAPIProvider.providerTabLabel` and `ZAIAPIProvider.providerTabLabel` are `"API"`. `KimiCodeProvider` and `ZAIProvider` give `nil`.
   - `Tests/AppTests/ProviderTabFlowLayoutTests.swift`: the row breaks for a set of tab widths, the width cap, and an empty list.
   - `Tests/AppTests`: `resolvedSelectedTab` returns the saved ID when configured, the first ID when the saved ID is missing or not configured, and `nil` with no configured provider. The fallback does not write the store. `setPanelLayout` does not change any `ProviderCollapseState` value (AC12).
9. [ ] **Manual check in the packaged app.** Check with 1, 2, 3, and all configured providers. Check AC3 with Settings and the panel open. Check AC8 for a double trigger on the refresh button. Check that the Kimi Code and Kimi API tabs, and the z.ai Coding Plan and z.ai API tabs, are easy to tell apart (AC7). Check VoiceOver and keyboard focus (AC14).

## Risks

- **Tab width for amounts. Accepted 2026-11-03.** The maximum tab width is about 121 pt. The logo, the "API" label, the dot, a balance such as "1.234,56 US$", and the refresh button can need more. If an amount does not fit, the text scales down a small amount and then truncates. It does not wrap, and it does not push the refresh button out of the tab.
- **Panel height changes on tab change. Accepted 2026-11-03.** Each provider's card has a different height, so the panel height changes when the user selects a different tab. A collapse toggle in the stacked layout already does this.
- **Nested button double trigger.** The select button and the refresh button are siblings, not nested. This is the same fix as (ui 14 Risks). Plan step 9 checks it.
- **Many providers. Accepted 2026-11-03.** With 10 providers, the grid has 5 rows before the card. This is still shorter than 10 expanded cards, but the card moves down.
- **Refresh button moves to a shared view.** Plan step 4 moves code that the stacked layout uses. The stacked layout must not change (AC2). A reviewer should check the refresh help text and the disabled rule in both layouts.
- **New protocol requirement.** `providerTabLabel` has a `nil` default, so a new provider compiles without it. A provider with the same logo as another provider must remember to declare a label. Nothing enforces this.

## Findings

- 2026-11-03: the refresh button is now one shared view (`ProviderRefreshButton`). It has an accessibility label, "Check usage now", in both layouts. Before, the stacked button had only help text.
- 2026-11-03: the `providerGlyph` and `providerTabLabel` defaults are in `Sources/Core/ProviderGlyph.swift`. `ProviderProtocol.swift` was 404 lines at HEAD, more than the SwiftLint `file_length` limit of 400. It is now 401 lines. That warning existed before this change.
- 2026-11-03, feedback round 1: tabs use `ProviderTabFlowLayout` in place of the two-column grid. A tab is as wide as its content, up to about 121 pt at the 280 pt panel width. The gate passed after the change.
- 2026-11-03: the new strings are machine translations. They need the native review in Plan step 7 before release.

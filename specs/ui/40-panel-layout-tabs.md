## Objective

Let the user choose a stacked or a tabbed layout for the provider cards in Filbert's panel.

## Context

- Status: approved 2026-11-03. The first build and feedback round 1 are committed in `7eefc74`. Feedback round 3 is in progress. The manual check in Plan step 9 and the native review of the new strings are open.
- The user asked on 2026-11-03 for a setting with two layouts:
  - **Stacked** is the layout of today: one card per provider, each collapsible (ui 14).
  - **Tabs** shows one tab per provider. A tab has the provider logo, the current allowance, and the refresh button, but no name. A click on a tab shows that provider's full card. Only one card shows at a time. This helps users with many providers.
- Decisions the user made on 2026-11-03:
  - Tabs wrap into a grid at the current 280 pt panel width. A tab is about 110 pt wide, so two tabs fit in one row. Filbert has 10 providers, so the grid can have 5 rows. The panel width does not change.
  - The panel opens on the tab the user selected last, also after a restart.
  - Kimi Code and Kimi API use the same glyph files. z.ai Coding Plan and z.ai API do too. The API tab shows a small "API" label after the logo. The subscription tab shows no label.
  - A wide amount that does not fit in a tab is an accepted risk.
  - The panel height can change when the user selects a different tab.
  - Five rows of tabs with 10 providers is acceptable. Superseded by feedback round 2.
- Feedback round 1, 2026-11-03: the first build worked. The user asked for tabs sized to their content, with a maximum width, instead of equal columns. Claude Code, Codex, Kimi Code, and DeepSeek tabs were wider than their content needs.
- Feedback round 2, 2026-11-03, after commit `7eefc74`: the user asked for the tabs in one row that scrolls horizontally, in place of the wrapping rows. This replaces the grid decision above. Tabs keep their content width and the maximum width.
- Feedback round 3, 2026-11-03: the round 2 build matched this spec, but the user did not like the scrolling row. Its problems: a vertical mouse wheel does not move it, the scroll bar looks foreign in the panel, and tabs out of view hide providers. The tabs were also wide (about 100 pt) because each had a refresh button and a ring with a number beside the logo. The user chose "icon tabs":
  - The usage ring goes around the logo. The value goes below the logo, in small text.
  - One refresh button on the selected card header, in place of one in each tab. This changes the first request (a refresh button in each tab).
  - "API" is a small badge on the corner of the logo, so it adds no width.
  - Tabs wrap again (round 1 flow layout). A percentage tab is about 38 pt and a balance tab about 58 pt, so 5 providers fit in one row and 10 fit in two.
  - No scroll.
- Feedback round 4, 2026-11-03: the user liked the direction of round 3 and asked for three refinements:
  - Remove the square fill of the logo badge inside the ring.
  - Make the ring colors less intense in the panel. The value text keeps its full color. The user first saw 55% opacity, then chose 70%.
  - Five tabs did not fit in one row of 248 pt (they needed about 268 pt). Make the tabs smaller.
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

### AC5: Tabs mode shows icon tabs that wrap

- **Given** the tabs layout and two or more configured providers
- **When** the panel opens
- **Then** the top of the panel shows one tab for each configured provider, in the order of `configuredProviderIds` (ui 09, ui 17)
- **And** each tab is as wide as its content, up to a maximum of half the row width minus the spacing
- **And** the tabs flow from leading to trailing, and a tab that does not fit in the row goes to the next row. All tabs show without a scroll
- **And** a tab whose value is wider than the maximum gets the maximum width, and its value scales down and then truncates
- **And** the panel width stays 280 pt.

### AC6: A tab shows the logo inside a usage ring, and the value below it

- **Given** a tab
- **When** it renders
- **Then** it shows the provider logo inside a ring of 28 pt, and one line of `.caption2` text below the ring. The logo has no square fill in a tab
- **And** it does not show the provider name, and it has no refresh button
- **And** the ring and the value for each state are:
  - `.loaded` with a `.window` status: the ring fills to the used percentage in the tier color at 70% opacity. The value is the percentage, in the full tier color
  - `.loaded` with a `.balance` status: the ring is full, in the balance tier color at 70% opacity. The value is the formatted amount
  - `.loaded` with a `.credits` status: the ring is the empty track. The value is the formatted amount
  - `.loaded` with a `.fallback` status, or `.setup`: the ring is the empty track. The value line is empty
  - `.loading`: a small progress indicator in place of the value
  - `.error`, or a refresh error: the yellow warning triangle in place of the value, with the message as help text
- **And** the percentage, the amount, the ring fraction, and the tier come from `QuotaStatusResolver`, the same as a collapsed stacked card and the menu bar icon (ui 14 AC5, ui 10)
- **And** every tab has the same height, also when its value line is empty
- **And** a tab is at least 36 pt wide, and tabs have 4 pt between them, so five tabs with two short amounts fit in one row of 248 pt
- **And** the provider name shows as help text when the pointer is on the tab.

### AC7: API providers show an "API" badge

- **Given** the tabs layout
- **When** the Kimi API tab or the z.ai API tab renders
- **Then** it shows a small "API" badge on the bottom trailing corner of the ring, in `.system(size: 7)` bold, on a capsule that separates it from the logo
- **And** the badge adds no width to the tab
- **And** the Kimi Code tab and the z.ai Coding Plan tab show no badge
- **And** a provider declares its label with `static var providerTabLabel: String?`. The default is `nil`. Only Kimi API and z.ai API return "API"
- **And** the label is the same in every language
- **And** the label is decorative for VoiceOver, because the provider name already has "API" (AC14)
- **And** the stacked layout does not show the label.

### AC8: A click on a tab selects it

- **Given** the tabs layout
- **When** the user clicks a tab
- **Then** that tab becomes the selected tab
- **And** the selected tab has a highlighted background. The other tabs have no background.

### AC9: The selected provider's full card shows below the tabs

- **Given** a selected tab
- **When** the panel renders
- **Then** below the tabs, the panel shows one card for the selected provider
- **And** the card header shows the logo badge, the provider name, "Fast checks on" when it applies, the yellow warning triangle when there is an error, and the refresh button. It shows no chevron and no compact status
- **And** the refresh button works as in a stacked card: it is disabled while a refresh runs and while the provider asks Filbert to wait, with the same help text
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
- **And** the refresh button on the card has its own label, "Check usage now"
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
5. [x] **App: tabs layout in `QuotaView`.** `body` switches on `viewModel.panelLayout`. The tabs branch draws the tabs in `ProviderTabStripLayout`, a SwiftUI `Layout` that puts the tabs in one row and caps each tab at the maximum width, inside a horizontal `ScrollView` with a `ScrollViewReader` (feedback round 2; it replaces the wrapping `ProviderTabFlowLayout` of round 1 and the two-column `LazyVGrid` before it). The `ScrollView` has `fixedSize(horizontal: false, vertical: true)`, because `MenuBarExtra` collapses a scroll view without a fixed height to zero height. Then it draws one card for the selected provider. That card uses a header without the chevron and refresh, and the existing `providerBody`.
6. [x] **App: Settings card.** Add the "Panel layout" card to `AppearanceTab`, after "Provider order". It uses a segmented `Picker` bound to `viewModel.panelLayout` and the caption from AC1.
7. [x] **Strings.** Add the new strings to `Localizable.xcstrings` for every supported language. A native speaker reviews them, as for (ui 36). The "API" label is not in the catalog, because it is part of a product name.
8. [x] **Tests.**
   - `Tests/CoreTests/PanelLayoutPreferencesTests.swift`: the default is `.stacked`, an unknown raw value gives `.stacked`, layout and selected tab round-trip, `setUserDefaults` swaps the store.
   - `Tests/CoreTests`: `ProviderInfo.tabLabel` comes from the registry, and is `nil` for a provider that does not declare one.
   - Provider tests: `KimiAPIProvider.providerTabLabel` and `ZAIAPIProvider.providerTabLabel` are `"API"`. `KimiCodeProvider` and `ZAIProvider` give `nil`.
   - `Tests/AppTests/ProviderTabFlowLayoutTests.swift`: the row breaks for a set of tab widths, the width cap, and an empty list (restored in round 3).
   - `Tests/AppTests`: `resolvedSelectedTab` returns the saved ID when configured, the first ID when the saved ID is missing or not configured, and `nil` with no configured provider. The fallback does not write the store. `setPanelLayout` does not change any `ProviderCollapseState` value (AC12).
9. [ ] **Manual check in the packaged app.** Check with 1, 2, 3, 5, and all configured providers. Check AC3 with Settings and the panel open. Check that the Kimi Code and Kimi API tabs, and the z.ai Coding Plan and z.ai API tabs, are easy to tell apart (AC7). Check the ring and the value for each state in light and dark mode (AC6). Check VoiceOver and keyboard focus (AC14).
10. [x] **Feedback round 3: icon tabs.**
    - Restore `ProviderTabFlowLayout` and its tests from `7eefc74`. Remove `ProviderTabStripLayout`, its tests, and the horizontal `ScrollView`.
    - Extract the ring of `CompactProviderStatus` into a shared `UsageRing` view (fraction, color, line width, diameter). `CompactProviderStatus` uses it at its current size, so a collapsed stacked card does not change.
    - A pure `ProviderTabStatus` value maps a `ProviderState` and the time to the ring fraction, the ring tier, and the value text, with `QuotaStatusResolver`. `ProviderTab` renders it, so the mapping has unit tests.
    - `ProviderTab` becomes one `Button`: a `VStack` of the ring around the badge (with the "API" corner badge) and the value line. No refresh button in the tab.
    - The selected card header gets the error triangle and `ProviderRefreshButton`, the same as the stacked header without the chevron.
    - Tests: `Tests/AppTests/ProviderTabStatusTests.swift` covers each row of AC6.

11. [x] **Feedback round 4: tab refinements.** `ProviderLogoBadge` gets a `showsContainer` flag, `true` by default, so the stacked layout and Settings keep the fill. `UsageRing` gets an opacity for its tier color. The tab ring is 28 pt, the tab padding is 4 pt, and the flow spacing is 4 pt.

## Risks

- **Tab width for amounts. Accepted 2026-11-03.** The maximum tab width is about 121 pt. Only the value line can be wider than the ring, so this is rare now. If an amount does not fit, the text scales down a small amount and then truncates. It does not wrap, and it does not push the refresh button out of the tab.
- **Panel height changes on tab change. Accepted 2026-11-03.** Each provider's card has a different height, so the panel height changes when the user selects a different tab. A collapse toggle in the stacked layout already does this.
- **Refresh from a tab that is not selected.** Round 3 removes the refresh button from the tabs. To refresh a provider, the user selects its tab, then clicks refresh on the card. Automatic refreshes do not change. A hover or context-menu refresh on the tab can come in a later round if the user asks.
- **Small value text.** The value is `.caption2` under a ring of about 31 pt. A long balance such as "1.234,56 US$" makes the tab wider than the ring. Plan step 9 checks that it stays readable.
- **Ring colors on the badge.** The ring is beside the gray badge fill. In dark mode the tier colors must still read clearly. Plan step 9 checks light and dark mode.
- **Refresh button moves to a shared view.** Plan step 4 moves code that the stacked layout uses. The stacked layout must not change (AC2). A reviewer should check the refresh help text and the disabled rule in both layouts.
- **New protocol requirement.** `providerTabLabel` has a `nil` default, so a new provider compiles without it. A provider with the same logo as another provider must remember to declare a label. Nothing enforces this.

## Findings

- 2026-11-03: the refresh button is now one shared view (`ProviderRefreshButton`). It has an accessibility label, "Check usage now", in both layouts. Before, the stacked button had only help text.
- 2026-11-03: the `providerGlyph` and `providerTabLabel` defaults are in `Sources/Core/ProviderGlyph.swift`. `ProviderProtocol.swift` was 404 lines at HEAD, more than the SwiftLint `file_length` limit of 400. It is now 401 lines. That warning existed before this change.
- 2026-11-03, feedback round 1: tabs use `ProviderTabFlowLayout` in place of the two-column grid. A tab is as wide as its content, up to about 121 pt at the 280 pt panel width. The gate passed after the change.
- 2026-11-03, feedback round 2: tabs are in one horizontal scrolling row (`ProviderTabStripLayout`). `ProviderTabFlowLayout` and its tests are removed.
- 2026-11-03, feedback round 3: done as in Plan step 10. `UsageRing` is shared by the collapsed stacked card and the tab. The selected card header and the stacked header share `headerTrailingControls`. The gate passed.
- 2026-11-03: the new strings are machine translations. They need the native review in Plan step 7 before release.

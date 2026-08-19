## Objective

Let the user choose between a manually ordered provider and a deterministic automatic policy for the provider represented in the macOS menu bar while making the selected provider's identity and fast-refresh state visible there.

## Context

- `Sources/App/AppearanceSettingsView.swift` — adds the Automatic control and explains how provider order behaves in each mode.
- `Sources/App/MenuBarStatusIcon.swift` — currently reads `configuredProviderIds.first`; it will consume one shared selection result before resolving the provider glyph, existing ring, amount, Vintage Mac face, accessibility output, and fast-refresh indicator (ui 10, ui 12, ui 14).
- `Sources/App/QuotaViewModel.swift` — owns the observable configured order, loaded provider states, and per-provider fast-refresh status needed by the selection policy.
- New `Sources/App/MenuBarProviderSelector.swift` — keeps priority and tie-breaking in a pure, provider-neutral resolver.
- New `Sources/Core/MenuBarProviderSelectionPreferences.swift` — persists whether selection is automatic without exposing the raw `UserDefaults` key to App code.
- `Sources/App/Resources/Localizable.xcstrings` — localizes the control, explanation, current-selection text, and accessibility values.
- Builds on saved provider ordering (ui 09), configured-only ordering (ui 16), live menu-bar status resolution (ui 10), provider-owned glyphs (ui 14), and provider-scoped Smart fast mode (core 08, core 09). Its menu-bar fast indicator supersedes the prohibition in (core 08 AC17) while retaining that criterion's provider-specific popover status.

## Acceptance Criteria

### AC1: Appearance offers automatic or manual selection

- **Given** at least one provider is configured
- **When** the Provider order card renders
- **Then** it shows an `Automatic` toggle before the ordered provider rows
- **And** supporting text explains that Automatic favors active providers and otherwise uses the most recently updated provider
- **And** the ordered rows remain visible and reorderable in both modes because their order is the manual choice, the automatic tie-breaker, and the automatic fallback.

### AC2: Automatic selection is enabled by default

- **Given** no menu-bar selection preference has been saved
- **When** Filbert resolves the preference on a fresh or upgraded installation
- **Then** Automatic is on
- **And** changing the toggle persists the Boolean choice in `UserDefaults` and survives relaunch
- **And** this preference is independent of provider order, enablement, credentials, refresh settings, and the Vintage Mac option.

### AC3: Manual mode uses the first configured provider

- **Given** Automatic is off
- **When** the menu-bar provider is selected
- **Then** the first ID in `configuredProviderIds` is selected exactly as specified by (ui 10 AC2)
- **And** moving another configured provider to the first position updates the menu-bar status on the next render without a restart or refresh
- **And** an empty configured list selects no provider and keeps the existing Filbert fallback icon.

### AC4: Only displayable loaded providers compete in Automatic mode

- **Given** Automatic is on
- **When** candidates are assembled
- **Then** a candidate must be enabled, configured, present in `configuredProviderIds`, have a `.loaded(ProviderQuota)` state, and resolve to a non-fallback `QuotaStatusResolver.Status`
- **And** `.unconfigured`, `.setup`, `.loading`, `.error`, missing, disabled, and non-displayable loaded states do not compete
- **And** the rule is provider-neutral and contains no provider-ID or provider-type branches.

### AC5: Fast mode has first priority

- **Given** Automatic is on and one or more candidates are currently in Smart fast mode
- **When** the selector runs
- **Then** it selects only from those fast candidates, regardless of whether a non-fast candidate has a later `lastUpdated`
- **And** when exactly one candidate is fast, that provider is selected
- **And** when multiple candidates are fast, saved provider order selects among them under AC7; their `lastUpdated` values are not compared
- **And** fast status is read from the view model state established by (core 08 AC17), without changing refresh cadence or scheduling work.

### AC6: The latest update chooses only when no provider is fast

- **Given** Automatic is on, eligible candidates exist, and none is currently in Smart fast mode
- **When** the selector compares those candidates
- **Then** the candidate with the greatest `ProviderQuota.lastUpdated` value is selected
- **And** this uses the same provider-supplied timestamp shown as Last updated in the popover, not wall-clock render time or dictionary iteration order
- **And** `lastUpdated` never overrides an eligible fast provider and never chooses between two fast providers
- **And** a successful state update immediately recomputes the selection through existing observable state, with no new timer, fetch, or Keychain read.

### AC7: Saved user order resolves priority conflicts

- **Given** two or more eligible candidates are fast, or no candidate is fast and two or more candidates have equal `lastUpdated` values
- **When** the selector resolves that priority conflict
- **Then** the earliest candidate in `configuredProviderIds` wins
- **And** if malformed input includes a candidate absent from that array, it sorts after listed candidates and provider ID ascending is the final defensive tie-breaker
- **And** selection never depends on set or dictionary iteration order.

### AC8: Automatic mode has a stable fallback

- **Given** Automatic is on and no provider satisfies AC4
- **When** the menu-bar provider is selected
- **Then** the selector falls back to `configuredProviderIds.first`
- **And** the existing menu-bar resolver decides whether that provider produces live status or the Filbert fallback icon (ui 10 AC5)
- **And** the selector returns no provider only when the configured list is empty.

### AC9: Priority changes update the menu bar live

- **Given** Automatic is on
- **When** a candidate enters or leaves fast mode, receives a newer loaded quota, becomes unavailable as a candidate, is enabled or disabled, is configured or unconfigured, or its saved order changes a tie
- **Then** the selected provider and its existing menu-bar presentation update on the next SwiftUI render
- **And** leaving fast mode causes the selector to re-evaluate all remaining candidates under AC4–AC7 rather than pinning the previous provider
- **And** automatic selection introduces no sticky duration, debounce, polling loop, or provider mutation.

### AC10: Settings communicates the effective choice

- **Given** at least one provider is configured
- **When** the Provider order card renders
- **Then** it shows localized secondary text identifying the provider currently selected for the menu bar
- **And** in manual mode the text makes clear that the first provider is selected
- **And** in Automatic mode the text updates when the winning provider changes
- **And** VoiceOver announces the toggle state, its behavior, and the current selected provider without relying on row position or an icon alone.

### AC11: Menu bar identifies the selected provider

- **Given** the provider selected in either Automatic or manual mode resolves to a percentage or balance status
- **When** its menu-bar status renders
- **Then** the existing ring or Vintage Mac face and status text retain their order, followed immediately by that provider's own `ProviderInfo.glyph` unless the fast-refresh indicator is present
- **And** the glyph is a compact, unboxed menu-bar image rather than the larger background badge used in the popover and Settings
- **And** the glyph uses template rendering and the existing neutral glyph fallback, remains legible at the menu bar's standard content height, and never branches on provider ID or provider type (ui 14 AC3)
- **And** changing the selected provider changes the glyph on the same render as the percentage or balance text, so identity and status cannot disagree
- **And** the Filbert fallback icon shows no provider glyph because it represents no live provider status
- **And** the glyph is hidden from VoiceOver because the existing localized accessibility label already announces the selected provider by name.

### AC12: Menu bar identifies fast mode

- **Given** the provider selected in either Automatic or manual mode is currently in Smart fast mode
- **When** its menu-bar status renders
- **Then** a compact monochrome lightning-bolt icon appears immediately after the existing percentage or balance text
- **And** the indicator disappears on the next render when that provider leaves fast mode, automatic refresh is disabled for it, the shared mode changes to Regular, or another non-fast provider becomes selected
- **And** a different provider being fast does not show the indicator when the selected provider is not fast
- **And** the fallback Filbert icon does not show the indicator because no provider status is being represented
- **And** VoiceOver includes the localized phrase `Fast refresh active` in the selected provider's menu-bar accessibility label
- **And** the indicator uses template rendering and does not rely on color, matching the menu-bar monochrome rule in (ui 10 AC8)
- **And** this deliberately extends the popover-only fast status from (core 08 AC17) to the menu bar.

### AC13: Existing menu-bar presentations otherwise remain unchanged

- **Given** a provider has been selected by either mode
- **When** its status renders
- **Then** percentage, balance, fallback, Vintage Mac, monochrome, and accessibility behavior remain governed by (ui 10, ui 12)
- **And** apart from the provider glyph in AC11 and fast indicator in AC12, selection changes only which provider supplies the existing presentation
- **And** the popover provider order and provider-card contents are unchanged.

### AC14: Selection, persistence, provider identity, and fast indication are covered by focused tests

- **Given** isolated preferences and pure selector inputs
- **When** the test suites run
- **Then** they cover default-on persistence, explicit off/on round trips, manual first-provider selection, empty lists, candidate filtering, one fast provider, multiple fast providers resolved by saved order regardless of timestamps, latest-update selection only with no fast candidates, equal-date saved-order ties, malformed-order defensive ties, no-candidate fallback, and transitions into and out of fast mode
- **And** menu-bar presentation tests cover the selected provider's glyph in percentage, balance, Vintage Mac, provider-change, missing-asset fallback, and Filbert fallback states
- **And** they cover fast-indicator visibility for selected fast, selected non-fast, unselected fast, percentage, balance, fallback, and accessibility states
- **And** the tests perform no network request, Keychain mutation, child-process spawn, or wall-clock wait
- **And** existing menu-bar icon, provider ordering, and Smart refresh tests continue to pass.

## Plan

Add a Core preference wrapper with a missing-value default of `true`, a setter, and an isolated-`UserDefaults` test hook matching the existing presentation-preference stores. Expose the preference through observable `QuotaViewModel` state so Settings mutations and menu-bar rendering stay synchronized.

Add a pure App-layer selector that receives the configured IDs, provider states, fast-provider IDs, and mode. In manual mode it returns the first configured ID. In Automatic mode it filters to displayable loaded candidates. When fast candidates exist, it chooses the earliest one in configured order without consulting timestamps. Otherwise it sorts by `lastUpdated` descending, configured-order index ascending, then provider ID ascending. If filtering produces no candidates, it returns the first configured ID.

Update `MenuBarStatusIcon` to resolve its provider ID through the selector and obtain the matching provider-owned glyph from existing registry metadata. For a resolved percentage or balance status, retain the existing ring or Vintage Mac face and text order, then append a compact template glyph; keep it decorative because the accessibility label already names the provider. When that selected provider is fast, retain its template lightning-bolt image immediately after the existing text, before the provider glyph, and extend its accessibility label. Add the toggle, explanatory copy, and effective-provider text to the Provider order card. Add focused Core and App tests for persistence, the complete priority table, live state transitions, provider-glyph presentation, fast-indicator presentation, and current manual behavior before running the repository validation gate after review.

## Risks

- Default-on changes the menu-bar provider for existing users after upgrade when a later-updated or fast provider outranks their first saved provider. The control and effective-provider text make the change visible, and switching Automatic off restores the prior first-provider behavior without changing saved order.
- Providers do not necessarily source `lastUpdated` from identical clocks. A future-dated provider timestamp can remain selected until another candidate reports a later value; saved order still makes equal timestamps deterministic, but correcting provider timestamps is outside this presentation feature.
- Concurrent launch refreshes can move the selection as results arrive when no provider is fast. This is intentional because the latest successful non-fast candidate wins, but the menu-bar label may change width when providers use different status formats.
- A provider may remain displayable with stale last-known data after a quiet refresh failure. It remains an Automatic candidate under the same stale-data behavior already used by the popover and menu-bar; a failure removes fast priority through the Smart policy but does not erase useful last-known quota.
- The provider glyph and lightning bolt add width to an already constrained menu-bar label. They must use the smallest legible native sizing and spacing without shrinking the existing percentage or balance text; the provider glyph remains valuable because Automatic mode can change which provider supplies that text.

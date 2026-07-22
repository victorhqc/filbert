## Objective

Restyle the Settings window with the provider badges, rounded card surfaces, visual hierarchy, spacing, and semantic colors introduced by the revamped popover so both surfaces feel like one application without changing settings behavior.

## Context

- `Sources/App/SettingsView.swift` — owns the two-tab Settings window, provider credential and helper rows, provider ordering, balance thresholds, and the Vintage Mac toggle; its flat `List` rows and repeated badge styling now look disconnected from the provider cards introduced by (ui 14).
- `Sources/App/QuotaView.swift` — contains the reference provider-card treatment and the current private `ProviderLogoBadge` and tier-palette helpers from (ui 14); reusable visual primitives move out of this file so Settings and the popover cannot drift.
- New `Sources/App/ProviderVisualStyle.swift` — holds the small App-layer visual primitives and constants shared by the popover and Settings; it contains presentation only and does not become a general design-system abstraction.
- `Sources/App/AppMain.swift` — owns the `Settings` scene and is where the refreshed window receives an intentional default size and a usable minimum size.
- `Sources/Core/ProviderGlyph.swift` and `Sources/Core/ProviderProtocol.swift` — already transport provider-owned glyphs through `ProviderInfo`; they remain unchanged and Settings consumes the same metadata as the popover (ui 14 AC2/AC3).
- `Sources/App/Resources/Localizable.xcstrings` — receives any new headings, descriptions, accessibility labels, and control help text.
- The existing settings behavior comes from (ui 02), (ui 03), (ui 05), (ui 08), (ui 09), and (ui 13); this spec changes presentation and layout only.

## Acceptance Criteria

### AC1: The existing Settings information architecture is preserved

- **Given** the Settings window is opened
- **When** its root view renders
- **Then** it still exposes the two existing destinations, "Providers" and "Appearance", as native macOS Settings tabs with an icon and localized label
- **And** Providers still contains credentials, provider-local setup, and base-URL overrides, while Appearance still contains provider order, balance thresholds, and the Vintage Mac option (ui 09 AC1, ui 11 AC2)
- **And** the selected tab, tab keyboard behavior, and standard Settings-window chrome remain native rather than being replaced by a custom navigation control.

### AC2: The window has an intentional, adaptable layout

- **Given** the Settings window opens for the first time
- **When** macOS lays out its content
- **Then** it opens at a default content size of approximately `620 × 520` points with a minimum content size of `520 × 420` points
- **And** either tab can scroll vertically when its cards do not fit, while horizontal scrolling never appears at the minimum width
- **And** resizing wider grows the content area without stretching text fields, descriptions, or provider cards into hard-to-read full-width lines; the primary column is capped at a readable width and remains centered.

### AC3: Popover and Settings share provider visual primitives

- **Given** the same `ProviderInfo` appears in the popover and Settings
- **When** its identity is rendered on either surface
- **Then** both use one shared `ProviderLogoBadge` implementation with the same glyph loading, template rendering, fallback symbol, outer dimensions, inset, background opacity, and corner radius established by (ui 14 AC1/AC3)
- **And** shared provider surfaces use one source for the card corner radius and neutral container fill rather than duplicating numeric values in `QuotaView` and `SettingsView`
- **And** semantic good, warning, and critical colors come from the existing appearance-aware tier palette introduced by (ui 11 AC1), including its light-mode contrast tuning
- **And** these shared values remain App-layer presentation code; Core and provider modules do not import SwiftUI.

### AC4: The Providers tab renders one coherent card per provider

- **Given** one or more providers are registered
- **When** the Providers tab renders
- **Then** each provider appears in its own rounded card, separated from adjacent cards by consistent spacing rather than default `List` separators
- **And** each card header is laid out as `<logo badge> <name + description> … <status>`, using the same badge scale as the popover, a `.headline` provider name, and secondary supporting text
- **And** long provider names and descriptions wrap or truncate before the trailing status without overlapping it
- **And** the cards are driven exclusively by `registeredProvidersOrdered` and `ProviderInfo`; no provider ID is used to select a layout, glyph, color, or title (ui 02 AC9, ui 14 AC3).

### AC5: Provider status treatment is consistent and accessible

- **Given** an API-key provider or API-key-free provider is in any current settings state
- **When** its card header renders
- **Then** it shows a compact status pill with a small symbol plus localized text: configured/ready uses the shared good color, error uses the shared critical color, and unconfigured/setup/loading uses a neutral secondary treatment
- **And** the pill uses the same padding, corner radius, typography, and opacity for every provider and auth shape instead of the duplicated badge implementations in today's two row types
- **And** status is never communicated by color alone; the symbol and text remain visible in Increased Contrast and Differentiate Without Color modes
- **And** loading keeps its in-body progress indicator so an in-progress operation remains clear even when the header pill is not noticed.

### AC6: Provider controls gain clear hierarchy without behavioral changes

- **Given** any provider card state
- **When** its controls render
- **Then** the card body is visually separated from the identity header and uses standard macOS controls with consistent alignment, field height, and spacing
- **And** the primary action for the current state (Save or Install Helper) uses accent emphasis, while secondary actions (Reset and Advanced) remain secondary and destructive actions (Clear Key and Remove Helper) use the destructive role/tint without adding a new confirmation flow
- **And** the API-key field still submits and clears as specified by (ui 02 AC3/AC5), helper setup still follows (ui 05 AC3–AC7), setup-help links still follow (ui 13 AC2–AC4), and base-URL disclosure, validation, reset, and saved indicator still follow (ui 03 AC1–AC7)
- **And** expanding Advanced re-tiles the card without the `List` animation artifact documented in the current implementation; no nested control activates the card or another action accidentally.

### AC7: The Appearance tab uses the same card language

- **Given** the Appearance tab is selected
- **When** it renders
- **Then** Provider order, Balance thresholds, and Menu bar icon each appear as a distinct rounded settings card with a short heading and, where useful, secondary explanatory text
- **And** card geometry, container fill, heading hierarchy, and inter-card spacing match the Providers tab and the popover's provider-card family
- **And** the tab does not use tall empty `Section` header space or default separators that visually conflict with the cards.

### AC8: Provider-order rows show identity and remain reorderable

- **Given** the Provider order card contains registered providers
- **When** it renders
- **Then** every row shows the shared provider logo badge and display name, with compact row spacing and a visible drag affordance or localized drag help
- **And** dragging a row still updates and persists provider order, filters stale IDs, and updates the popover live exactly as specified by (ui 09 AC3–AC8)
- **And** row separators, if used inside the card, are inset after the logo and do not extend through the card's outer padding
- **And** adding a provider automatically adds its glyph-bearing row without changing `SettingsView`.

### AC9: Threshold and icon settings retain their data semantics

- **Given** the Balance thresholds and Menu bar icon cards render
- **When** the user edits their controls
- **Then** the low/ok steppers, range preview, validation, persistence, and currency-agnostic hint remain unchanged from (ui 08 AC2/AC4)
- **And** the preview uses the same shared appearance-aware good/warning/critical palette as the popover, not direct `.green`, `.orange`, or `.red` literals (ui 11 AC1)
- **And** the Vintage Mac toggle and its explanatory text keep the behavior introduced by (ui 12), with the control aligned consistently with the other settings cards.

### AC10: Light, dark, and system accessibility appearances are supported

- **Given** the app uses light mode, dark mode, Increased Contrast, Reduce Transparency, Differentiate Without Color, or a larger accessibility text size
- **When** either Settings tab renders
- **Then** card boundaries, text, status pills, controls, focus rings, and provider glyphs remain distinguishable and legible
- **And** no essential boundary relies solely on a translucent fill; Increased Contrast or Reduce Transparency adds a subtle semantic stroke or more opaque system background where needed
- **And** keyboard focus follows visual order, every actionable control remains reachable, and no fixed card height clips wrapped or enlarged content
- **And** decorative provider glyphs are hidden from VoiceOver because the adjacent provider name supplies their meaning (ui 14 AC10).

### AC11: All new Settings text is localized

- **Given** the app runs in any supported locale
- **When** the refreshed Settings UI renders
- **Then** every new heading, description, status label, tooltip, drag hint, and accessibility string resolves through `String(localized:)` or an equivalent localized SwiftUI initializer
- **And** English, German, Spanish (Spain), and Spanish (Mexico) values are present in `Sources/App/Resources/Localizable.xcstrings`, following (ui 13 AC5)
- **And** provider names, URLs, paths, currency codes, and other non-prose values remain unchanged.

### AC12: Visual parity is reviewed at representative states

- **Given** an implementation candidate
- **When** it is reviewed before completion
- **Then** screenshots are inspected in light and dark mode for both tabs at the default and minimum window sizes
- **And** the Providers tab review includes at least one configured API-key provider, one unconfigured API-key provider, one ready API-key-free provider, one setup-needed API-key-free provider, an expanded Advanced section, and an inline error state
- **And** the Appearance tab review includes at least four provider-order rows, threshold values, and the Vintage Mac toggle
- **And** the same provider badge is compared side-by-side with its popover card to confirm shared size, tint, inset, and fallback behavior.

## Plan

1. [x] **Extract focused shared visuals.** Move `ProviderLogoBadge` and the appearance-aware tier palette out of `QuotaView.swift` into `Sources/App/ProviderVisualStyle.swift`. Add a small set of shared provider-surface constants for badge geometry, card corner radius, and neutral fill. Keep concrete view composition in each owning view; do not introduce a broad theme framework.
2. [x] **Set the window layout.** Apply the default and minimum content sizes at the `Settings` scene/root content boundary in `AppMain.swift` or `SettingsView.swift`, whichever produces correct macOS Settings restoration behavior. Give each tab a vertical `ScrollView` with a centered, maximum-width content column and consistent outer padding.
3. [x] **Create settings-only surface components.** In `SettingsView.swift`, add small private views/modifiers such as `SettingsCard`, `SettingsCardHeader`, and `ProviderStatusPill`. The header accepts `ProviderInfo` plus generic status presentation data; it never switches on provider ID. Centralize status pill symbol, color role, and label resolution so API-key and API-key-free rows cannot drift.
4. [x] **Restyle the Providers tab.** Replace the outer flat `List` presentation with a lazy vertical stack of provider cards. Refactor `ProviderSettingsRow` and `APIKeyFreeSettingsRow` to share the card header while retaining their existing state-specific bodies and callbacks. Preserve instant Advanced expansion to avoid the current animated-`List` geometry bug even though the outer container is no longer a `List`; animation can be reconsidered only after it is verified artifact-free.
5. [x] **Restyle the Appearance tab.** Compose three cards: Provider order, Balance thresholds, and Menu bar icon. Keep the existing reorder persistence API. Use a reorder-capable macOS container inside the first card, or a focused drag/drop implementation if embedding `.onMove` without default `List` chrome is unreliable; either path must preserve keyboard and accessibility behavior from AC8.
6. [x] **Unify action and field styling.** Apply consistent control sizes, spacing, button prominence, and destructive roles across both provider auth shapes. Preserve all callbacks and validation rules; no Keychain, helper installer, provider state, refresh, `UserDefaults`, or networking code changes.
7. [x] **Localization and accessibility.** Add only genuinely new prose to the string catalog with all four supported locales. Add status symbols/text, help, accessibility values, and adaptive card borders. Verify glyphs stay decorative and controls retain native focus rings.
8. [ ] **Validation.** Run the repository's formatting/lint gate and full test suite, then perform the visual review matrix in AC12. Add focused pure-unit tests only if status presentation is extracted into a non-View resolver; do not add brittle pixel tests or a new UI-test dependency solely for this refactor.
   - Light- and dark-mode screenshots were inspected for both tabs at the `620 × 520` default and `520 × 420` content minimum. The review covered four provider-order rows, threshold values, configured API-key providers, ready API-key-free providers, and an expanded Advanced section. Unconfigured, setup-needed, and provider-error states still require manual review because producing them would mutate the developer's Keychain or helper installation.

No code is written until this spec is reviewed.

## Risks

- **Reordering inside a card.** SwiftUI's macOS `.onMove` behavior is tied to `List`, whose default background, selection, separators, and insets conflict with the new surface. A locally styled inner `List` may be sufficient; otherwise a custom drop delegate adds complexity and must preserve keyboard access. Implementation should prove the smallest reliable option before committing to custom drag/drop.
- **Settings size restoration.** macOS may restore a user's previous Settings window size instead of the new default. The minimum size must prevent clipping, while the default applies only when the system has no restored geometry; forcibly resetting user-resized geometry on every open is not acceptable.
- **Too much visual reuse.** The Settings window is wider and more interactive than the `280`-point popover. Shared badge, palette, radius, and surface treatment provide family resemblance, but copying the popover's tight padding or collapsed-card behavior verbatim would make forms cramped. Settings keeps roomier internal spacing and does not make whole provider cards collapsible.
- **Nested surfaces.** An inner reorder list, fields, and status pills can create too many borders against the outer card. Prefer whitespace and subtle inset separators; reserve outlines for focus, contrast accommodations, and actual controls.
- **Semantic color misuse.** Good/warning/critical colors communicate status in Settings, while balance tiers communicate remaining quota in the popover. Text and symbols must accompany Settings colors so green never becomes the only meaning, and neutral setup states must not imply an error.
- **Behavioral regression during row refactoring.** The two current provider row types encode many state-specific paths. Moving their common header must not merge their control logic: API keys stay in Keychain, API-key-free providers retain helper/setup flows, and base-URL controls stay absent from API-key-free providers.
- **Localization expansion.** Longer German and Spanish labels may wrap inside status pills or action rows. Cards must grow vertically and let status text wrap or move below the title instead of truncating essential state.
- **Orthogonality preserved.** Settings continues to render from `ProviderInfo`, `authShape`, and `ProviderState`. No provider module changes and no App-layer provider-ID branches are introduced, preserving (core 01) and (ui 14 AC3).

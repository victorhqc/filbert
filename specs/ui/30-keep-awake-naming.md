## Objective

Rename the sleep-prevention feature to the short, familiar name "Keep Awake" so the panel row reads without truncation.

## Context

- Amends the user-facing text of (ui 25). Behavior, IOKit assertions, durations, and layout stay unchanged.
- `Sources/App/SleepPreventionRow.swift` — the panel row label "Prevent Mac from sleeping" truncates to "Prevent Mac from sleepi…" at the panel's width.
- `Sources/App/AppearanceSettingsView.swift` — the Settings card heading and toggle use the old name.
- `Sources/App/MenuBarStatusIcon.swift`, `Sources/App/MenuBarProviderPresentation.swift` — append the old name to the menu-bar accessibility label.
- `Sources/App/Resources/Localizable.xcstrings` — replaces the old keys with new ones for en, de-DE, es-ES, and es-MX.
- `Tests/AppTests/MenuBarProviderPresentationTests.swift` — asserts the accessibility status text.
- "Keep Awake" is the established term in macOS keep-awake utilities. It is shorter and clearer than "Caffeinate", which is CLI jargon.

## Acceptance Criteria

### AC1: The panel row uses the new name
- **Given** the keep-awake row is visible (ui 25 AC1)
- **When** the Filbert panel opens at its default width
- **Then** the row label reads "Keep Awake" in full, with no truncation, next to the "for…" dropdown
- **And** active states read "Keep Awake" with "for <remaining time>" or "Until turned off" (ui 25 AC3, AC4)

### AC2: Settings uses the new name
- **Given** the Settings window is open on the Appearance tab
- **When** it renders
- **Then** the card heading reads "Keep Awake" and the toggle reads "Show Keep Awake"
- **And** the subtitle "Show a keep-awake timer in Filbert's panel" is unchanged

### AC3: Status and error text use the new name
- **Given** the feature is active, or IOKit fails to create the assertion
- **When** VoiceOver reads the menu-bar label or the panel shows the error
- **Then** the menu-bar status reads "Keep Awake active"
- **And** the selector's accessibility label reads "Keep Awake duration"
- **And** the error reads "Keep Awake couldn't start. Try again."

### AC4: Every locale is updated
- **Given** a de-DE, es-ES, or es-MX locale
- **When** the renamed strings render
- **Then** they use these translations, and no old key remains in `Localizable.xcstrings`:

| en | de-DE | es-ES / es-MX |
|----|-------|---------------|
| Keep Awake | Wach halten | No dormir |
| Show Keep Awake | „Wach halten“ anzeigen | Mostrar «No dormir» |
| Keep Awake active | „Wach halten“ aktiv | «No dormir» activo |
| Keep Awake duration | Dauer für „Wach halten“ | Duración de «No dormir» |
| Keep Awake couldn't start. Try again. | „Wach halten“ konnte nicht starten. Versuche es erneut. | No se pudo iniciar «No dormir». Inténtalo de nuevo. |

## Plan

1. [x] Replace the five `String(localized:)` keys at their call sites. Keep type names such as `SleepPreventionController` and the IOKit reason "Filbert sleep prevention", which only `pmset -g assertions` shows.
2. [x] Replace the matching catalog entries with the AC4 translations.
3. [x] Update the accessibility-status assertion in `MenuBarProviderPresentationTests`.
4. [ ] Check the panel in en, de-DE, and es-ES for truncation.

## Risks

- Users who learned the old name will see a different label. The control's position and the `sun.max.fill` mark stay the same, so this is low risk.

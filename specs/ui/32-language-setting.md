## Objective

Let the user choose Filbert's display language in Settings, and update all of Filbert's text at once, with no restart.

## Context

- Status: draft for review.
- Requires (ui 31) for the language list and `CFBundleLocalizations`. Changes how (ui 29) does lookups. See Plan.
- `Sources/App/GeneralSettingsView.swift` — the General tab. A new "Language" card goes after "Startup".
- Facts checked on 2026-10-18 with a compiled catalog:
  - `String(localized:bundle:locale:)` uses `locale` only to format values. It does not select the language. It returned English for `ru`.
  - `LocalizedStringResource` with `.locale` set selects the language. It resolved interpolation, Russian plurals (1 минута, 2 минуты, 5 минут, 21 минута), the fallback for `fr` to English, and `zh-Hans-CN` to `zh-Hans`. It is `Sendable`.
  - A sub-bundle for each `.lproj` folder gave a wrong Russian plural ("5 минуты"). Do not use it.
- Providers store finished text. `UsageLine.label` in `Sources/Core/ProviderProtocol.swift` is a `String`. Error and setup messages are made at fetch time. `providerDescription` is a `static let`, so it is computed one time. A live switch must make this text resolve at render time, not at fetch time.
- Formatters use `Locale.current`: `Sources/Core/QuotaFormatting.swift`, `CoarseDurationFormatting`, `PeakHoursBlock`, `UsageAmountFormatting`, `PacedUsageLineText`, `PeakHoursPresentation`, and `QuotaView` (`.formatted(.relative)`). Each must take the display locale.
- macOS keeps a per-app language in the `AppleLanguages` key of the app's own defaults domain. System Settings › General › Language & Region › Applications writes the same key. macOS reads it only at launch, for system-supplied text and for Sparkle's update dialogs.

## Acceptance Criteria

### AC1: The picker lists every language in its own name

- **Given** the General tab in Settings
- **When** the user opens the Language picker
- **Then** the first option is "System Default", in the current display language
- **And** the other options are the supported languages (ui 31), each in its own language: English, Deutsch, Español (México), Español (España), Português (Brasil), Português (Portugal), Русский, 简体中文.

### AC2: A fresh install follows macOS

- **Given** a fresh install
- **When** Settings opens
- **Then** the picker shows "System Default"
- **And** Filbert writes no `AppleLanguages` value.

### AC3: Filbert's text changes at once

- **Given** the popover and Settings are open
- **When** the user selects a language
- **Then** without a restart and without a network request, all of Filbert's text changes to that language in both windows. This includes tab labels, provider names and descriptions, usage lines, error and setup messages, forecasts, and the menu bar accessibility label
- **And** dates, durations, relative times, and numbers use that language's format
- **And** the Settings window stays on the General tab, and the provider cards keep their collapsed or expanded state.

### AC4: Text from macOS and Sparkle follows at the next launch

- **Given** the user selected a language
- **When** Filbert launches again
- **Then** Sparkle's update dialogs and other macOS-supplied text use that language too
- **And** before the relaunch, the card shows "Some system dialogs change after Filbert restarts." No restart button.

### AC5: The selection persists

- **Given** the user selected a language
- **When** Filbert quits and launches again
- **Then** it starts in that language.

### AC6: System Default follows macOS again

- **Given** a language is selected
- **When** the user selects "System Default"
- **Then** Filbert removes its `AppleLanguages` value
- **And** the text changes at once to the first supported language in the macOS language order.

### AC7: The picker agrees with System Settings

- **Given** the user set Filbert's language in System Settings › Language & Region › Applications
- **When** Filbert's Settings opens
- **Then** the picker shows that language.

### AC8: An unknown stored value is safe

- **Given** the stored `AppleLanguages` value has no supported language, for example `fr`
- **When** Filbert launches
- **Then** the picker shows "System Default", and Filbert shows English.

### AC9: Each lookup selects the display language

- **Given** any user-facing string in App, Core, or a provider
- **When** the source guard test (ui 29 AC1) scans the code
- **Then** the string comes from the Core lookup, with its module bundle and the display locale
- **And** a direct `String(localized:)` call fails the test.

### AC10: The picker is accessible

- **Given** VoiceOver is on
- **When** focus moves to the picker
- **Then** VoiceOver reads "Language" and the selected option.

## Plan

1. [x] Core lookup. `Sources/Core/DisplayLanguage.swift`: a lock-protected holder for the selected catalog language code, or `nil` for the system language. `String(displayLocalized:bundle:)` and `String(displayLocalized:)` build a `LocalizedStringResource` and resolve it with `DisplayLanguage.locale`. Do this before the (ui 29) sweep, so that each call site changes one time.
   - One locale serves every module. Core's own catalog languages are the available list, because (ui 31 AC3) gives every catalog the same languages.
   - With no selection, the whole macOS language order is matched, so `fr`, then `es-MX` resolves to `es-MX`. The macOS region is kept as a region override (`es_MX@rg=dezzzz`), so formats follow the region.
   - `Locale.preferredLanguages` includes Filbert's own `AppleLanguages` value. Step 5 must give `setSystemPreferences` the global-domain order, so "System Default" works before a relaunch.
2. [ ] Deferred provider text. In Core models, change the text that providers fill (usage line labels, setup and error messages, link labels, provider descriptions) from `String` to `LocalizedStringResource`. App resolves it when it renders. `providerDescription` becomes a computed value. Every provider changes, but only in Core's public types. No provider depends on another provider.
3. [ ] Formatters. Pass `DisplayLanguage.locale` to every formatter in Context, and set `.environment(\.locale)` on the popover and Settings roots.
4. [ ] Refresh views. The popover root and the Settings root observe the language and rebuild on a change. The Settings tab selection and the provider collapse state live above the rebuild, so they persist (AC3). The menu bar item updates its accessibility label.
5. [ ] Persistence. Add `AppLanguagePreference` in `Sources/App`. It reads and writes `AppleLanguages` only in the app's persistent domain, through an injected `UserDefaults`, and sets `DisplayLanguage` at launch and on change. Unit tests cover AC2, AC5, AC6, AC7, and AC8.
6. [ ] Add `SupportedLanguage` in `Sources/App` with a code and an autonym for each language. The picker and the catalog test (ui 29 AC3) read this one list.
7. [ ] Add the Language card to `GeneralSettingsView` (AC1, AC4, AC10).
8. [ ] Run the validation gate. Then manually check AC3 to AC7 in the packaged app for each language, with the popover and Settings open together.

## Risks

- Plan step 2 changes the provider protocol's public types. Every provider and many tests change. Do it as one Core change with mechanical updates to providers, before new languages are added.
- Text that a provider formats itself, such as a currency amount from `NumberFormatter`, is resolved at fetch time. It keeps the old number format until the next refresh. Words change at once, and only digit grouping or decimal marks can lag. If this is visible, move these formatters to render time as well.
- A rebuild of the view tree resets transient view state: scroll position, an open picker, or text typed in an API key field on another tab. Keep the API key draft state above the rebuild.
- `Locale.current` keeps the macOS region. The display locale must keep that region too (for example `es-MX` text with the German region). Otherwise the date order and the first weekday change when the user only wanted a different language.
- Under `swift run`, `Bundle.main` has no bundle identifier. The persistent-domain lookup must not crash. The live switch still works for that session.

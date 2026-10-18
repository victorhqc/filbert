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
2. [x] Deferred provider text (2026-10-18). Core's `DisplayText` holds a closure that builds the text. App resolves it when it renders. `ProviderQuota.headline` and `error`, `UsageLine.label`, `UsageDetail.label` and `value`, `ProviderState.setup` and `.error`, and the registry's configuration error are `DisplayText`. Provider metadata (`providerDescription`, `providerDisclaimer`, `setupHelp`) stays `String` but becomes computed, because the registry rebuilds `ProviderInfo` on each read. Every provider changes, but only through Core's public types. No provider depends on another provider.
   - `DisplayText` replaced `LocalizedStringResource`, for three reasons. Providers join formatted parts ("$12.34 left · resets in 2h"). Some values are raw, such as model codes. Errors resolve through `localizedDescription`. A closure covers all three, and the formatted parts, including currency, use the display locale at render time. `DisplayText(describing:)` keeps a caught error and resolves its description when shown.
   - Countdowns in headlines now update on each render, not only on each fetch.
3. [x] Formatters (2026-10-18). Pass `DisplayLanguage.locale` to every formatter in Context, and set `.environment(\.locale)` on the popover and Settings roots.
   - Also covered: weekday names and lists in `PeakHoursPresentation` and `PeakHoursBlock`, and Z.ai token counts.
   - Percentages used `String(format: "%.0f%%")`, which ignores the locale. They now share `QuotaFormatting.percentage`, in App and in every provider headline. It rounds half to even, like `%.0f`. The menu bar rounded half up before.
   - Three format keys take numbers: `%lld seconds`, `%lld minutes`, and `%lld× multiplier`. They are now interpolated lookups with the same keys, so the display locale formats the number and picks the plural form.
   - Number and percent formats follow the region, not the language. English with the German region gives "42 %" with a no-break space, as macOS does for a per-app language. `DisplayLanguage.setCurrentLocale` lets tests pin the region. Tests that compare English text pin `en_US` too, so they pass on any Mac.
   - `DisplayLocaleFormattingTests` checks durations, numbers, weekdays, and a language switch that keeps the region formats.
4. [ ] Refresh views. The popover root and the Settings root observe the language and rebuild on a change. The Settings tab selection and the provider collapse state live above the rebuild, so they persist (AC3). The menu bar item updates its accessibility label.
5. [ ] Persistence. Add `AppLanguagePreference` in `Sources/App`. It reads and writes `AppleLanguages` only in the app's persistent domain, through an injected `UserDefaults`, and sets `DisplayLanguage` at launch and on change. Unit tests cover AC2, AC5, AC6, AC7, and AC8.
6. [ ] Add `SupportedLanguage` in `Sources/App` with a code and an autonym for each language. The picker and the catalog test (ui 29 AC3) read this one list.
7. [ ] Add the Language card to `GeneralSettingsView` (AC1, AC4, AC10).
8. [ ] Run the validation gate. Then manually check AC3 to AC7 in the packaged app for each language, with the popover and Settings open together.

## Risks

- Plan step 2 changes the provider protocol's public types. Every provider and many tests change. Do it as one Core change with mechanical updates to providers, before new languages are added.
- Resolved by Plan step 2: text that a provider formats itself, such as a currency amount from `NumberFormatter`, now resolves at render time with the display locale.
- A rebuild of the view tree resets transient view state: scroll position, an open picker, or text typed in an API key field on another tab. Keep the API key draft state above the rebuild.
- `Locale.current` keeps the macOS region. The display locale must keep that region too (for example `es-MX` text with the German region). Otherwise the date order and the first weekday change when the user only wanted a different language.
- Under `swift run`, `Bundle.main` has no bundle identifier. The persistent-domain lookup must not crash. The live switch still works for that session.

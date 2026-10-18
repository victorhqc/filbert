## Objective

Resolve every user-facing string against its own module's String Catalog, so the app shows the user's language and never shows a raw key.

## Context

- Status: implemented, not yet on `main` (2026-10-18). Found during the manual check of (providers 17) on 2026-10-12. VoiceOver is checked with (ui 32) Plan step 8.
- (ui 01 AC7) requires all UI chrome in the active language. Today that does not hold.
- `Package.swift` processes each module's `Resources/Localizable.xcstrings` into that module's resource bundle. Only `Bundle.module` reads it.
- `String(localized:)` without `bundle:` reads `Bundle.main`. `Bundle.main` has no catalog, so the lookup returns the key. A key that is the English text looks correct. A name-style key shows raw.
- `scripts/build-dmg.sh` builds with the native build system and compiles each catalog inside its module bundle under `Contents/Resources/`. The packaged app has the same gap.
- The native build system copies `Localizable.xcstrings` raw into the module bundle, so even `bundle: .module` returns the key. Swift Build compiles it into `.lproj` folders. Swift 6.4 uses Swift Build by default; CI ran Swift 6.3.3 with the native build system, and the headline test failed there on 2026-10-12. Swift Build on Swift 6.3.3 does not copy the Sparkle framework next to the test bundles, so CI keeps the native build system and compiles the catalogs before `swift test --skip-build`, as `scripts/build-dmg.sh` does.
- Calls without `bundle:` on 2026-10-12 (re-counted on 2026-10-18: App 224, Core 4, Providers 136; unchanged in effect):
  - `Sources/App` — about 200; 13 calls pass `bundle: .module`.
  - `Sources/Core` — 4.
  - `Sources/Providers` — 138; none pass `bundle:`.
- `Sources/Providers/ClaudeCode` and `Sources/Providers/OpenAICodex` have no catalog.
- Name-style keys that still show raw: `Automatic selection description` and `Automatic selection accessibility hint` in `Sources/App/AppearanceSettingsView.swift`. The four format keys (`Forecast headline format`, `Forecast labeled value format`, `Accessibility sentence format`, `Peak hours day and time format`) already pass `bundle: .module`, fixed together with (providers 17).
- `packaging/Info.plist` sets `CFBundleDevelopmentRegion` to `en` and declares no `CFBundleLocalizations`.
- Catalog languages: `de-DE`, `en`, `es-ES`, `es-MX`. Source language `en`. (ui 31) adds `pt-BR`, `pt-PT`, `ru`, and `zh-Hans`. (ui 32) adds an in-app language setting on top of this spec.
- `Tests/AppTests/AllowanceForecastLocalizationTests.swift` checks a fixed list of forecast keys for translations and matching placeholders.

## Acceptance Criteria

### AC1: Every lookup names its module bundle

- **Given** any `String(localized:)` call in `Sources/App`, `Sources/Core`, or `Sources/Providers`
- **When** the source guard test scans the code
- **Then** the call goes through the Core lookup (ui 32 AC9) and passes `bundle: .module`, also when the call spans several lines
- **And** a new call without it fails the test.

### AC2: No raw key reaches the screen

- **Given** a name-style key, such as `Automatic selection description`
- **When** the view renders
- **Then** it shows the catalog text in the active language, never the key.

### AC3: Every key exists in its module's catalog

- **Given** a key used in a module's source
- **When** the catalog test runs
- **Then** the key exists in that module's catalog
- **And** it is translated in every supported language (ui 31)
- **And** each translation has the same placeholders as English
- **And** the test finds keys in the source, not from a fixed list
- **And** every catalog key has a lookup in its module's source, so no unused key gets translated.

### AC4: Every module with user-facing strings has a catalog

- **Given** Claude Code and Codex use `String(localized:)`
- **When** the modules build
- **Then** each has a `Resources/Localizable.xcstrings` with every supported language (ui 31)
- **And** `Package.swift` processes it like the other providers.

### AC5: The packaged app shows the user's language

- **Given** the user's preferred language is German or Spanish
- **When** the packaged app runs
- **Then** the popover, settings, and provider text appear in that language
- **And** an unsupported language falls back to English.

### AC6: Development and tests read the same catalogs

- **Given** `swift run` or `swift test`
- **When** a string resolves
- **Then** it reads the same module catalog as the packaged app.

## Plan

1. [x] Evidence. On a German system, open Settings in the packaged release. Check the "General" tab label, which already passes `bundle: .module`. "Allgemein" means module bundles pick the user's language. "General" means `packaging/Info.plist` needs `CFBundleLocalizations`, and step 5 is required.
   - 2026-10-18: step 5 was done anyway by (ui 31) Plan step 6. On the user's German Mac, Filbert shows German.
2. [x] Add the source guard test (AC1) and the generated catalog test (AC3) in `Tests/AppTests/StringCatalogCoverageTests.swift`, with the key scanner in `Tests/AppTests/LocalizedSourceScanner.swift`. `AllowanceForecastLocalizationTests` is removed. The tests cover Core, App, and all seven providers.
   - The guard first matched line by line, so it missed `String(` followed by `localized:` on the next line. One such call in `ProviderRegistry` was found during the provider sweep. The guard now matches across line breaks, and a probe file confirmed it.
   - Swift builds an interpolated key with one plain specifier per value (`"\(name): \(count)% used"` → `%@: %lld%% used`). A positional catalog key such as `%1$@: %2$lld%% used` never matches; this was verified with a compiled catalog. Two App keys had this form, so the menu bar and card header accessibility labels were never translated. They are re-keyed. Translations can still use positional placeholders.
   - Swift Build generates a symbol for each `manual` catalog key and fails on a key with no letters, such as `%lld%%`. Format such values in code instead: percentages use `.percent.locale(DisplayLanguage.locale)`, and a number range is not localized.
3. [x] Build the Core lookup first (ui 32, Plan step 1) [x]. Then move each call to it with `bundle: .module`, module by module: Core [x], App [x], then each provider together with (ui 32, Plan step 2) [x] (2026-10-18). The two `Automatic selection` keys resolve from the App catalog (AC2).
   - App sweep, 2026-10-18: 259 calls moved. 14 keys used in App were missing from the App catalog, and they are added in `de-DE`, `es-ES`, and `es-MX` per `docs/localization-glossary.md`. 14 App catalog keys are unused, mostly provider text that belongs in provider catalogs. Leave them for the provider sweep.
   - Tests that compare English text pin `DisplayLanguage.selectedLanguageCode = "en"`, in 7 test classes or their base classes.
   - Provider sweep, 2026-10-18: 144 calls moved. Before, every provider call read `Bundle.main` and showed English. 50 keys were missing from provider catalogs. DeepSeek and OpenCodeGo had English only. All are now in `de-DE`, `es-ES`, and `es-MX`. Translations already in another catalog are reused, with the glossary's "clave de API" in `es-MX`.
   - 20 unused keys are removed: 15 in App (provider text, plus dead `Panel` and `%@–%@ (your time)`), 4 in Cursor, and 1 in Core.
   - Claude Code had "Claude Code not found" and "Claude Code not found." Swift Build cannot give two keys that differ only by punctuation separate symbols. The error now uses the first text, as Codex does.
   - Provider tests that compare English text pin English too: 9 classes, plus `EnglishTestCase` for the 3 Cursor classes.
4. [x] Add catalogs for Claude Code and Codex, with translations (AC4).
5. [x] If step 1 requires it, declare the four languages in `packaging/Info.plist` (AC5).
   - (ui 31) Plan step 6 declares all eight languages, and `PackagedLocalizationsTests` keeps the list equal to `SupportedLanguage.all`.
6. [x] Compile the catalogs in CI before running the tests, so tests read compiled catalogs (AC6). Drop the step once CI uses Swift Build by default.
7. [x] Run the validation gate. Then manually check the popover, every settings tab, and each provider's states in German, Spanish, and English, at normal width and with VoiceOver.
   - 2026-10-18: the user checked the popover and every settings tab in each language, together with (ui 31) Plan step 7. VoiceOver and the provider error states move to (ui 32) Plan step 8.

## Risks

- German and Spanish text is longer. Rows, headlines, and settings labels can truncate or wrap where English fits. Step 6 must check every screen.
- Translations that no one has seen before appear at once. Some can be wrong or stale.
- System formatters already follow the user's locale. Until this lands, a German system shows mixed text, e.g. "resets in 2 Stunden". After it lands, the remaining mixed text points at a missed call.
- Test results can depend on the test runner's language. Tests that compare rendered text must use keys whose text is the same in every language, or set the locale explicitly.
- A string the code builds by joining parts can read wrong in another language. Prefer one format key over joining.
- Found on 2026-10-18, when Core moved to the Core lookup: Core text followed the German test machine, but App text was still English. `FallbackPoolPresentationTests` and `ClaudeCodeProviderTests` failed. Before, Core read `Bundle.main`, which has no catalog, and always returned English. A test that compares English text sets `DisplayLanguage.selectedLanguageCode = "en"` in `setUp` and clears it in `tearDown`.

## Objective

Resolve every user-facing string against its own module's String Catalog, so the app shows the user's language and never shows a raw key.

## Context

- Status: draft for review. Found during the manual check of (providers 17) on 2026-10-12.
- (ui 01 AC7) requires all UI chrome in the active language. Today that does not hold.
- `Package.swift` processes each module's `Resources/Localizable.xcstrings` into that module's resource bundle. Only `Bundle.module` reads it.
- `String(localized:)` without `bundle:` reads `Bundle.main`. `Bundle.main` has no catalog, so the lookup returns the key. A key that is the English text looks correct. A name-style key shows raw.
- `scripts/build-dmg.sh` builds with the native build system and compiles each catalog inside its module bundle under `Contents/Resources/`. The packaged app has the same gap.
- The native build system copies `Localizable.xcstrings` raw into the module bundle, so even `bundle: .module` returns the key. Swift Build compiles it into `.lproj` folders. Swift 6.4 uses Swift Build by default; CI ran Swift 6.3.3 with the native build system, and the headline test failed there on 2026-10-12. CI now builds and tests with `--build-system swiftbuild`.
- Calls without `bundle:` on 2026-10-12:
  - `Sources/App` — about 200; 13 calls pass `bundle: .module`.
  - `Sources/Core` — 4.
  - `Sources/Providers` — 138; none pass `bundle:`.
- `Sources/Providers/ClaudeCode` and `Sources/Providers/OpenAICodex` have no catalog.
- Name-style keys that still show raw: `Automatic selection description` and `Automatic selection accessibility hint` in `Sources/App/AppearanceSettingsView.swift`. The four format keys (`Forecast headline format`, `Forecast labeled value format`, `Accessibility sentence format`, `Peak hours day and time format`) already pass `bundle: .module`, fixed together with (providers 17).
- `packaging/Info.plist` sets `CFBundleDevelopmentRegion` to `en` and declares no `CFBundleLocalizations`.
- Catalog languages: `de-DE`, `en`, `es-ES`, `es-MX`. Source language `en`.
- `Tests/AppTests/AllowanceForecastLocalizationTests.swift` checks a fixed list of forecast keys for translations and matching placeholders.

## Acceptance Criteria

### AC1: Every lookup names its module bundle

- **Given** any `String(localized:)` call in `Sources/App`, `Sources/Core`, or `Sources/Providers`
- **When** the source guard test scans the code
- **Then** the call passes `bundle: .module`, also when the call spans several lines
- **And** a new call without it fails the test.

### AC2: No raw key reaches the screen

- **Given** a name-style key, such as `Automatic selection description`
- **When** the view renders
- **Then** it shows the catalog text in the active language, never the key.

### AC3: Every key exists in its module's catalog

- **Given** a key used in a module's source
- **When** the catalog test runs
- **Then** the key exists in that module's catalog
- **And** it is translated in `de-DE`, `en`, `es-ES`, and `es-MX`
- **And** each translation has the same placeholders as English
- **And** the test finds keys in the source, not from a fixed list.

### AC4: Every module with user-facing strings has a catalog

- **Given** Claude Code and Codex use `String(localized:)`
- **When** the modules build
- **Then** each has a `Resources/Localizable.xcstrings` with the four languages
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

1. [ ] Evidence. On a German system, open Settings in the packaged release. Check the "General" tab label, which already passes `bundle: .module`. "Allgemein" means module bundles pick the user's language. "General" means `packaging/Info.plist` needs `CFBundleLocalizations`, and step 5 is required.
2. [ ] Add the source guard test (AC1) and the generated catalog test (AC3). Both fail at first. Replace the fixed key list in `AllowanceForecastLocalizationTests` with the generated test.
3. [ ] Add `bundle: .module` module by module: App, Core, then each provider. Fix the two `Automatic selection` keys with the App (AC2).
4. [ ] Add catalogs for Claude Code and Codex, with translations (AC4).
5. [ ] If step 1 requires it, declare the four languages in `packaging/Info.plist` (AC5).
6. [x] Build and test CI with `--build-system swiftbuild`, so tests read compiled catalogs (AC6).
7. [ ] Run the validation gate. Then manually check the popover, every settings tab, and each provider's states in German, Spanish, and English, at normal width and with VoiceOver.

## Risks

- German and Spanish text is longer. Rows, headlines, and settings labels can truncate or wrap where English fits. Step 6 must check every screen.
- Translations that no one has seen before appear at once. Some can be wrong or stale.
- System formatters already follow the user's locale. Until this lands, a German system shows mixed text, e.g. "resets in 2 Stunden". After it lands, the remaining mixed text points at a missed call.
- Test results can depend on the test runner's language. Tests that compare rendered text must use keys whose text is the same in every language, or set the locale explicitly.
- A string the code builds by joining parts can read wrong in another language. Prefer one format key over joining.

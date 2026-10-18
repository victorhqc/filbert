## Objective

Ship Filbert in correct Mexican Spanish and Spain Spanish, and add Brazilian Portuguese, European Portuguese, Russian, Simplified Chinese, and Japanese.

## Context

- Status: in progress, not yet on `main`. Plan steps 1–7 are done (2026-10-18). Japanese was added on 2026-10-18; steps 8–11 cover it. Before a release, a native speaker reviews `ru`, `zh-Hans`, `pt-PT`, and `ja` (Risks).
- Builds on (ui 29). Its generated catalog test (ui 29 AC3) is the gate for every language in this spec.
- Catalog languages on 2026-10-18: `en` (source), `de-DE`, `es-ES`, `es-MX`.
- `es-ES` and `es-MX` are mostly copies of each other. Identical entries on 2026-10-18: App 201 of 222, Cursor 12 of 23, ZAI 5 of 9, GeminiCLI 29 of 29, Core 3 of 3.
- Neither Spanish variant is clean:
  - `es-MX` in App uses Spain wording: "Ajustes", "Abrir Ajustes", "Comprueba el acceso al llavero".
  - `es-ES` in GeminiCLI uses Latin American wording: "La autenticación falló", "devolvió una respuesta".
- DeepSeek and OpenCodeGo catalogs are English only. Claude Code and Codex have no catalog until (ui 29 AC4).
- Foundation language matching, checked on 2026-10-18 with `Bundle.preferredLocalizations`:
  - `es`, `es-ES` → `es-ES`. `es-MX`, `es-419`, `es-AR`, `es-US` → `es-MX`.
  - `pt`, `pt-BR` → `pt-BR`. `pt-PT` → `pt-PT`.
  - `zh-Hans`, `zh-CN`, `zh-Hans-CN` → `zh-Hans`. `zh-Hant` → `en`.
  - `de`, `de-AT` → `de-DE`.
  - `ja`, `ja-JP` → `ja`. `en-JP` → `en`.
  - The current codes need no rename. `es-MX` also serves all of Latin America.
- No catalog uses plural variations. `%lld seconds`, `%lld minutes`, and `%lld-hour window` (ZAI) read wrong for a count of 1 in English. Russian needs three forms (1 минута, 2 минуты, 5 минут).
- `packaging/Info.plist` declares no `CFBundleLocalizations`. Without it, macOS does not localize system-supplied UI and does not list Filbert under System Settings › General › Language & Region › Applications.
- Sparkle ships its own `de`, `es`, `pt_BR`, `pt_PT`, `ru`, `zh_CN`, and `ja` strings. Its update dialogs follow the same language selection.

## Acceptance Criteria

### AC1: Mexican Spanish reads as Mexican Spanish

- **Given** any `es-MX` string
- **When** a reviewer reads it
- **Then** it uses Mexican usage: "Configuración", simple past for finished events ("No se pudo", "falló"), "Revisa", and "ustedes" for plural address
- **And** the guard test fails on the denied terms in `docs/localization-glossary.md`, such as "Ajustes", "Comprueba", "ordenador", or a "vosotros" form.

### AC2: Spain Spanish reads as Spain Spanish

- **Given** any `es-ES` string
- **When** a reviewer reads it
- **Then** it uses peninsular usage: "Ajustes", present perfect for recent events ("No se ha podido", "ha fallado"), and "Comprueba"
- **And** an `es-ES` value that equals its `es-MX` value is correct in both variants. It is not a copy of the other variant.

### AC3: The five new languages are complete

- **Given** any key in any module catalog
- **When** the catalog test (ui 29 AC3) runs
- **Then** the key has a `translated` value in `pt-BR`, `pt-PT`, `ru`, `zh-Hans`, and `ja`
- **And** each value has the same placeholders as English.

### AC4: Counted strings agree with the count

- **Given** a string that shows a count, such as `%lld minutes`
- **When** the count is 1, 2, 5, or 21
- **Then** each language shows its correct plural form. English shows "1 minute" and "2 minutes". Russian shows "1 минута", "2 минуты", "5 минут", and "21 минута". Japanese, like Chinese, uses one form for every count.

### AC5: macOS picks the expected language

- **Given** the macOS preferred language in the left column
- **When** Filbert launches
- **Then** it shows the language in the right column:

| Preferred | Shown |
|---|---|
| Español (España), `es` | `es-ES` |
| Español (México), Español (Latinoamérica) | `es-MX` |
| Português (Brasil), `pt` | `pt-BR` |
| Português (Portugal) | `pt-PT` |
| Русский | `ru` |
| 简体中文 | `zh-Hans` |
| 日本語 | `ja` |
| 繁體中文, or any other unsupported language | `en` |

### AC6: The packaged app declares its languages

- **Given** the release build
- **When** `Contents/Info.plist` is read
- **Then** `CFBundleLocalizations` lists `en`, `de-DE`, `es-ES`, `es-MX`, `pt-BR`, `pt-PT`, `ru`, `zh-Hans`, and `ja`
- **And** Filbert appears under System Settings › General › Language & Region › Applications.

### AC7: Layouts hold in every language

- **Given** the longest translations (usually German, Russian, and Portuguese)
- **When** the popover and each settings tab open at their default sizes
- **Then** no label is truncated where English is not truncated. Chinese and Japanese text use full-width punctuation where it is normal.

## Plan

1. [x] Glossary in `docs/localization-glossary.md`. List about 25 recurring terms (Settings, API key, Keychain, menu bar, provider, refresh, retry, sign in, reset, usage, limit, credits, rate limited) for each language. Match Apple's own macOS terms, for example System Settings: "Configuración del Sistema" (`es-MX`), "Ajustes del Sistema" (`es-ES`), "Ajustes do Sistema" (`pt-BR`), "Definições do Sistema" (`pt-PT`), "Системные настройки" (`ru`), "系统设置" (`zh-Hans`). Add denied terms for each Spanish variant. The user reviews the glossary before any translation.
2. [x] Mexican Spanish audit. Read every `es-MX` string in every catalog and fix it against the glossary (AC1). Add the denied-term guard test. (2026-10-18)
   - All 358 strings in 9 catalogs were read. 42 values were fixed: "Configuración" for Settings, "clave de API", "Actualizar", "Reintentar", "Mantener activo", "restablecimiento" for a quota reset, "barra de menús", "Revisa", "costo", "íconos", "la Mac", “…” quotes, "solicitudes", and "Supervisa" in every provider description. Cursor's "Sign in to Cursor" link uses the infinitive, as a button does.
   - `testEachSpanishVariantAvoidsTheOtherVariantsTerms` in `StringCatalogCoverageTests` enforces both deny lists. On the committed catalogs it failed on 14 `es-MX` strings. It passes now. `es-ES` had no hits, so step 3 must still read every `es-ES` string.
   - Left for step 3: `es-ES` still says "No dormir", "reinicio", and Latin American past tenses. Left for step 4: `%lld-hour window` and the other counted strings.
3. [x] Spain Spanish pass. Rewrite `es-ES` in peninsular Spanish, without copying `es-MX` (AC2). (2026-10-18)
   - 40 values were fixed in App, Core, DeepSeek, OpenCodeGo, ZAI, and GeminiCLI. Changes: present perfect for recent events ("No se ha podido", "ha fallado", "ha devuelto", "Se ha agotado"), "Comprueba", "Mantener activo", "restablecimiento" and "se restablece" for a quota reset, "ritmo medio", "solicitudes", "Se ha cerrado la sesión", and "Supervisa" in every provider description.
   - GeminiCLI's `es-ES` was a copy of Latin American text, so 11 of its 29 strings changed.
   - 274 of 357 `es-ES` values still equal `es-MX`. Each was read. They use wording that is correct in both countries, and none uses a past tense.
   - "Reiniciar" stays for restarting Filbert. Only a quota reset uses "restablecer".
4. [x] Plural variations. Convert every counted key to plural variations in all languages (AC4). Prefer one format key over strings that join parts. (2026-10-18)
   - App: `%lld seconds` and `%lld minutes` have `one` and `other` forms in every language. The separate "1 minute" key is gone. `refreshDurationText` uses one key for every count.
   - ZAI: `%lld-hour window` has plural forms in Spanish ("Ventana de 1 hora"). The English and German compounds don't change with the count ("1-hour window", "1-Stunden-Fenster"), so they keep one value. Codex's `%lld-minute window` already had Spanish forms.
   - Not counted nouns, so not plural: `%lld× multiplier`, `under %lld`, `%lld and up`, percentages, and the exit code. The sleep durations ("5 minutes", "1 hour", "2 hours") are fixed keys, one per menu item.
   - `testEveryPluralHasTheFormsItsLanguageNeeds` checks the CLDR forms for each language: `one` and `other` by default, four for `ru`, and only `other` for `zh-Hans`. Step 5 must add plural variations for `ru` wherever the noun changes with the count.
   - Credits arrive as formatted text with two decimals ("1.00 credits"), so they can't use plural variations. The glossary says how to phrase them.
5. [x] New languages, one module at a time: App, Core, then each provider (AC3). Extend the catalog test's language list. (2026-10-18)
   - All 357 keys in 9 catalogs have `pt-BR`, `pt-PT`, `ru`, and `zh-Hans` values. `SupportedLanguage.all` lists the four languages, so the picker shows them and the catalog test requires them.
   - Before writing, the ⚠︎ terms were checked in Apple's Mac User Guide (`mh26684`) for each locale: Idioma / Язык / 语言, caixa de diálogo / диалоговое окно / 对话框, and "o Mac". Codex credits use OpenAI's 积分. DeepSeek balances use its own 赠金余额 and 充值余额. "average" and Z.ai's 消耗速率 are still ⚠︎ for the native review.
   - Russian durations arrive in the nominative, so no string puts one after a word that needs another case. Colons and parentheses carry them instead. The glossary records this rule.
   - Russian and Chinese counted windows use forms that don't change with the count ("5-часовое окно", "5 小时窗口"). Portuguese uses plural variations.
   - `DisplayLanguageTests` covers the AC5 table, a lookup in each new language, and Chinese text joined to a relative date without a space. `AppLanguagePreferenceTests` covers Traditional Chinese from System Settings, which shows System Default in English.
   - GeminiCLI's `de-DE` used "Sie". Step 6 fixed it.
6. [x] Declare `CFBundleLocalizations` in `packaging/Info.plist` (AC6). (2026-10-18)
   - The app bundle has no `.lproj` folders, because the catalogs live in the SwiftPM resource bundles. `CFBundleLocalizations` is how macOS learns the languages.
   - `PackagedLocalizationsTests` checks that the list equals `SupportedLanguage.all`, so a new language can't miss the plist.
   - An unsigned local DMG (`scripts/build-dmg.sh --no-sign --skip-launch-check`) has the eight languages in `Contents/Info.plist`, and `filbert_App.bundle` has eight `.lproj` folders. The System Settings listing is checked by hand in step 7.
   - German follows Apple's Mac User Guide, which uses "du". GeminiCLI's 11 "Sie" strings now use "du". "Versuch es später nochmal" in DeepSeek, OpenCode Go, and Z.ai is now "Versuche es später erneut". `testEveryLanguageAvoidsItsDeniedTerms` (renamed from the Spanish-only test) denies "Sie", "Ihnen", "Ihr…", and "nochmal" in `de-DE`.
7. [x] Run the validation gate. Then manually check AC5 and AC7 in each language: the popover, every settings tab, the error states, and VoiceOver. (2026-10-18)
   - The gate passes: 1054 tests, also on the native build path with compiled catalogs.
   - The user checked AC5 (macOS picks the language; their Mac runs German and Filbert follows), AC6 (Filbert appears in Language & Region › Applications), and AC7 (no truncation in the popover and the settings tabs).
   - VoiceOver and the provider error states were not part of this check. (ui 32) Plan step 8 covers them.
8. [ ] Japanese glossary. Add a `ja` column to the Conventions and Terms tables in `docs/localization-glossary.md`. Take each term from Apple's Mac User Guide in `ja-jp` and Google's docs with `hl=ja`. Record how Apple addresses the user and phrases buttons, its quotes (「…」), and whether it puts a space between Japanese and Latin letters or digits ("Mac の"). The user reviews the column before any translation.
9. [ ] Japanese catalogs, one module at a time: App, Core, then each provider (AC3). Add `ja` to `SupportedLanguage.all` as "日本語". Add `"ja": ["other"]` to the catalog test's plural forms, so every counted string has one `other` form (AC4).
10. [ ] Add `ja` to `CFBundleLocalizations` (AC6). Extend the language tables in `DisplayLanguageTests` (AC5, a lookup, and relative dates joined to Japanese text), `DisplayLocaleFormattingTests`, `ZAIWindowLabelTests`, and `AppLanguagePreferenceTests`.
11. [ ] Run the validation gate. Then manually check AC5 and AC7 in Japanese: the popover, every settings tab, and Language & Region › Applications.

## Risks

- The agent writes the translations and follows the sources of truth in `docs/localization-glossary.md`. The user arranges a native speaker's review of Russian, Simplified Chinese, European Portuguese, and Japanese before a release.
- The work changes about 357 keys in 9 catalogs, for 8 languages. Review the work module by module, not as one diff.
- Russian and Portuguese text is long. Some rows can wrap or truncate (AC7).
- Japanese has no spaces between words, so a long label can break at any character. Check the popover rows for odd breaks (AC7).
- Plural variations change the catalog shape for the affected keys. Tests that read the catalog JSON must accept both a `stringUnit` value and a `variations` value.
- Users who use `es-ES` and see Mexican text today will see different text after the release. This is the expected fix.

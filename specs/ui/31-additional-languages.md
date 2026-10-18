## Objective

Ship Filbert in correct Mexican Spanish and Spain Spanish, and add Brazilian Portuguese, European Portuguese, Russian, and Simplified Chinese.

## Context

- Status: draft for review.
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
  - The current codes need no rename. `es-MX` also serves all of Latin America.
- No catalog uses plural variations. `%lld seconds`, `%lld minutes`, and `%lld-hour window` (ZAI) read wrong for a count of 1 in English. Russian needs three forms (1 минута, 2 минуты, 5 минут).
- `packaging/Info.plist` declares no `CFBundleLocalizations`. Without it, macOS does not localize system-supplied UI and does not list Filbert under System Settings › General › Language & Region › Applications.
- Sparkle ships its own `de`, `es`, `pt_BR`, `pt_PT`, `ru`, and `zh_CN` strings. Its update dialogs follow the same language selection.

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

### AC3: The four new languages are complete

- **Given** any key in any module catalog
- **When** the catalog test (ui 29 AC3) runs
- **Then** the key has a `translated` value in `pt-BR`, `pt-PT`, `ru`, and `zh-Hans`
- **And** each value has the same placeholders as English.

### AC4: Counted strings agree with the count

- **Given** a string that shows a count, such as `%lld minutes`
- **When** the count is 1, 2, 5, or 21
- **Then** each language shows its correct plural form. English shows "1 minute" and "2 minutes". Russian shows "1 минута", "2 минуты", "5 минут", and "21 минута".

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
| 繁體中文, or any other unsupported language | `en` |

### AC6: The packaged app declares its languages

- **Given** the release build
- **When** `Contents/Info.plist` is read
- **Then** `CFBundleLocalizations` lists `en`, `de-DE`, `es-ES`, `es-MX`, `pt-BR`, `pt-PT`, `ru`, and `zh-Hans`
- **And** Filbert appears under System Settings › General › Language & Region › Applications.

### AC7: Layouts hold in every language

- **Given** the longest translations (usually German, Russian, and Portuguese)
- **When** the popover and each settings tab open at their default sizes
- **Then** no label is truncated where English is not truncated. Chinese text uses full-width punctuation where it is normal.

## Plan

1. [ ] Glossary in `docs/localization-glossary.md`. List about 25 recurring terms (Settings, API key, Keychain, menu bar, provider, refresh, retry, sign in, reset, usage, limit, credits, rate limited) for each language. Match Apple's own macOS terms, for example System Settings: "Configuración del Sistema" (`es-MX`), "Ajustes del Sistema" (`es-ES`), "Ajustes do Sistema" (`pt-BR`), "Definições do Sistema" (`pt-PT`), "Системные настройки" (`ru`), "系统设置" (`zh-Hans`). Add denied terms for each Spanish variant. The user reviews the glossary before any translation.
2. [ ] Mexican Spanish audit. Read every `es-MX` string in every catalog and fix it against the glossary (AC1). Add the denied-term guard test.
3. [ ] Spain Spanish pass. Rewrite `es-ES` in peninsular Spanish, without copying `es-MX` (AC2).
4. [ ] Plural variations. Convert every counted key to plural variations in all languages (AC4). Prefer one format key over strings that join parts.
5. [ ] New languages, one module at a time: App, Core, then each provider (AC3). Extend the catalog test's language list.
6. [ ] Declare `CFBundleLocalizations` in `packaging/Info.plist` (AC6).
7. [ ] Run the validation gate. Then manually check AC5 and AC7 in each language: the popover, every settings tab, the error states, and VoiceOver.

## Risks

- The agent writes the translations and follows the sources of truth in `docs/localization-glossary.md`. The user arranges a native speaker's review of Russian, Simplified Chinese, and European Portuguese before a release.
- The work changes about 330 keys in 8 catalogs, for 7 languages. Review the work module by module, not as one diff.
- Russian and Portuguese text is long. Some rows can wrap or truncate (AC7).
- Plural variations change the catalog shape for the affected keys. Tests that read the catalog JSON must accept both a `stringUnit` value and a `variations` value.
- Users who use `es-ES` and see Mexican text today will see different text after the release. This is the expected fix.

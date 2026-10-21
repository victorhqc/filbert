## Objective

Replace "refresh" with "usage check" wording and "Keep Awake" with "Keep Mac Awake" in every language, so each string says what it does.

## Context

- Status: approved 2026-10-21. Plan steps 1–6 are done. Step 7 found truncation (see the AC5 finding); waiting for the user's decision.
- Feedback from a Russian speaker: the Russian for "Refresh" reads like "update". Feedback from a Taiwanese speaker: 「防止睡眠」 ("Keep Awake") was confusing.
- The Russian collision is real. Russian uses обновление for both a data refresh and a software update, and Settings shows both side by side:
  - "Refresh Settings" is «Настройки обновления»; the "Updates" section is «Обновления».
  - "Automatic refresh" is «Автоматическое обновление»; "Automatic updates…" is «Автоматические обновления…».
- The root cause is in English. "Refresh" names the mechanism, not the result. The new wording names what Filbert does: it checks each provider's usage. The app already calls the Smart-mode polls "fast checks", so "usage check" joins an existing term.
- "Usage", not "token usage". Not every provider reports tokens: Cursor reports spend, DeepSeek a balance, Claude Code a percentage of a limit. "Usage" is the term the app and the glossary already use for all of them.
- "Keep Awake" has no object in English or in any locale. (ui 30) chose it to stop "Prevent Mac from sleeping" from truncating. "Keep Mac Awake" adds the object at a cost of four characters.
- Amends the user-facing text of (ui 25), (ui 30), (ui 35), and the refresh settings text of (core 11). Behavior stays the same.
- Translations convey the meaning of the English, in each language's own idiom. They are not word-for-word.
- `Sources/App/SleepPreventionRow.swift`, `AppearanceSettingsView.swift`, `MenuBarStatusIcon.swift`, `MenuBarProviderPresentation.swift` — Keep Awake call sites.
- `Sources/App/QuotaView.swift`, `QuotaViewModel+Results.swift`, `RefreshSettingsView.swift`, `RefreshSettingsProviderRow.swift`, `SettingsView.swift`, `AllowanceForecastPresentation.swift` — refresh call sites.
- `Sources/Providers/ClaudeCode/ClaudeCodeRefresher.swift`, `StatuslineCacheStore.swift`, `Sources/Providers/GeminiCLI/GeminiCLIError.swift` — refresh wording in provider errors. Each provider changes only its own strings and catalog.
- `Sources/App/Resources/Localizable.xcstrings`, and the ClaudeCode and GeminiCLI catalogs — old keys replaced in all ten locales.
- `Tests/AppTests/MenuBarProviderPresentationTests.swift`, `DisplayLanguageModelTests.swift`, `AllowanceForecastPresentationTests.swift` — assert old English or German text.
- `docs/localization-glossary.md` — the Refresh, Update, and Keep Awake rows, and the "Refresh in provider errors" rule.
- `site/index.html` — the "Smart refresh" and "Keep Awake" cards. `README.md` — the user-facing "Automatic refresh" section and the "click **Refresh**" note.
- The catalog test (ui 29 AC3) is the gate for keys and placeholders.

## Acceptance Criteria

### AC1: English names the Mac

- **Given** the app in English
- **When** the panel, Settings, VoiceOver, or the landing page shows the feature
- **Then** the text reads:

| Old | New |
|-----|-----|
| Keep Awake | Keep Mac Awake |
| Show Keep Awake | Show Keep Mac Awake |
| Keep Awake active | Keep Mac Awake active |
| Keep Awake duration | Keep Mac Awake duration |
| Keep Awake couldn't start. Try again. | Keep Mac Awake couldn't start. Try again. |
| After a restart, Filbert turns Keep Awake back on if it was set to Until turned off. | After a restart, Filbert turns Keep Mac Awake back on if it was set to Until turned off. |
| Show a keep-awake timer in Filbert's panel | Show a Keep Mac Awake timer in Filbert's panel |

- **And** no old key remains in any catalog.

### AC2: Every locale names the Mac

- **Given** any supported locale
- **When** the AC1 strings render
- **Then** the feature name is the one below, and every AC1 string uses it with the locale's quotes:

| Locale | Old | New | Source |
|--------|-----|-----|--------|
| de-DE | Wach halten | Mac wach halten | — |
| es-ES | Mantener activo | Mantener el Mac activo | glossary article "el Mac" |
| es-MX | Mantener activo | Mantener la Mac activa | glossary article "la Mac" |
| pt-BR, pt-PT | Manter ativo | Manter o Mac ativo | — |
| ru | Не засыпать | Не давать Mac уснуть | native reviewer, 2026-10-21 |
| zh-Hans | 保持唤醒 | 保持 Mac 唤醒 | — |
| zh-Hant | 防止睡眠 | 防止Mac進入睡眠 | macOS Battery: 「防止Mac…自動進入睡眠」 |
| ja | スリープさせない | Macをスリープさせない | macOS Battery: 「…自動でスリープさせない」 |

### AC3: English says "usage check", not "refresh"

- **Given** the app in English
- **When** any of these strings render
- **Then** they read:

| Where | Old | New |
|-------|-----|-----|
| Panel, card button tooltip | Refresh | Check usage now |
| Panel, card error | Refresh canceled. Select Refresh to try again. | Usage check canceled. Try again. |
| Panel, card badge; menu-bar VoiceOver | Fast refresh active | Fast checks on |
| Panel, under "Last updated by %@" | Open %@ to refresh | Open %@ to get newer usage |
| Panel, forecast row | Refreshes too far apart to estimate | Checks too far apart to estimate |
| Settings sidebar, page title | Refresh Settings | Usage Checks |
| Settings card heading; provider toggle | Automatic refresh | Automatic usage checks |
| Settings card description | Choose which providers refresh automatically. Mode and intervals control how often. | Choose which providers Filbert checks automatically. The schedule and intervals set how often. |
| Settings picker | Refresh mode | Check schedule |
| Settings, no provider on | Turn on automatic refresh for each provider you want to check. | Turn on automatic checks for each provider you want to track. |
| Settings, Regular explanation | Regular refresh checks opted-in providers %@. | The Regular schedule checks the selected providers %@. |
| Settings, Smart explanation | Smart refresh checks %1$@. After a usage change, a provider checks %2$@ for %3$@, then %4$@ for another %3$@ before returning to the slow interval. | The Smart schedule checks %1$@. When usage changes, it checks that provider %2$@ for %3$@, then %4$@ for another %3$@, and then returns to the slow interval. |
| Settings, toggle VoiceOver label | Automatic refresh for %@ | Automatic usage checks for %@ |
| Settings, toggle help | Toggle periodic refresh for this provider. | Turn automatic usage checks on or off for this provider. |
| Settings, provider off | Automatic refresh is paused because this provider is disabled. | Automatic checks are paused because this provider is disabled. |
| Settings, provider not set up | Automatic refresh is waiting for setup. | Automatic checks start after setup. |
| Settings, Stop fast checks help | Stopping ends the fast checks early. Automatic refresh stays on and the normal Smart timing resumes. | Stopping ends the fast checks early. Automatic checks stay on, and the normal Smart schedule resumes. |
| Claude Code error | Claude Code refresh failed with exit code %d. Open Claude Code and retry. | Couldn't check Claude Code usage (exit code %d). Open Claude Code and try again. |
| Claude Code error | Claude Code refresh timed out. Retry the refresh. | The Claude Code usage check timed out. Try again. |
| Claude Code error | Could not prepare Claude Code refresh. Retry the refresh. | Couldn't start the Claude Code usage check. Try again. |
| Claude Code error | Could not decode Claude Code usage data. Refresh to retry. | Claude Code usage data is in an unexpected format. Try again. |
| Claude Code error | Could not read Claude Code usage data. Refresh to retry. | Couldn't read Claude Code usage data. Try again. |
| Gemini CLI error | Sign in to Gemini CLI before refreshing usage. | Sign in to Gemini CLI so Filbert can check its usage. |

- **And** no catalog key or English value contains "refresh".
- **And** "Last updated: %@", "Regular", "Smart", "Slow interval", "Fast interval", "Keep checking", and the fast-check strings stay as they are.
- **And** the landing-page card "Smart refresh" reads "Smart usage checks", and the README's user-facing section reads "Automatic usage checks".

### AC4: Every locale says "usage check", in its own idiom

- **Given** any supported locale
- **When** an AC3 string renders
- **Then** it conveys the AC3 English meaning with the terms below, consistent with the existing fast-check terms
- **And** no data-check string uses the word the locale uses for a software update:

| Term | de-DE | es-ES / es-MX | pt-BR | pt-PT | ru | zh-Hans | zh-Hant | ja |
|------|-------|---------------|-------|-------|----|---------|---------|----|
| Check usage now | Nutzung jetzt prüfen | Consultar uso ahora | Verificar uso agora | Verificar utilização agora | Проверить использование (native reviewer, 2026-10-21) | 立即检查用量 | 立即檢查用量 | 今すぐ使用量を確認 |
| usage check | Nutzungsprüfung | consulta de uso | verificação de uso | verificação da utilização | проверка использования | 用量检查 | 用量檢查 | 使用量の確認 |
| Usage Checks (settings page) | Nutzungsprüfung | Consultas de uso | Verificações de uso | Verificações da utilização | Проверка использования | 用量检查 | 用量檢查 | 使用量の確認 |
| Automatic usage checks | Automatische Nutzungsprüfung | Consultas automáticas de uso | Verificação automática de uso | Verificação automática da utilização | Автоматическая проверка использования | 自动检查用量 | 自動檢查用量 | 使用量の自動確認 |
| Check schedule | Prüfrhythmus | Frecuencia de consulta | Frequência de verificação | Frequência de verificação | График проверок | 检查频率 | 檢查頻率 | 確認の頻度 |
| existing: fast checks | schnelle Prüfungen | consultas rápidas | verificações rápidas | verificações rápidas | быстрые проверки | 快速检查 | 快速檢查 | 高速確認 |
| avoid (software update) | Update, Aktualisierung | actualización | atualização | atualização | обновление, обновить | 更新 | 更新 | 更新, アップデート |

### AC5: Labels fit

- **Given** the panel at its default width
- **When** it shows the Keep Mac Awake row in each locale, idle and active
- **Then** the row label uses a font 1 point smaller than before: `.subheadline` (11 pt) instead of `.callout` (12 pt)
- **And** the label shows in full next to the duration menu, with no truncation.
- **Given** the Settings sidebar, the Usage Checks card, and the card badge "Fast checks on"
- **When** they render in each locale
- **Then** each label shows in full.

Finding, 2026-10-21. An offscreen render of a copy of the row at 280 pt (not a screenshot of the real panel) shows:
- Idle ("for…"): the label fits in every locale except es-ES and es-MX («Mantener el Mac act…»).
- Active ("Until turned off" or a countdown): the label truncates in en, de-DE, es-ES, es-MX, pt-BR, pt-PT, ru, and ja. It fits in zh-Hans and zh-Hant.
- The duration menu draws its own pop-up indicator, and the row adds a second `chevron.up.chevron.down`. Together they take about 40 pt.
- Measured at 11 pt, "Keep Mac Awake" is 88 pt wide. "Keep Awake" was 68 pt at 12 pt. The ru name grows from 74 to 119 pt.
- The "Fast checks on" badge is narrower than the old text in every locale except pt-BR, pt-PT (+14 pt), and ja (+19 pt). "Usage Checks" is narrower than "Refresh Settings" except in ru (+14 pt) and ja (+25 pt). Both still need the real-app check.

### AC6: The glossary records the decision

- **Given** `docs/localization-glossary.md`
- **When** a translator looks up these terms
- **Then** the Refresh row is replaced by the AC4 rows
- **And** the Keep Awake row is renamed "Keep Mac Awake" with the AC2 values
- **And** the "Refresh in provider errors" rule is replaced by: a usage check reads and shows usage data. It never uses the locale's software-update word, because Filbert's update strings use it
- **And** the de-DE note on "Update (install button)" no longer says "Aktualisieren is Refresh".

## Plan

1. [x] Update the glossary (AC6).
2. [x] Replace the seven Keep Awake keys at their call sites with the AC1 keys. Change the panel row label font from `.callout` to `.subheadline` (AC5).
3. [x] Replace the 23 refresh keys at their call sites with the AC3 keys, in App, ClaudeCode, and GeminiCLI. Keep type and property names such as `RefreshSettingsView` and `fastRefreshStatus`.
4. [x] Write the new catalog entries for all ten locales from the AC3 English and the AC4 terms. Remove the old entries.
5. [x] Update the tests that assert old text, the `site/index.html` cards, and the README's user-facing section.
6. [x] Run `swift test`. The catalog test must pass, and no key or English value contains "refresh".
7. [ ] Check AC5 in the running app for every locale. If a label still truncates, report it before shortening anything.
8. [ ] Native review: send the new ru and zh-Hant strings to the two reviewers.

## Risks

- Users who learned "Refresh" and "Keep Awake" see new names. Positions, the ↻ button icon, and the `sun.max.fill` mark stay the same.
- es-ES, es-MX, and ru Keep Mac Awake names are the longest (20–22 characters). They are the likeliest to truncate (AC5).
- Provider error keys change, so any provider test that asserts error text must change with them.
- Except the confirmed ru terms, the AC4 terms come from a non-native writer. Treat them as a proposal until step 8.

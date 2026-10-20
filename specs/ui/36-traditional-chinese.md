## Objective

Add Traditional Chinese (`zh-Hant`, Taiwan usage) to every Filbert string catalog and to the language picker.

## Context

- Status: spec approved 2026-10-20. Plan steps 1–8 are done (2026-10-20). Step 9 (native review) is done; the user's manual check (step 10) is open.
- Builds on (ui 31) and (ui 32). Follows the Japanese pattern of (ui 31) Plan steps 8–11: a glossary column first, the user reviews it, then the catalogs.
- The catalog test (ui 29 AC3) is the gate. On 2026-10-20 the 9 catalogs hold 380 keys: App 245, GeminiCLI 29, Cursor 25, Claude Code 20, Codex 16, OpenCode Go 16, DeepSeek 13, Z.ai 11, Core 5.
- Foundation language matching, checked on 2026-10-20 with `Bundle.preferredLocalizations` and `zh-Hant` added to the current languages:
  - `zh-Hant`, `zh-Hant-TW`, `zh-TW`, `zh-HK`, `zh-Hant-HK`, `zh-MO`, `zh-Hant-MO`, `yue-Hant` → `zh-Hant`.
  - `zh-Hans`, `zh-CN`, `zh-SG`, `zh` → `zh-Hans`. No change.
  - One `zh-Hant` catalog serves Taiwan, Hong Kong, and Macau. No `zh-TW` or `zh-HK` split is needed.
- Today `zh-Hant` falls back to English. Two tests lock that in, and this spec reverses them:
  - `Tests/CoreTests/DisplayLanguageTests.swift` — `testUnsupportedLanguage_fallsBackToEnglish` lists `zh-Hant`, `zh-Hant-TW`, `zh-HK`.
  - `Tests/AppTests/AppLanguagePreferenceTests.swift` — `testTraditionalChineseFromSystemSettingsShowsSystemDefault`.
- `Sources/App/SupportedLanguage.swift` — the picker list and the catalog test's language list.
- `packaging/Info.plist` — `CFBundleLocalizations`. `PackagedLocalizationsTests` requires it to equal `SupportedLanguage.all`.
- `docs/localization-glossary.md` — gets a `zh-Hant` column in the Conventions and Terms tables, a deny list, and sources.
- `site/index.html` — the "Speaks your language" card says "Chinese". It changes to name both scripts.
- macOS's own `zh_TW` UI strings (the `.loctable` files under `/System`, 121 files, 23,645 strings) set the style. It differs from the `zh-Hans` column in the glossary:
  - Quotes are 「…」 (2,216 strings), not “…” (1 string).
  - The ellipsis is ⋯ (U+22EF): "設定⋯", "載入中⋯".
  - No space between Han and Latin letters or digits (2,450 strings, against 7 with a space): "使用Siri的權限".
  - Full-width ，。：？！（）.
  - Address is 你.
- macOS `zh_TW` terms: 設定 (Settings), 系統設定, 鑰匙圈 (Keychain), 重新整理 (Refresh), 再試一次 (Try Again), 登入, 登出, 重置 (Reset), 預設值 (Default), 帳號, 網路, 結束 (Quit), 簡介 (About), 一般 (General), 外觀 (Appearance), 語言與地區, 軟體更新, 剩餘, 錯誤, 限制, 視窗.
- Foundation in `zh-Hant`: durations "9天3小時", "5分鐘"; relative dates "2小時後", "1週後"; weekdays "週一"; percent "19.6%".
- Sparkle ships `zh_TW` and `zh_HK`. A `zh-Hant` selection shows Sparkle's `zh_TW` text. A Hong Kong system language shows `zh_HK`.
- The ICU transform `Hans-Hant` leaves Traditional text unchanged and changes Simplified characters ("设置" → "設置", "钥匙串" → "鑰匙串"). It can detect Simplified characters in a `zh-Hant` value. It also changes 周 to 週, so 周 needs an exception if a string uses it on purpose.
- Terms are researched, not guessed. Every term comes from how real platforms say it in Traditional Chinese, and Taiwan usage wins when sources disagree. The source order is in Plan step 1. Platforms to check, at least:
  - Apple: macOS `zh_TW` `.loctable` strings, `support.apple.com/zh-tw`, `developer.apple.com` in `zh-TW`.
  - Google: `ai.google.dev` and Gemini docs with `hl=zh-TW`, Google Cloud docs in `zh-TW`.
  - OpenAI: ChatGPT and Codex UI in 繁體中文, `help.openai.com` in `zh-Hant`, OpenAI's pricing and usage pages.
  - Anthropic: Claude and Claude Code UI and docs in 繁體中文, `support.anthropic.com` in `zh-TW`.
  - Cursor: `cursor.com` and `docs.cursor.com` in 繁體中文.
  - DeepSeek and Z.ai: their own docs and consoles. These are likely Simplified only; then check Traditional Chinese coverage of them in Taiwan media.
  - Microsoft: the Microsoft Terminology collection and Learn docs in `zh-TW`, a large source of standard Taiwan software terms.
  - Taiwan's National Academy for Educational Research term database (`terms.naer.edu.tw`), for Taiwan's official equivalents of technical terms.
  - A general web search in Traditional Chinese, preferring Taiwan sites (`.tw` domains, iThome, INSIDE, TechNews 科技新報), to confirm what Taiwanese users actually say.

## Acceptance Criteria

### AC1: Every key has a Traditional Chinese value

- **Given** any key in any of the 9 module catalogs
- **When** the catalog test (ui 29 AC3) runs
- **Then** the key has a `translated` `zh-Hant` value with the same placeholders as English.

### AC2: macOS picks Traditional Chinese

- **Given** the macOS preferred language in the left column, and Filbert on System Default
- **When** Filbert launches
- **Then** it shows the language in the right column:

| Preferred | Shown |
|---|---|
| 繁體中文, 繁體中文（台灣）, 繁體中文（香港）, `zh-MO` | `zh-Hant` |
| 简体中文, `zh-CN`, `zh-SG` | `zh-Hans` |
| `fr`, or any other unsupported language | `en` |

### AC3: The picker offers Traditional Chinese

- **Given** the language picker in Settings (ui 32)
- **When** the user opens it
- **Then** "繁體中文" appears directly after "简体中文"
- **And** selecting it changes the text at once, with no relaunch (ui 32)
- **And** the choice persists across a relaunch.

### AC4: The text is Traditional Chinese, Taiwan usage

- **Given** any `zh-Hant` value
- **When** the guard test runs
- **Then** the value contains no Simplified character: the `Hans-Hant` transform leaves it unchanged, except for exceptions listed in the glossary
- **And** the value contains none of the mainland terms in the `zh-Hant` deny list, such as 設置, 默認, 菜單, 軟件, 信息, 網絡, 賬號, 屏幕, 鑰匙串
- **And** the value is written from the English source, not converted character by character from `zh-Hans`.

### AC5: Every glossary term has a researched source

- **Given** any `zh-Hant` term in `docs/localization-glossary.md`
- **When** a reviewer reads its row and the sources list
- **Then** the term names at least one source from Context, as a URL or a `.loctable` path
- **And** for a term that a provider's own product names (credits, balance, quota, peak hours, rate limit, model, plan), the source is that provider in Traditional Chinese where one exists, else another AI platform (Apple, Google, OpenAI, Anthropic, Microsoft) in `zh-TW`
- **And** where Taiwan and Hong Kong or mainland sources disagree, the Taiwan term is chosen, and the row records the other forms
- **And** a term with no Traditional Chinese source is marked ⚠︎ and goes to the native review (Plan step 9). It is never a silent character conversion from `zh-Hans`.

### AC6: The text follows the macOS Traditional Chinese style

- **Given** any `zh-Hant` value
- **When** a reviewer reads it, and the guard test runs
- **Then** quotes are 「…」, the ellipsis is ⋯, punctuation is full width, and no space separates Han from Latin letters, digits, or placeholders: "API金鑰", "5分鐘", "結束%@", "%@後重置"
- **And** the guard test fails on “…”, "…" (U+2026), half-width , ? ! : after a Han character, and a space between Han and a Latin letter or digit.

### AC7: Counted strings use one form

- **Given** a counted key such as `%lld minutes`
- **When** the plural test (`testEveryPluralHasTheFormsItsLanguageNeeds`) runs
- **Then** the `zh-Hant` value has one `other` form, as `zh-Hans` and `ja` do: "%lld分鐘".

### AC8: The packaged app declares Traditional Chinese

- **Given** the release build
- **When** `Contents/Info.plist` is read
- **Then** `CFBundleLocalizations` lists `zh-Hant`
- **And** `filbert_App.bundle` contains a `zh-Hant.lproj` folder.

### AC9: Layouts hold

- **Given** Filbert in Traditional Chinese
- **When** the popover, each settings tab, and the welcome window (ui 34) open at their default sizes
- **Then** no label is truncated where English is not truncated.

## Plan

1. [x] Term research (AC5). For every glossary term and every product term in the catalogs (credits, balance, quota, usage, reset, peak hours, rate limit, plan, model, API key, sign in, Keychain, menu bar), look the term up on the platforms in Context and record what each one says. Use this source order, and stop at the first level that answers:
   1. The platform that owns the term, in Traditional Chinese for Taiwan (`zh-TW`, or `zh-Hant` where the site has no region). macOS `zh_TW` strings for macOS terms. The provider's own UI or docs for provider terms (OpenAI for Codex credits, Anthropic for Claude Code limits, Google for Gemini quota, Cursor for its plans).
   2. Another major platform in `zh-TW` that names the same idea: Apple, Google, Microsoft, OpenAI, Anthropic.
   3. Taiwan usage from the NAER term database and a web search of Taiwan sites.
   4. A Hong Kong (`zh-HK`) source, recorded but used only when no Taiwan source exists.
   5. Nothing found: the term is ⚠︎. A mainland `zh-CN` source tells only the meaning. Its wording is never copied or character-converted.
   - When levels disagree, Taiwan usage wins. Record the losing forms with their source, for example "額度 (OpenAI zh-TW); 配額 (zh-CN, not used)".
   - Expected weak spots: DeepSeek and Z.ai balance and peak-hour terms, which likely have only Simplified sources.
   - Done 2026-10-20. macOS `zh_TW` `.loctable` strings (3,071 files) and Sparkle `zh_TW` were read locally. Four research passes covered Apple and Google, OpenAI and Anthropic, Cursor, DeepSeek, Z.ai, and OpenCode, and Microsoft, NAER, and Taiwan media. The sources are listed in the glossary.
   - Generic UI terms come from macOS, so 認證 (not 驗證) and 要求 (not 請求). Provider-owned terms come from the providers in `zh-TW`: 速率限制, 重設 (macOS says 重置), 點數, 方案, 用量上限. Taiwan usage settled 尖峰 / 離峰, 儲值, 門檻, and 時段.
   - Still ⚠︎: Keep Awake (防止睡眠; macOS has no such feature), DeepSeek's 贈送餘額 and 儲值餘額, Z.ai credits and credit rate, the pace status, "(your time)", helper script (Apple's 工序指令 against developers' 腳本), and Monitor (監控).
   - The user reviewed the column on 2026-10-20: no space before Latin text, as for Japanese; 防止睡眠 for Keep Awake; 腳本 for script, as Taiwanese developers write it; Taiwan blogs are acceptable sources for DeepSeek and Z.ai.
   - Found on the way: Apple's `zh-tw` help pages and Microsoft put a space around Latin text; macOS UI does not. AC6 follows the UI.
2. [x] Glossary column. Add `zh-Hant` to the Conventions and Terms tables in `docs/localization-glossary.md` from the step 1 results. Record the style rules from Context, the `zh-Hant` deny list, the `Hans-Hant` exceptions, and one source line for each term. Add the Taiwan sources to "Sources of truth". **The user reviews the column before any translation.**
3. [x] Catalogs, one module at a time: App, Core, then each provider (AC1). Write each value from English with the glossary. Use the `zh-Hans` value only to check meaning, never as the source text. A phrase that is not in the glossary (an error sentence, a setup hint) is checked against how the same platform phrases a similar message in `zh-TW`, for example Apple's and OpenAI's rate-limit and sign-in errors.
   - Done 2026-10-20. All 380 keys in 9 catalogs have a `zh-Hant` value, written from English with the glossary. Each value was checked before insertion for deny-list terms, spacing, punctuation, and `Hans-Hant`. The check caught 了解; macOS writes 瞭解 (99 strings, 了解 in none).
4. [x] Add `SupportedLanguage(code: "zh-Hant", autonym: "繁體中文")` after `zh-Hans` (AC3). Add `"zh-Hant": ["other"]` to the catalog test's plural forms (AC7).
   - Done 2026-10-20.
5. [x] Guard tests (AC4, AC6). Add the `zh-Hant` deny list and style checks to `testEveryLanguageAvoidsItsDeniedTerms`. Add a test that runs `Hans-Hant` on every `zh-Hant` value.
   - Done 2026-10-20. The deny list covers only unambiguous terms; 文件, 項目, 支持, and 通過 have valid Taiwan uses, so the glossary lists them for review only.
   - `Hans-Hant` runs on the whole value, because ICU converts some characters only in context: 周 alone stays, 周一 becomes 週一.
   - A deliberately broken value ("周一 API刷新") failed both tests, and the catalog was restored.
6. [x] Add `zh-Hant` to `CFBundleLocalizations` (AC8). Update the tests:
   - `DisplayLanguageTests`: the AC2 table, a lookup in `zh-Hant`, a reset countdown ("2小時後重設"), and remove the Traditional codes from the English fallback test. Keep `fr`.
   - `AppLanguagePreferenceTests`: `zh-Hant-TW` from System Settings now selects `zh-Hant`. Add "繁體中文" to the autonym list.
   - `DisplayLocaleFormattingTests`, `ZAIWindowLabelTests`, and `LocalizedPresentationCompositionTests`: add `zh-Hant` rows next to `zh-Hans`.
   - Done 2026-10-20. `zh-Hant-TW` and `zh-Hant-HK` stored by System Settings now select `zh-Hant`. The English fallback test keeps `fr` and `fr-CA`.
7. [x] Change the landing page card to "English, German, Spanish, Portuguese, Russian, Simplified and Traditional Chinese, and Japanese."
   - Done 2026-10-20.
8. [x] Run the validation gate: SwiftFormat, SwiftLint, release build, and the tests, also on the compiled-catalog path.
   - Done 2026-10-20. SwiftFormat and SwiftLint are clean, the release build passes, and 1,082 tests pass. An unsigned DMG (`scripts/build-dmg.sh --no-sign --skip-launch-check`) lists `zh-Hant` in `CFBundleLocalizations` and ships `filbert_App.bundle/zh-Hant.lproj`.
   - SwiftLint counted the CJK deny-list lines as too long, so the list is split six terms per line.
9. [x] Native review: one reviewer subagent reads every `zh-Hant` value against English and the glossary, as in (ui 31) Plan step 13. The reviewer does its own searches for every ⚠︎ term and for any value that reads as mainland or Hong Kong usage, and cites what it finds. The user approves the findings before they go into the catalogs.
   - Done 2026-10-20. The reviewer read all 380 strings and found no wrong meanings, mainland terms, or placeholder and punctuation errors. The user approved 18 style changes: 重新整理選項 (the Settings tab), 用量未超前 / 超前目前進度, 串接, 基底URL, 已可供下載 (as Sparkle), 無限制 (as Cursor), （你的時區）, 未開啟, 「codex login」, （USD、CNY等）, "%@版", and five reordered sentences.
   - Kept: "token", as Taiwanese developers write it, not Google's machine-translated 權杖.
   - The ⚠︎ on 防止睡眠, 儲值餘額, the pace status, and "(your time)" is gone. 贈送餘額, 點數 for Z.ai, 點數扣除比例, and 監控 keep theirs.
10. [ ] Manual check by the user: AC2, AC3, AC8 (Filbert listed in Language & Region › Applications), and AC9.

## Risks

- The agent writes the translations. A native Taiwanese speaker should review them before a release.
- Hong Kong users get Taiwan vocabulary. Most UI terms are shared, but some differ (for example 軟件 is normal in Hong Kong and denied here). A `zh-HK` catalog is out of scope.
- The `zh-Hant` style (no space before Latin text, 「」) differs from the existing `zh-Hans` style (a space, “…”). This is deliberate: each follows its own source. Reviewers must not "fix" one to match the other.
- Simplified-to-Traditional conversion gives wrong words, not only wrong characters (设置 → 設置, not 設定). AC4 catches the listed terms only. The term research (AC5) and the native review catch the rest.
- `Hans-Hant` can flag a valid Traditional character, such as 周. Each exception goes into the glossary, so the test does not get looser by accident.
- Traditional text is about as long as Simplified, so truncation risk is low. The welcome window (ui 34) is new since the last layout check.
- Some vendor pages may serve Simplified Chinese or English for a `zh-TW` URL, or redirect by IP. Record the page that was actually read, and treat a Simplified page as a level 5 source, not level 1.

---
name: release-highlights
description: Write the in-app "What's New" highlights for a Filbert release — add the version's entry to Sources/App/Resources/ReleaseHighlights.json, with one plain sentence per feature or fix in every supported language. Use this after the release-notes skill, or whenever the user asks for "highlights", "what's new text", or the release workflow fails because the version has no highlights entry.
---

# Release highlights

After an update, Filbert shows a short list of what is new in each version. Sparkle's
update dialog shows the same list in English. The text comes from
`Sources/App/Resources/ReleaseHighlights.json`, which ships inside the app. So the entry
must be merged to `main` **before** the release is published. The release workflow fails
when the entry is missing.

Never touch git. Edit the file, validate it, and give the user the commands.

## 1. Find the version and the source text

1. Ask for the version, or read it from the draft release: `gh release list --limit 5`.
   The version is the tag without the `v`, for example `0.26.0`.
2. Read the source text: `gh release view v<version> --json isDraft,body`. If the user
   just ran the `release-notes` skill, use that text.
3. Use only the **Overview**, **Features**, and **Bug Fixes** sections. Do not read the
   Changes list, commits, or PRs. The highlights say less than the release notes, never
   more.

If there is no Features and no Bug Fixes section, write an entry with an empty `items`
list. That tells the app that this release has nothing to show.

## 2. Write the English items

At most **5 items**. Pick what a user notices. Merge small related changes into one item.

Each item:

- has `kind` `feature` (something new the user can do or see) or `fix` (something that
  was broken and now works);
- is **one sentence**, at most **140 characters**, ending with `.`;
- says what the user sees, not how the code works;
- uses plain words. No Markdown, links, HTML, emoji, or version numbers;
- names a provider the way the app does: Claude Code, Codex, Cursor, DeepSeek, Gemini
  CLI, Kimi API, Kimi Code, OpenCode Go, Z.ai;
- claims nothing that the source text does not say.

Good: `Kimi Code's weekly and monthly rows now show when the allowance runs out.`
Bad: `Refactored KimiCodeForecast to use the shared pacing engine (#108).`

## 3. Translate

Write a value for every language in `Sources/App/SupportedLanguage.swift`. Today:
`en`, `de-DE`, `es-MX`, `es-ES`, `pt-BR`, `pt-PT`, `ru`, `zh-Hans`, `zh-Hant`, `ja`.

- Read `docs/localization-glossary.md` first. Use its terms and follow its deny lists.
  The tests fail on a denied term.
- Carry the meaning in the language's own idiom, not word for word.
- `es-MX` and `es-ES`, and `pt-BR` and `pt-PT`, are separate. Write each one for its
  region, even when the words come out the same.
- `zh-Hant` uses Taiwan terms, with no space between Han characters and Latin letters or
  digits. `ja` has no space between kana or kanji and Latin letters or digits.
- "Filbert" and provider names stay in Latin letters.
- Each value is one line, with no Markdown.

## 4. Edit the file

Add the entry at the **top** of the list. If the version is already there, replace it.
Keep the existing format: two-space indent, `kind` then `text`, languages in the order
above.

```json
{
  "version": "0.26.0",
  "items": [
    { "kind": "feature", "text": { "en": "…", "de-DE": "…", "…": "…" } }
  ]
}
```

## 5. Validate

Run both. Fix the entry until they pass.

```sh
python3 scripts/validate-release-highlights.py --require-version <version>
swift test --filter AppTests.ReleaseHighlightsTests
```

The first checks the shape, the languages, and the English rules. The second checks the
glossary deny lists and the Traditional Chinese characters.

## 6. Hand off

Show the user:

1. The English items, as a list with their kind.
2. A note that the translations need a native review before the merge.
3. The commands to run. Do not run them:

```sh
git switch -c release-highlights/v<version>
git add Sources/App/Resources/ReleaseHighlights.json
git commit -m "chore: add release highlights for <version>"
git push -u origin release-highlights/v<version>
gh pr create --fill --base main
```

Then remind the user of the order: merge this PR, **then** publish the release.

## Before you hand it back

- [ ] The entry is at the top, and its version matches the release.
- [ ] Every item comes from the Overview, Features, or Bug Fixes text.
- [ ] At most 5 items. Each English text is one sentence of 140 characters or fewer.
- [ ] Every supported language has a value.
- [ ] Both validation commands pass.
- [ ] You gave the git commands and did not run them.

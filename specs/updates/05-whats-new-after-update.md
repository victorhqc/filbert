# What's new after an update

## Objective

After Filbert updates, show the user a short, translated list of the new features and bug fixes in each new version, from highlights that ship inside the app.

## Context

- Problem: Sparkle installs a new version and relaunches Filbert. The user sees no sign of what changed. The Sparkle dialog before the update shows only the DMG name, the SHA-256, and install steps, because `scripts/build-dmg.sh` writes one notes file for the GitHub release and for the appcast.
- `Sources/App/Resources/ReleaseHighlights.json` — new. One entry for each version, newest first. Each item is one sentence, a feature or a fix, in every supported language (ui 31, ui 36). The `release-highlights` skill writes each entry. The maintainer reviews it in a PR that merges before the release is published.
- `Sources/App/ReleaseHighlights.swift` — new. Decodes the file and picks the text for the display language.
- `Sources/App/WhatsNewState.swift` — new. Saves the last version that the user saw in `UserDefaults` and decides which versions to show. It follows the pattern of `WelcomeState` (ui 34).
- `Sources/App/WhatsNewWindowController.swift`, `Sources/App/WhatsNewView.swift` — new. A small window that the user can dismiss, like the Welcome window (ui 34 Plan step 5). The popover only links to it. The highlights never show inside the popover.
- `Sources/App/AboutSettingsView.swift` — `AboutMascot` loads `Mascot.png`, the octopus. The new window uses the same loader.
- `Sources/App/QuotaView+Footer.swift` — gets the "What's new" row, next to the update row (updates 02).
- `Sources/App/AboutSettingsView.swift` — gets a "What's New" button (ui 20).
- `Sources/App/SettingsWindowActivation.swift` — `SettingsWindowLookup` must skip the new window, as it skips the Welcome window (ui 34 AC12).
- `Sources/App/Resources/Localizable.xcstrings` — the window and row text, in every language. The highlight sentences are not in the catalog. They are in the JSON file.
- `scripts/validate-release-highlights.py` — new. Checks the file shape. CI, the release workflow, and the `release-highlights` skill use it.
- `scripts/build-dmg.sh` — writes a second notes file for the appcast that contains the English highlights.
- `.github/workflows/release.yml`, `scripts/validate-appcast.py` — the release fails if the tag's version has no entry. The appcast embeds the highlights notes.
- `.agents/skills/release-highlights/SKILL.md` — new skill. It turns the release notes into a highlights entry, translates it with the terms in `docs/localization-glossary.md`, and runs the validator. Like every agent in this repo, it does not touch git. It gives the maintainer the commands.
- `.agents/skills/release-notes/SKILL.md` — its Features and Bug Fixes are the source text for the new skill. Its final checklist points to the new skill.
- `docs/automatic-updates.md` — the release steps get the new order: highlights PR, merge, then publish.
- Builds on (updates 01, updates 02, updates 04). Filbert makes no new network request. "Full release notes" opens the browser.

## Acceptance Criteria

`[~]` marks a plausible AC. The code is in place and is assumed to work, but no packaged app or published release has proved it. Change it back to `[ ]` when someone reports a bug against it.

### [x] AC1: The highlights file has a fixed shape

- **Given** `ReleaseHighlights.json`
- **When** `scripts/validate-release-highlights.py` runs in CI
- **Then** it passes only when every entry has a plain `X.Y.Z` version, the versions are unique and newest first, and each entry has 0 to 5 items
- **And** each item has a `kind` of `feature` or `fix`, and a non-empty text for every language in `SupportedLanguage.all`
- **And** each English text is one sentence of at most 140 characters, with no Markdown, links, or line breaks.

### [~] AC2: A release cannot ship without an entry

- **Given** a published release with tag `vX.Y.Z`
- **When** the release workflow starts
- **Then** it fails before the build if `ReleaseHighlights.json` at that tag has no valid entry for `X.Y.Z`
- **And** an entry with no items is valid. It means that the release has nothing to show.

### [~] AC3: An updated user sees a row in the popover

- **Given** the saved last-seen version is `0.25.0` and the running version is `0.26.0`, and `0.26.0` has items
- **When** the user opens the popover
- **Then** a row shows "Updated to 0.26.0" with a "What's New" button and a dismiss button
- **And** the row stays across popover closes and app relaunches until AC6 applies.

### [x] AC4: Skipped versions are included

- **Given** the last-seen version is `0.23.0` and the running version is `0.26.0`
- **When** the user opens the What's New window from the row
- **Then** it shows the items of every version after `0.23.0` up to `0.26.0` that has items, newest version first.

### [~] AC5: The window lists the highlights

- **Given** the What's New window is open
- **When** it shows a version
- **Then** it shows the version number, then its features, then its fixes, each with its own heading and one line for each item
- **And** a "Full release notes" link opens `https://github.com/victorhqc/filbert/releases/tag/vX.Y.Z` for the running version in the browser.

### [~] AC5a: The window shows the mascot

- **Given** the What's New window is open
- **When** it shows
- **Then** the octopus mascot shows in the header, next to the title "What's New in Filbert"
- **And** the mascot is hidden from VoiceOver, as on the About tab (ui 20).

### [~] AC5b: The user can dismiss the window

- **Given** the What's New window is open
- **When** the user selects "Done", presses Return or Escape, or closes the window
- **Then** the window closes
- **And** the popover and Settings do not open.

### [x] AC6: Reading or dismissing marks the update as seen

- **Given** the row is visible
- **When** the user opens the What's New window, or selects the dismiss button
- **Then** Filbert saves the running version as the last-seen version
- **And** the row does not show again, also after a relaunch.

### [x] AC7: A new user sees nothing

- **Given** a fresh install, where the Welcome window shows (ui 34 AC1)
- **When** Filbert launches
- **Then** Filbert saves the running version as the last-seen version
- **And** no row shows.

### [x] AC8: The first version with this feature shows its own highlights

- **Given** an existing install (ui 34 AC2) with no saved last-seen version
- **When** Filbert launches
- **Then** the row shows for the running version only.

### [x] AC9: Nothing to show means no row

- **Given** every version between the last-seen version and the running version has no items, or the running version is older than the last-seen version
- **When** Filbert launches
- **Then** no row shows, and Filbert saves the running version as the last-seen version.

### [~] AC10: The text follows the display language

- **Given** the user selects a language (ui 32)
- **When** the row or the window is visible
- **Then** the highlights change to that language at once, as the other text does
- **And** if a language has no text, the English text shows.

### [~] AC11: The user can see the highlights again

- **Given** the About tab in Settings
- **When** the user selects "What's New"
- **Then** the window opens with the newest three versions that have items, up to the running version
- **And** this does not change the last-seen version.

### [~] AC12: The update dialog shows the highlights

- **Given** Sparkle offers version `X.Y.Z`
- **When** Sparkle's update dialog shows the release notes
- **Then** it shows the English features and fixes for `X.Y.Z`, and a link to the full release notes
- **And** the DMG name, the SHA-256, and the install steps stay on the GitHub release only.

### [~] AC13: Development builds stay quiet

- **Given** a build with no release version (ui 20)
- **When** Filbert launches
- **Then** no row shows, unless Filbert launches with `--show-whats-new`. Then the window opens with the newest entry that has items.

### [~] AC14: Settings still opens

- **Given** the What's New window is open
- **When** the user selects "Open Settings" in the popover
- **Then** the Settings window comes to the front, and the What's New window does not.

### [~] AC15: The window is accessible and translated

- **Given** VoiceOver is on
- **When** focus moves through the row and the window
- **Then** VoiceOver reads the version, each heading, and each item
- **And** the catalog test (ui 29 AC3) passes for every new row and window string in every language.

### [~] AC16: A skill writes the entry

- **Given** the Features and Bug Fixes for version `X.Y.Z`, from a draft release or from the `release-notes` skill
- **When** the maintainer runs the `release-highlights` skill
- **Then** it adds an `X.Y.Z` entry at the top of `ReleaseHighlights.json`, or replaces the existing one
- **And** each item is a plain sentence for a user, with no feature or fix that is not in the source text, and with text in every supported language
- **And** it runs `validate-release-highlights.py` and fixes the entry until it passes
- **And** it shows the English items and gives the git commands for the PR. It does not run them.

## Plan

1. [x] `ReleaseHighlights` model and decoder. The file holds, for example:
   `[{"version": "0.26.0", "items": [{"kind": "feature", "text": {"en": "…", "de-DE": "…"}}]}]`.
   Text lookup uses the language of `DisplayLanguage.locale` and falls back to `en`. Tests use a fixture file (AC10).
2. [x] `scripts/validate-release-highlights.py`, standard library only, with tests next to `scripts/test-automatic-updates.py`. `ci.yml` runs it. It reads the language list from one place that the Swift test also checks against `SupportedLanguage.all` (AC1).
3. [x] `WhatsNewState` with an injected `UserDefaults`, running version, launch arguments, and the existing-install check from `WelcomeState`. It returns the versions to show, or none, and saves the last-seen version. `AppMain.init` reads it before the first enablement read, as `WelcomeState` does. Tests cover AC3, AC4, AC6–AC9, AC13.
4. [x] `WhatsNewView` and `WhatsNewWindowController`. Same `NSWindow` approach and accessory-policy activation as the Welcome window. Fixed identifier `filbert.whats-new`, skipped by `SettingsWindowLookup` (AC5, AC14).
   - About 420 pt wide. A header with the mascot at about 64 pt from `AboutMascot.load()` and the title. Below it, a scroll view with the versions. At the bottom, "Full release notes" and a "Done" default button (AC5a, AC5b).
   - The window can be resized only in height, so a long list of skipped versions scrolls.
5. [x] Popover row in `QuotaView+Footer.swift`, under the footer and above the update row. "About" button in `AboutSettingsView` (AC3, AC11).
6. [x] Strings for the row, the window, and the About button, in every language (AC15). Needs a native review, as for (ui 31).
7. [x] Release side. `build-dmg.sh` takes the version's entry and writes `<dmg>.appcast-notes.md`: a "What's new" list in English and the release link. `release.yml` validates the entry first (AC2) and gives the appcast notes to `generate_appcast`. `validate-appcast.py` checks that the embedded notes contain each English item (AC12).
8. [x] The `release-highlights` skill (AC16). It covers the source text, the rules for a highlight, the translation with the glossary, the validator, and the hand-off commands. The `release-notes` checklist and `docs/automatic-updates.md` get the new release order: write the release notes, run the skill, merge the PR, then publish.
9. [ ] Seed entry for the next release (done 2026-11-04: one `0.26.0` feature item), then a manual check in the packaged app: an update from the previous release (AC3, AC6), a skipped version (AC4), a fresh account (AC7), and a language change while the window is open (AC10).

## Findings

- 2026-11-04: `Bundle.preferredLocalizations` matches `es-Latn-MX` to `es-ES` before `es-MX`. The text lookup puts `<language>-<region>` first, then the minimal and maximal identifiers. A test checks that each supported language picks its own text.
- 2026-11-04: SwiftLint allows one level of type nesting, so the item type is the top-level `ReleaseHighlight`.
- 2026-11-04: Escape closes the window through `cancelOperation(_:)` on an `NSWindow` subclass. The window title helper moved from `WelcomeView` to `WindowTitle.swift`, so both windows use it.
- 2026-11-04: The highlights tests reuse the catalog deny lists and the Traditional Chinese check from `StringCatalogCoverageTests`.
- 2026-11-04: The signed lane of `build-dmg.sh` checks the entry before the build too, so a local signed build fails early, not after notarization.
- 2026-11-04: A debug launch with `--show-whats-new` from the agent's shell made no windows at all, not even the menu bar item. The shell has no window server session. The window layout, the mascot, and the popover row need the manual check in Plan step 9.

## Risks

- A release now needs a merged PR before it is published. This adds a step, but the text is reviewed as a normal diff.
- The skill writes the translations. They need a native review, as for (ui 31), or a wrong sentence ships in that language.
- A maintainer who creates the tag before the highlights PR merges gets a failed release (AC2). This is the purpose of the check. The fix is to delete the tag and publish again after the merge.
- The existing-install check (AC8) uses the same guess as (ui 34 Risks). A rare user sees the row once without a real update.
- The highlights file grows with each release. At 10 languages × 5 items, it is about 10 KB for each version. This is acceptable for years. Old entries can be removed when needed, because the window shows at most the skipped versions.
- Sparkle's dialog stays in English (AC12). Sparkle can show localized notes, but `generate_appcast` support for them is not checked. Localized notes are a possible follow-up.
- The What's New window adds a second titled window next to the Welcome window. A wrong lookup can bring the wrong window to the front (AC14).

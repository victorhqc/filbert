## Objective

Make durations, intervals, and ranges read naturally in every language, on screen and in VoiceOver.

## Context

- Status: draft, waiting for the user's review.
- Follows the native language review (ui 31, plan steps 13–15). These issues come from code, not from the catalogs.
- `Sources/App/CoarseDurationFormatting.swift` formats durations in `.abbreviated` style. For a week or more it uses weeks, and Japanese then shows a Latin "w": "残り2w3日", "約1w2日". German shows "1W 2d".
- `Sources/App/PacedUsageLineText.swift` reuses the visual text for VoiceOver, so VoiceOver reads "4d 15h left". The forecast sentences already use `.full`.
- `Sources/App/SleepPreventionController.swift` fills "Mac won't sleep for %@" with a clock ("12:34", "1:02:03"). VoiceOver reads it as a time of day.
- `Sources/App/RefreshSettingsFormatting.swift` returns "1 minute", and the sentences put "every" in front of it: "every 1 minute". Affected keys: "Regular refresh checks opted-in providers every %@.", the Smart refresh sentence, "Provider limit: checks no more often than every %@.", and "Checks every %@ for the time you choose…". German works around it with "im Abstand von %@".
- `CoarseDurationFormatting.evidenceSpan` is often exactly one unit, so English reads "Based on the last 1 hour". Eight forecast keys contain "last %@". Most translations already say "%@ of history", so the problem is mainly English.
- `Sources/App/PeakHoursPresentation.swift` and `PeakHoursBlock.swift` hard-code "–" for weekday and time ranges. Chinese writes "周一至周五", and Japanese writes "月〜金".
- Foundation decides how durations look in each language (ui 31 glossary): "4d 15h" is Apple's own German `.abbreviated` output. This spec keeps the system formatters and changes only how Filbert uses them.

## Acceptance Criteria

### AC1: No week unit in short durations
- **Given** a remaining time or forecast of 7 days or more
- **When** the popover shows it
- **Then** it uses days, not weeks: "9d", "9日", "9 д.", "9天"
- **And** no language shows a Latin unit letter inside non-Latin text ("w", "W").

### AC2: VoiceOver reads durations in full
- **Given** a paced usage row with "4d 15h left" on screen
- **When** VoiceOver reads the row
- **Then** it hears the full form, for example "4 days, 15 hours left" or "Tiempo restante: 4 días y 15 horas"
- **And** the screen still shows the short form.

### AC3: Keep Awake time is spoken as a duration
- **Given** Keep Awake is on with 12:34 left
- **When** VoiceOver reads the Keep Awake status
- **Then** it hears "12 minutes, 34 seconds", in the display language
- **And** the screen still shows "12:34".

### AC4: Refresh intervals agree with their count
- **Given** a refresh interval of 1 minute, 5 minutes, or 30 seconds
- **When** the refresh settings describe it
- **Then** English reads "every minute", "every 5 minutes", and "every 30 seconds", never "every 1 minute"
- **And** every language uses its own plural forms for the interval phrase, such as "jede Minute" / "alle 5 Minuten" and "каждую минуту" / "каждые 5 минут" / "каждые 21 минуту".

### AC5: The evidence span reads naturally in English
- **Given** a forecast based on exactly 1 hour of history
- **When** the forecast line shows the span
- **Then** English reads "1 hour of history", never "the last 1 hour"
- **And** no translation changes meaning.

### AC6: Ranges use each language's range style
- **Given** peak hours on weekdays 1–5 from 01:00 to 04:00
- **When** the peak-hours block shows the range
- **Then** each language uses its own range form: "Mon–Fri" (en), "周一至周五" (zh-Hans), "月〜金" (ja)
- **And** time ranges follow the same rule.

## Plan

1. `CoarseDurationFormatting.string`: replace `[.weekOfMonth, .day]` with `[.day]` for 7 days and more. Keep `.abbreviated` everywhere else. Update the forecast tests that expect weeks.
2. `PacedUsageLineText`: build `accessibilitySentences` from a separate `.full` duration. The visual `remainingTime` keeps `.abbreviated`.
3. Keep Awake: add a spoken form from `DateComponentsFormatter` (`.full`, hours, minutes, seconds) and use it in the accessibility label and value. Keep the clock text on screen.
4. Interval phrases: add plural keys "every %lld seconds" and "every %lld minutes" (English `one`: "every minute"). The four refresh sentences take the phrase as `%@` and no longer contain "every". The reviewers for each language write the plural forms and the sentence templates. German drops "im Abstand von" where the plural phrase reads better.
5. Evidence span: rename the eight English keys to the "%@ of history" pattern ("Based on %@ of history", "Should last until reset · %@ of history"). Translations move to the new keys unchanged, unless a reviewer finds a problem.
6. Ranges: add a catalog key "%1$@–%2$@" for a range, with a translator comment. Weekday ranges and peak time ranges use it. zh-Hans writes "%1$@至%2$@", ja "%1$@〜%2$@", other languages keep "–".
7. Glossary: record the interval-phrase rule, the range key, and the "no weeks" rule. Update the duration rules that mention "alle %@" and "im Abstand von %@".
8. Validation gate: SwiftFormat, SwiftLint, release build, and the tests on the compiled-catalog path. Then the user checks the popover, the refresh settings, and Keep Awake with VoiceOver in at least German, Russian, and Japanese.

## Risks

- Days only makes long values longer in some languages: "28d" replaces "4w". The 4-week forecast cap still applies.
- Plural keys for intervals change four templates in every language. Russian needs `one`, `few`, `many`, and `other`, and the catalog test checks them (ui 31 AC4).
- Renaming the eight evidence-span keys touches every catalog. The catalog test catches a missed key.
- Japanese and Chinese range text has no spaces, so check the peak-hours row for odd line breaks.
- Foundation's `ListFormatter` still joins Chinese time ranges as "01:00–04:00和06:00–10:00", without spaces. This spec leaves it as Foundation's output.

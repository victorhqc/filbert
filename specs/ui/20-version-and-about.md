## Objective

Make the running Filbert version visible in the popover and add an About destination that identifies the project, links to its source and license, and discloses shipped third-party components.

## Context

- `Sources/App/QuotaView.swift` — owns the menu-bar popover footer where the compact running-version label belongs.
- `Sources/App/SettingsView.swift` — owns the native Settings tabs and gains an About tab alongside Providers, Appearance, and Refresh Settings.
- New `Sources/App/AboutSettingsView.swift` — keeps About presentation separate from provider configuration and refresh behavior while reusing the settings card layout from (ui 15).
- New `Sources/App/AppVersion.swift` — resolves and formats the installed app version from bundle metadata without hard-coding a release number in Swift.
- `packaging/Info.plist` and `scripts/build-dmg.sh` — already stamp the release version into `CFBundleShortVersionString` when assembling the installed app bundle (ci 02 AC1).
- `assets/mascot.png` and `Sources/App/Resources/` — the existing Filbert mascot is the source artwork; a runtime-sized copy belongs in the App resource bundle so installed builds can load it through `Bundle.module`.
- `Package.swift` — currently declares no external Swift package dependencies, so Filbert ships no third-party runtime libraries today.
- `scripts/provider-glyphs/README.md` — records the Simple Icons source and license for the shipped Claude and DeepSeek glyph artwork; About acknowledges that asset source separately from runtime libraries.
- `Sources/App/Resources/Localizable.xcstrings` — receives all new user-facing prose in the app's supported locales.
- `Tests/AppTests/` — gains focused coverage for bundle-version resolution and About acknowledgement data without adding UI snapshot infrastructure.

## Acceptance Criteria

### AC1: The popover shows the installed version

- **Given** Filbert is running from an installed app bundle whose `CFBundleShortVersionString` is `0.9.0`
- **When** the user opens the menu-bar popover
- **Then** the footer shows `filbert v0.9.0`
- **And** the value comes from the running bundle's `CFBundleShortVersionString`, not a hard-coded Swift constant, a network request, a release tag lookup, or the package manifest
- **And** the version label remains visible whether providers are configured or the empty state is shown.

### AC2: The popover version is deliberately quiet

- **Given** the popover footer contains Settings, the version, and Quit
- **When** it renders at the existing `280`-point width
- **Then** the version uses very small secondary text no larger than `.caption2`
- **And** it is centered between the leading Settings action and trailing Quit action without shrinking either action below its readable intrinsic width
- **And** the footer does not increase the popover width or add a second divider.

### AC3: Missing or malformed development metadata is handled safely

- **Given** a local `swift run` or test process has no non-empty `CFBundleShortVersionString`
- **When** the version presentation is resolved
- **Then** it shows the localized development fallback `filbert development`
- **And** it never shows `v(null)`, `v0.0.0`, an empty `v`, a build-script placeholder such as `@VERSION@`, or crashes
- **And** installed release builds continue to use the real stamped version from AC1.

### AC4: Settings includes a native About destination

- **Given** the user opens Settings
- **When** the Settings tab bar renders
- **Then** it contains Providers, Appearance, Refresh Settings, and a localized About tab
- **And** About uses a suitable native information icon and preserves native macOS Settings tab selection, keyboard behavior, window sizing, and scrolling from (ui 15 AC1/AC2)
- **And** opening About performs no provider refresh, credential read, Keychain access, or network request.

### AC5: About presents Filbert's identity and running build

- **Given** the About tab is selected
- **When** its content renders
- **Then** it shows the existing Filbert mascot, the product name `Filbert`, a short localized description identifying it as a native macOS AI usage tracker, and the same resolved version presentation used by the popover
- **And** the mascot is loaded from the App resource bundle in both development and packaged builds
- **And** the image is aspect-fit, remains crisp on Retina displays, does not dominate the settings window, and is hidden from VoiceOver because the adjacent product name supplies its identity.

### AC6: Project and license information is actionable

- **Given** the About tab is visible
- **When** the user reviews the Project section
- **Then** it includes an actionable GitHub link to `https://github.com/victorhqc/filbert`
- **And** it identifies Filbert as open source under the MIT License and includes an actionable link to `https://github.com/victorhqc/filbert/blob/main/LICENSE`
- **And** both links use the system's normal external-link behavior, expose their destinations to accessibility, and do not embed a web view or make a background request.

### AC7: Runtime libraries and asset acknowledgements are accurate

- **Given** the current package has no external runtime dependencies
- **When** the About tab renders its Open Source section
- **Then** it states that Filbert currently has no third-party runtime library dependencies and is built with Apple system frameworks
- **And** it separately acknowledges that the Claude and DeepSeek provider glyphs are derived from Simple Icons, with an actionable link to `https://github.com/simple-icons/simple-icons`
- **And** developer and packaging tools such as SwiftFormat, SwiftLint, and `create-dmg` are not misrepresented as libraries shipped inside the app
- **And** future runtime dependencies must be added to the acknowledgement data when they are introduced, so the statement cannot silently remain false.

### AC8: About content follows the existing visual and accessibility language

- **Given** the About tab renders in light mode, dark mode, Increased Contrast, Reduce Transparency, or a larger accessibility text size
- **When** the user views or navigates its content
- **Then** it uses the shared centered scroll column and settings-card treatment from (ui 15)
- **And** all text remains readable, links retain visible focus and keyboard activation, and content scrolls rather than clipping at the minimum Settings window size
- **And** the mascot and links have no fixed layout that causes horizontal scrolling.

### AC9: New prose is localized and dynamic values remain literal

- **Given** the app runs in English, German, Spanish (Spain), or Spanish (Mexico)
- **When** the popover or About tab renders
- **Then** every new heading, description, fallback, acknowledgement sentence, and accessibility label is present in `Sources/App/Resources/Localizable.xcstrings`
- **And** the Filbert brand, semantic version, GitHub URLs, license name, and Simple Icons name remain unchanged rather than being translated.

### AC10: Version and acknowledgement behavior is covered by focused tests

- **Given** the implementation is ready for review
- **When** the App test suite runs
- **Then** tests cover a valid short version, missing and blank metadata, the unreplaced `@VERSION@` placeholder, and the exact `filbert v<version>` release format
- **And** tests assert that the acknowledgement model reports no runtime libraries today and includes the Simple Icons asset credit and canonical project/license URLs
- **And** the repository formatting, lint, debug build, release build, and full test gates pass.

## Plan

Add a small pure version resolver that reads `CFBundleShortVersionString` from an injected bundle or info dictionary and returns either the release presentation or a localized development fallback. Use that single presentation source in a centered `.caption2` popover footer label and in a new About settings view.

Add a runtime-sized mascot copy to `Sources/App/Resources/`, then compose the About tab from the existing settings scroll column and cards: identity, Project, and Open Source. Keep canonical URLs and acknowledgement entries in small immutable App-layer data so they can be tested and extended when a shipped dependency is added. Use native SwiftUI `Link` controls and no web view, provider logic, Core change, or network call.

Add localized strings for all four supported locales, focused pure tests for version sanitation and acknowledgement contents, and visual checks at the default and minimum Settings sizes in light and dark appearances.

## Risks

- SwiftPM test and `swift run` processes do not carry the packaged app's `Info.plist`; the explicit development fallback must stay visually distinct from a real release version.
- A version string supplied with a leading `v` could otherwise render as `vv...`; the release script currently supplies bare semver, and the resolver should normalize one leading `v` defensively.
- Adding a fourth native Settings tab reduces horizontal room for tab labels. The window minimum must accommodate all localized labels without replacing native tabs or truncating essential navigation.
- The `1254 × 1254` source mascot is larger than needed at runtime. The bundled copy should be resized for the intended Retina presentation so it does not add avoidable app size.
- Dependency acknowledgements can become stale when `Package.swift` changes. The immutable acknowledgement data and its test make the current claim explicit, but future dependency changes still require reviewer attention.
- Simple Icons is an artwork source rather than a linked runtime library. Keeping its credit separate avoids both omitting an asset attribution and overstating Filbert's runtime dependency footprint.

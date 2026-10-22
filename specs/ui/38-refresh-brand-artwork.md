## Objective

Use the refreshed source artwork consistently in the app icon, Settings About identity, and website.

## Context

- `assets/icon.png` — source for the macOS app icon and website icon variants.
- `assets/mascot.png` and `assets/mascot-with-ai-logos.png` — refreshed mascot artwork for website imagery.
- `Sources/App/Resources/AppIcon.icns` — bundled icon used at runtime and copied into the packaged app.
- `Sources/App/AboutSettingsView.swift` — retains the bundled mascot presentation from (ui 20 AC5).
- `Sources/App/Resources/Mascot.png` — runtime-sized About artwork derived from `assets/mascot-with-ai-logos.png`.
- `site/images/` — optimized artwork served by the landing page from (site 01).
- `scripts/build-site.sh` — copies prepared website images without requiring image tools during deployment.

## Acceptance Criteria

### AC1: The app uses the refreshed icon

- **Given** the updated `assets/icon.png`
- **When** the app icon resources are regenerated
- **Then** `AppIcon.icns` contains the standard macOS icon sizes derived from that artwork
- **And** development and packaged builds continue using the existing icon-loading and packaging paths.

### AC2: About shows the mascot with AI logos

- **Given** Settings is open on About
- **When** its identity card renders
- **Then** it shows the refreshed mascot with AI logos from `assets/mascot-with-ai-logos.png`, not the app icon or the standalone mascot
- **And** it loads a runtime-sized copy from the existing bundled `Mascot.png` resource without a source-checkout dependency
- **And** it preserves the current 112-point aspect-fit presentation, decorative accessibility treatment, text, and layout
- **And** the existing mascot resource-loading test continues to pass.

### AC3: Website branding uses the refreshed artwork

- **Given** the updated source images in `assets/`
- **When** the website imagery is regenerated
- **Then** the hero icon, favicon, and Apple touch icon derive from `assets/icon.png`
- **And** the privacy mascot derives from `assets/mascot.png`
- **And** the social preview uses the refreshed artwork while retaining a readable 1200 × 630 composition
- **And** generated images preserve their existing public paths and appropriate dimensions
- **And** the website remains below the transfer-size budget from (site 01 AC4)
- **And** screenshots and provider glyphs remain unchanged because this is a branding refresh, not a new screenshot capture.

## Plan

- [x] Generate the macOS icon representations and replace the bundled `AppIcon.icns`.
- [x] Regenerate the bundled `Mascot.png` from `assets/mascot-with-ai-logos.png`, retaining the existing About loader and layout.
- [x] Regenerate the website branding images from the refreshed sources without adding image-tool dependencies to Pages deployment.
- [x] Validate icon representations, inspect the generated imagery, build a local website preview, and run the repository validation gate.

## Risks

- Finder and Dock may cache icons after a rebuild; an already running or installed app is not proof that the packaged icon is stale.
- Fine watercolor details can blur at favicon sizes; inspect small variants rather than relying only on the full-resolution source.
- Cropping or flattening can damage the artwork; preserve aspect ratios and inspect backgrounds and transparency.
- Social preview services cache images independently of the website; refreshed files do not guarantee immediate cache invalidation.

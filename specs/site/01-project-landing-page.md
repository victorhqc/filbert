## Objective

Publish a simple, static landing page at `https://victorhqc.github.io/filbert/` that explains Filbert, links to the latest signed DMG, and shows the app, without breaking the Sparkle appcast served from the same site.

## Context

- Status: implemented 2026-10-19 with the new v0.20.0 screenshots, not yet on `main`. Waiting for the one-time bootstrap (Plan step 7).
- `.github/workflows/release.yml` — its `publish-pages` job deploys a Pages artifact that contains only `appcast.xml`. Every Pages deployment replaces the whole site. A separate landing-page deployment would therefore delete the appcast, and the next release would delete the landing page.
- `packaging/Info.plist` and `Sources/App/UpdateCoordinator.swift` — installed apps read `https://victorhqc.github.io/filbert/appcast.xml`. This URL must not change and must never return 404 (updates 01 AC4).
- The `github-pages` environment accepts deployments from `main` and `v*` tags. No change to it is needed.
- `Sources/App/WelcomeView.swift` — the welcome window from (ui 34). Its lead sentence is the page tagline, so the page and the app introduce Filbert with the same words.
- `assets/` — the source icon and mascot. These PNGs are 2–6 MB each, too large for a web page.
- `Sources/Providers/*/Resources/ProviderGlyph@2x.png` — 48 px black template glyphs for the provider grid.
- New `site/` — the page source: `index.html`, `style.css`, and optimized images.
- New `scripts/build-site.sh` — assembles the Pages artifact from `site/`, the release version, and the appcast.
- New `.github/workflows/pages.yml` — the only workflow that deploys Pages.
- `docs/automatic-updates.md` — describes Pages as appcast-only and must describe the combined site.
- `README.md` — gains a link to the website.
- Builds on the release pipeline from (ci 02, ci 05) and the feed contract from (updates 01).

## Acceptance Criteria

### AC1: The page explains Filbert at a glance
- **Given** a visitor opens the site root
- **When** the page loads
- **Then** the first screen shows the Filbert icon, the name, the tagline "Filbert shows how much of your AI usage is left before you hit a limit.", a primary download button, and the hero screenshot
- **And** the page then shows, in order: the key features, screenshots, supported providers, privacy, getting started, and a footer
- **And** every claim on the page matches the README and the shipped app (providers, languages, requirements, privacy).

### AC2: The download button links to the exact latest DMG
- **Given** the site was built for release `vX.Y.Z`
- **When** the visitor clicks the primary download button
- **Then** the browser downloads `https://github.com/victorhqc/filbert/releases/download/vX.Y.Z/Filbert-X.Y.Z-arm64.dmg`
- **And** the button label shows the version
- **And** the requirements (Apple Silicon, macOS 26 or newer) appear next to the button
- **And** a secondary link opens the GitHub releases page.

### AC3: The page is simple, native-looking, and self-contained
- **Given** the page source
- **When** it is inspected
- **Then** it is plain HTML and CSS with no JavaScript, framework, build tool, web font, CDN, or analytics
- **And** the page makes no request to any host other than its own origin and the GitHub links the visitor clicks
- **And** it uses the system font stack and follows the light or dark appearance of the system
- **And** provider glyphs stay visible in dark mode
- **And** it is readable from 360 px to wide desktop widths.

### AC4: The page is accessible and light
- **Given** the page is rendered
- **When** it is checked
- **Then** every image has meaningful alt text, or empty alt text if it is decorative
- **And** the page uses semantic landmarks (`header`, `main`, `footer`) and one `h1`
- **And** text meets WCAG AA contrast in light and dark mode
- **And** the total transfer size of the page and its images is below 1.5 MB.

### AC5: Link previews show Filbert
- **Given** the site URL is shared in a chat or social app
- **When** the app fetches the page
- **Then** Open Graph and Twitter card metadata supply a title, description, and absolute image URL
- **And** the page has a favicon and an Apple touch icon.

### AC6: Screenshots show the current app
- **Given** the shot list in the Plan
- **When** the page is deployed for the first time
- **Then** every screenshot on the page is a new capture of the current release
- **And** no screenshot shows a real API key, account email, or other personal data.

### AC7: One workflow deploys the whole site, and it always includes the appcast
- **Given** any Pages deployment
- **When** the artifact is assembled
- **Then** it contains the landing page and `appcast.xml` at the site root
- **And** the build fails before deployment if the appcast is missing, is not well-formed XML, or does not reference the DMG of the target release tag
- **And** `.github/workflows/pages.yml` is the only workflow that runs `deploy-pages`.

### AC8: Releases persist the appcast so site-only deploys can reuse it
- **Given** a stable release passes the existing appcast validation
- **When** the release job continues
- **Then** it uploads the validated `appcast.xml` as an asset of that release
- **And** it calls `pages.yml` with the release tag after the upload succeeds
- **And** the appcast content and its validation are unchanged from (updates 01 AC10).

### AC9: Site changes deploy without a release
- **Given** a commit on `main` changes `site/**`, `scripts/build-site.sh`, or `pages.yml`
- **When** the push completes, or a maintainer runs the workflow manually
- **Then** `pages.yml` resolves the latest stable release, downloads its `appcast.xml` asset, builds the page for that version, and deploys both
- **And** Pages deployments never run concurrently and never cancel one another.

### AC10: Local preview works without secrets
- **Given** a developer runs `scripts/build-site.sh --version X.Y.Z --out <dir>` with no appcast
- **When** the script finishes
- **Then** `<dir>` holds a complete preview that can be served with `python3 -m http.server`
- **And** the script fails if any version token is left in the output or any image that the page references is missing.

## Plan

1. **Images.** Make web copies in `site/images/` with `magick`: icon at 256 px and 512 px, mascot at about 600 px, a 180 px touch icon, a favicon, and a 1200 × 630 social card. Copy the seven provider glyphs as they are. Commit the copies so the deploy needs no image tools.
2. **Screenshots.** The maintainer captures these from the current release as Retina PNGs. The originals stay in `assets/screenshots/`. The page serves WebP copies from `site/images/screenshots/`: lossy at quality 90 for `hero`, lossless for the panel shots. Every screenshot also has a `-dark` capture, which the page serves through `<picture>` when the system is in dark mode.

   | File | Content |
   |------|---------|
   | `hero.png` | The popover open under the menu-bar icon, over a desktop, with three or four providers that show usage and forecasts. |
   | `popover-collapsed.png` | The popover alone, all providers collapsed. |
   | `popover-expanded.png` | The popover alone, one provider expanded with its forecast. |
   | `welcome.png` | The first step of the welcome window. |

   The welcome shot sits in **Get started**, above the steps, because step 3 refers to it.
3. **Page.** One `site/index.html` with these sections:
   - **Hero:** icon, "Filbert" as the `h1`, the tagline, a **Download for macOS — vX.Y.Z** button, the requirements line, and a "View on GitHub" link. `hero.png` is beside the text, or under it on narrow screens.
   - **Features:** six short cards: menu-bar glance, full popover breakdown, "runs out in" forecasts, smart refresh, Keep Awake, and seven languages.
   - **Screenshots:** collapsed popover and expanded popover.
   - **Providers:** a glyph grid for z.ai, Claude Code, Gemini CLI, DeepSeek, OpenAI Codex, Cursor, and OpenCode Go, with a link to the README setup notes.
   - **Privacy:** the mascot, plus four points: Keychain storage, direct HTTPS calls, no telemetry, no Electron.
   - **Get started:** the welcome shot, then three steps (download, drag to Applications, add a provider in the welcome window). The step titles reuse the welcome window's words where they fit.
   - **Footer:** GitHub, releases, MIT license, and the FILBERT acronym.
   `site/style.css` uses CSS custom properties for colors, with a `prefers-color-scheme: dark` override that also inverts the glyphs.
4. **Version tokens.** The HTML contains `__FILBERT_VERSION__`. `scripts/build-site.sh --version X.Y.Z [--appcast path] --out dir` checks the appcast if one is given (well-formed XML with an enclosure for the exact DMG URL), copies `site/`, replaces the token, copies the appcast byte for byte, and fails on unknown arguments, a bad version, a non-empty output directory, a token that is left, or a file referenced by `src`, `href`, or `srcset` that is missing. The appcast check lives here, not in the workflow, so `scripts/test-automatic-updates.py` covers it.
5. **`pages.yml`.** Triggers: `push` to `main` filtered to the site paths, `workflow_dispatch` with an optional `tag` input, and `workflow_call` with a required `tag` input. Steps: resolve the tag (input, or `gh release view` for the latest), download `appcast.xml` from that release, run `build-site.sh` with it, upload the Pages artifact, and deploy. A job-level `concurrency: { group: github-pages, cancel-in-progress: false }` prevents overlapping deploys.
6. **`release.yml`.** After the appcast validation step, upload `$site/appcast.xml` to the release with `gh release upload --clobber`. Replace the `publish-pages` job with a job that calls `./.github/workflows/pages.yml` with the tag and gives it `pages: write`, `id-token: write`, and `contents: read`. Remove the `stable-appcast` artifact upload, because the release asset replaces it.
7. **One-time bootstrap.** v0.20.0 has no `appcast.xml` asset. Before the first site deploy, a maintainer copies the live feed, which already points to v0.20.0, to that release:
   `curl -fsSL https://victorhqc.github.io/filbert/appcast.xml -o appcast.xml && gh release upload v0.20.0 appcast.xml`. `docs/automatic-updates.md` records this step and the new deploy flow.
8. **README.** Add a website link under the badges.
9. **Tests.** `scripts/test-automatic-updates.py` checks that only `pages.yml` deploys, that the release uploads and passes on the appcast, and that `build-site.sh` publishes the signed appcast unchanged and rejects a malformed one or one for another release.

## Risks

- **Feed outage.** A deploy without the appcast stops updates for every installed copy. AC7 makes the build fail closed, and only one workflow can deploy.
- **Stale feed.** A site-only deploy reuses the appcast of the latest release. If someone publishes an older patch release after a newer one, "latest" can point to the wrong tag. The release path passes its tag explicitly, so this applies only to site-only deploys.
- **Bootstrap ordering.** If a site push merges before the bootstrap upload, the deploy fails closed. The current site stays live, so nothing breaks.
- **Stand-in screenshots.** The stand-ins come from before the welcome window, forecasts, and Keep Awake. AC6 blocks the first deploy until the new captures replace them.

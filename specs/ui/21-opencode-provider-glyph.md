## Objective

Give OpenCode Go a bundled provider glyph derived from Simple Icons so it has a recognizable, consistent badge in Filbert.

## Context

- `Sources/Providers/OpenCodeGo/OpenCodeGoProvider.swift` — currently relies on `AIProvider`'s generic `cpu` glyph fallback; it will declare its own asset-backed glyph.
- `Sources/Providers/OpenCodeGo/Resources/` — will contain the generated 24px and 48px glyph assets alongside the provider's strings.
- `scripts/provider-glyphs/opencode.svg` — will vendor the OpenCode SVG from Simple Icons at revision `34c22501f9ac9f22b12f825677ccbab1fb22e14b`, which identifies OpenCode's upstream mark as its source.
- `scripts/generate-provider-glyphs.swift` — will add OpenCode Go to the existing deterministic glyph-generation list.
- `scripts/provider-glyphs/README.md`, `Sources/App/AboutSettingsView.swift`, and `Sources/App/Resources/Localizable.xcstrings` — will extend the existing Simple Icons provenance and acknowledgement from Claude and DeepSeek to OpenCode.
- `Tests/OpenCodeGoProviderTests/` — will verify that OpenCode Go advertises its module-owned glyph, following the provider-glyph contract introduced in (ui 14 AC3).
- Builds on (ui 14) for provider-owned static glyphs and (providers 10) for the OpenCode Go provider boundary.

## Acceptance Criteria

### AC1: OpenCode Go provides a bundled glyph

- **Given** `OpenCodeGoProvider` is registered
- **When** the app reads its `ProviderInfo`
- **Then** the provider advertises `.asset(name: "ProviderGlyph", bundle: .module)` rather than the generic `cpu` fallback
- **And** its existing provider ID, name, authentication, request behavior, and error handling remain unchanged

### AC2: The source is reproducible and license-aware

- **Given** the OpenCode source SVG is added to `scripts/provider-glyphs/`
- **When** a maintainer inspects its provenance
- **Then** the README identifies it as the Simple Icons OpenCode glyph pinned to revision `34c22501f9ac9f22b12f825677ccbab1fb22e14b`
- **And** it retains the existing notice that Simple Icons is CC0 1.0 and subject to its trademark disclaimer
- **And** the app makes no network request to obtain or render the glyph

### AC3: Generated assets follow the existing provider-glyph pipeline

- **Given** the repository-root glyph generator is run
- **When** it processes OpenCode Go
- **Then** it renders the vendored SVG into committed `ProviderGlyph.png` (24px) and `ProviderGlyph@2x.png` (48px) files in `Sources/Providers/OpenCodeGo/Resources/`
- **And** the assets use the generator's existing transparent background, monochrome treatment, and shared inset so the OpenCode badge matches the other provider badges
- **And** re-running the generator for the unchanged source reproduces the same output set without modifying unrelated provider assets

### AC4: The acknowledgement and tests stay accurate

- **Given** the glyph is derived from Simple Icons
- **When** the About view renders its open-source acknowledgement
- **Then** its localized copy names OpenCode alongside Claude and DeepSeek
- **And** the OpenCode Go provider test suite verifies the provider's asset-backed glyph metadata

## Plan

1. Vendor the one-path OpenCode SVG from the pinned Simple Icons revision and document its exact source beside the existing glyph provenance.
2. Add the asset to the deterministic generator, run it, and commit only OpenCode Go's two generated PNGs.
3. Set `OpenCodeGoProvider.providerGlyph` to its module asset and add a focused metadata test.
4. Update the localized About acknowledgement and run the focused provider tests plus the full package test suite.

## Risks

- The Simple Icons mark represents a third-party trademark; retain its disclaimer and do not imply endorsement by OpenCode.
- Small, intricate SVG details may lose clarity at 24px; inspect the generated result and preserve the established shared inset rather than adding provider-specific rendering behavior.

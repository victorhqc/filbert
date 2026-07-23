## Objective

Make the OpenAI Codex provider's CLI prerequisite easy to install from both the README and its Settings setup state.

## Context

- `README.md` — documents supported providers and their optional local CLI requirements.
- `Sources/Core/ProviderProtocol.swift` — provider metadata can expose optional, generic setup help without leaking provider IDs into the App layer.
- `Sources/Providers/OpenAICodex/OpenAICodexProvider.swift` — supplies Codex's official installation destination.
- `Sources/App/SettingsView.swift` — renders an API-key-free provider's setup guidance using generic metadata from (ui 05).
- `Sources/App/Resources/Localizable.xcstrings` — contains translations for every new Settings label and sentence.
- `Tests/CoreTests/ProviderProtocolTests.swift` and `Tests/AppTests/` — cover metadata transport and the Settings presentation as practical.
- The Codex provider remains API-key-free and never handles the CLI's credentials (providers 05, core 03).

## Acceptance Criteria

### AC1: Document the Codex CLI prerequisite

- **Given** a user reads the supported-provider table or requirements in the README
- **When** they choose to track OpenAI Codex usage
- **Then** the README identifies the Codex provider as available through the local `codex` CLI
- **And** it provides the current official macOS/Linux installation command, a verification command, and a sign-in step
- **And** it explains that Filbert does not read or store Codex credentials
- **And** the instructions link to the official Codex CLI documentation instead of duplicating version-specific troubleshooting.

### AC2: Expose generic optional setup help

- **Given** an API-key-free provider has an external setup prerequisite
- **When** it supplies setup-help metadata
- **Then** Core transports a localized link label and HTTPS URL through `ProviderInfo`
- **And** providers with no setup help retain the existing `nil` default
- **And** neither Core nor the App layer branches on a provider identifier (ui 05 AC11).

### AC3: Link missing-Codex setup state to official installation guidance

- **Given** OpenAI Codex is listed in Settings and the `codex` executable is not locatable
- **When** its state is `.setup("Codex CLI not installed")`
- **Then** its API-key-free Settings row shows the existing setup reason and a visible `Install Codex CLI` link
- **And** activating the link opens the official Codex CLI documentation in the user's default browser
- **And** the link is not shown once Codex is configured or for providers that do not supply setup-help metadata.

### AC4: Preserve existing API-key-free provider flows

- **Given** Claude Code or a future API-key-free provider is rendered in Settings
- **When** it has no optional setup-help metadata
- **Then** its existing helper-install, helper-remove, and setup presentation are unchanged
- **And** the new Codex link never offers to install software or accesses credentials on the user's behalf.

### AC5: Localize all new app text

- **Given** the implementation adds user-visible text to the Settings interface or provider metadata
- **When** the app runs in any supported locale
- **Then** every new string is created with `String(localized:)` or an equivalent localized SwiftUI API
- **And** every new source key is added to `Sources/App/Resources/Localizable.xcstrings` with English, German, Spanish (Spain), and Spanish (Mexico) translations
- **And** URLs, CLI commands, provider identifiers, and other non-prose values remain unmodified.

## Plan

1. [x] Add a small optional setup-help metadata value to the provider protocol and `ProviderInfo`, defaulting to `nil`.
2. [x] Have `OpenAICodexProvider` provide the localized label `Install Codex CLI` and the canonical official CLI documentation URL.
3. [x] Render that metadata as a SwiftUI `Link` only in the generic API-key-free `.setup` presentation.
4. [x] Add every new app-text source key and its English, German, Spanish (Spain), and Spanish (Mexico) values to the App string catalog.
5. [x] Add a Codex CLI subsection to the README using the official installer, `codex --version` verification, and the first-run ChatGPT sign-in flow.
6. [x] Add focused metadata and Settings tests, then run the full validation gate.

## Risks

- Codex installation instructions can change; linking to the official CLI documentation keeps the app UI current even if the README command needs a future update.
- A generic link must remain optional so it does not blur Claude Code's separate helper-install flow.
- Missing catalog entries would expose English source keys to non-English users; tests and catalog review must cover every new app string.

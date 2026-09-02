## Objective

Add a `GeminiCLIProvider` that reports the signed-in user's Gemini CLI model quotas and reset times by reusing the CLI's local Google OAuth session.

## Context

- `Sources/Providers/GeminiCLI/` — new provider module; owns Gemini CLI credential access, OAuth refresh, Code Assist requests, decoding, and quota mapping.
- `Sources/Providers/GeminiCLI/Resources/Localizable.xcstrings` — new provider labels, setup guidance, and errors in every locale shipped by the app.
- `Sources/Providers/GeminiCLI/Resources/ProviderGlyph.png` and `ProviderGlyph@2x.png` — new license-safe monochrome Gemini glyphs that follow the provider-owned asset contract (ui 14 AC1).
- `Sources/Core/ProviderProtocol.swift` — unchanged; `UsageLine.percentage` and `resetDate` already represent Gemini's model quota buckets (core 01).
- `Package.swift` and `Sources/App/AppMain.swift` — gain an orthogonal `GeminiCLIProvider` target, test target, and one registration line.
- `README.md` — lists Gemini CLI as supported and documents installation, Google sign-in, Keychain access, tracked data, and the private API limitation.
- The provider uses `.apiKeyFree` because Gemini CLI owns the Google login session; Filbert does not ask for a Gemini API key (core 03).
- Gemini CLI stores current Google-login credentials in the macOS Keychain under service `gemini-cli-oauth`, account `main-account`. The legacy `~/.gemini/oauth_creds.json` file and Gemini API-key authentication are out of scope.
- The credential envelope and token field names follow Gemini CLI's public `OAuthCredentials` and `OAuthToken` types. `expiresAt` is a Unix timestamp in milliseconds, and the Keychain value is JSON-serialized by Gemini CLI's keychain storage.
- Gemini CLI's open-source implementation is the reference contract:
  - `OAuthCredentialStorage` defines the Keychain service, account, and token payload.
  - `setupUser` calls `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` to resolve the user's managed or configured Code Assist project.
  - `CodeAssistServer.retrieveUserQuota` calls `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` with that project.
  - Each response bucket may contain `modelId`, `tokenType`, `remainingFraction`, `remainingAmount`, and `resetTime`. Only `modelId` and `remainingFraction` are needed to display usage.
- Public implementations also show `loadCodeAssist` project references as either a string or an object with `id`/`projectId`, and some already-onboarded accounts return `currentCloudaicompanionProject`; the provider accepts those additive response shapes without onboarding or mutation.
- The public contract evidence is [`OAuthCredentialStorage`](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/code_assist/oauth-credential-storage.ts), [`OAuthToken`](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/mcp/token-storage/types.ts), [`Code Assist types`](https://github.com/google-gemini/gemini-cli/blob/main/packages/core/src/code_assist/types.ts), and the response-shape regression documented in [ZeroClaw PR #7560](https://github.com/zeroclaw-labs/zeroclaw/pull/7560). These sources are public contract evidence, not live credentials or a live API capture.
- `remainingFraction` is a value from `0` through `1`, where `1` means unused quota. Filbert converts it to used percentage with `(1 - remainingFraction) × 100`.
- These are Gemini CLI / Code Assist quotas. They are not Gemini API, AI Studio, Vertex AI, Google Cloud billing, or token-spend history.

## Acceptance Criteria

### AC1: Detect a supported Gemini CLI login

- **Given** the provider is registered
- **When** Core asks for its authentication shape and setup state
- **Then** `authShape` is `.apiKeyFree`
- **And** the provider reports configured only when the `gemini-cli-oauth` / `main-account` Keychain item contains a decodable access token or refresh token
- **And** a missing item produces `.setup("Sign in to Gemini CLI")` with a setup-help link to Google's Gemini CLI authentication documentation
- **And** an unreadable or unsupported credential payload produces a distinct localized recovery message that asks the user to update Gemini CLI and sign in again

### AC2: Keep Gemini credentials inside the Keychain boundary

- **Given** the user has signed in to Gemini CLI with Google
- **When** Filbert reads the CLI credential
- **Then** it uses the macOS Security framework through an injectable credential-store boundary
- **And** it reads only service `gemini-cli-oauth`, account `main-account`
- **And** it never reads `~/.gemini/oauth_creds.json`, Gemini API-key environment variables, browser cookies, `gcloud` credentials, or unrelated Keychain items
- **And** access tokens and refresh tokens are retained only for the active fetch, never logged, copied into Filbert's Keychain item, written to disk, or included in surfaced errors

### AC3: Refresh an expired access token without taking ownership of the session

- **Given** the stored access token is expired or expires within 60 seconds and a refresh token is present
- **When** a quota refresh starts
- **Then** the provider exchanges the refresh token at `https://oauth2.googleapis.com/token` using the installed-application OAuth client ID published in Gemini CLI's source and sends no client secret
- **And** it uses the returned access token only for the active fetch and does not overwrite Gemini CLI's Keychain item
- **And** a missing, revoked, or rejected refresh token produces a typed signed-out error instructing the user to run Gemini CLI and sign in again
- **And** a still-valid access token skips the token exchange

### AC4: Resolve the server-authoritative Code Assist project

- **Given** a valid Google access token
- **When** the provider prepares the quota request
- **Then** it sends an authenticated `POST` to `https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` using only the minimal Gemini CLI metadata required by the upstream contract
- **And** it does not read `GOOGLE_CLOUD_PROJECT` or `GOOGLE_CLOUD_PROJECT_ID`, or send a locally configured project seed
- **And** it uses the first non-empty project reference from `cloudaicompanionProject` and then `currentCloudaicompanionProject`, accepting either a string or an object containing `id` or `projectId`, as the project for `retrieveUserQuota`
- **And** it does not onboard accounts, accept terms, perform account validation, or call any other Code Assist method
- **And** a response requiring onboarding, validation, or an explicit Google Cloud project becomes a typed setup error directing the user to complete setup in Gemini CLI

### AC5: Fetch quota without generating content

- **Given** the Code Assist project was resolved
- **When** `fetchQuota(auth:baseURL:)` runs
- **Then** it sends one authenticated `POST` to `https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` with the resolved project
- **And** it performs no model inference, token count, telemetry, conversation, billing, or mutation request
- **And** it ignores `baseURL` and rejects redirects or alternate hosts so the bearer token is sent only to `cloudcode-pa.googleapis.com`
- **And** concurrent fetches are coalesced so only one credential read and one quota workflow are active

### AC6: Map every valid quota bucket without inventing limits

- **Given** `retrieveUserQuota` returns one or more buckets
- **When** the provider maps the response
- **Then** each bucket with a non-empty `modelId`, a finite `remainingFraction` in `0...1`, and an optional valid ISO-8601 `resetTime` becomes one `UsageLine`
- **And** the line's `percentage` is the used percentage `(1 - remainingFraction) × 100`, its `resetDate` comes from `resetTime`, and its label identifies the model plus a localized known `tokenType`
- **And** unknown or absent `tokenType` remains displayable through a generic localized quota label
- **And** `remainingAmount` may be shown as server-supplied detail but is never used to infer a total, window duration, cost, or token spend
- **And** an absent, `null`, or empty `buckets` collection is a valid no-limits result with no usage lines and the localized `"No usage limits reported"` headline
- **And** unknown JSON fields are ignored, while malformed buckets in a non-empty collection are omitted and an all-malformed response fails as payload drift rather than showing fake zero usage

### AC7: Derive the headline from the most constrained reported bucket

- **Given** at least one valid quota bucket
- **When** the provider builds `ProviderQuota`
- **Then** the headline uses the bucket with the smallest `remainingFraction`
- **And** it shows the corresponding used percentage and `QuotaFormatting.countdown(to:)` when a reset time exists
- **And** ties are ordered deterministically by normalized model ID and token type
- **And** no wording claims that the selected bucket represents an unreported quota dimension

### AC8: Preserve stable activity observations

- **Given** valid mapped buckets
- **When** the provider creates `ProviderActivityObservation`
- **Then** each bucket contributes one `.usage` metric whose ID is derived deterministically from normalized `modelId` and `tokenType`
- **And** its value is the used percentage as a `Decimal`
- **And** response ordering changes do not change metric identity or line ordering

### AC9: Fail safely and respect rate limits

- **Given** Keychain denial, signed-out credentials, `401`, `403`, `429`, `5xx`, a network failure, timeout, redirect, or undecodable data
- **When** a refresh runs
- **Then** the provider throws a typed, localized error and returns no placeholder quota
- **And** `401` maps to signed out, `403` to account or project setup required, and `429` to rate limited
- **And** retryable `429` and `5xx` responses use bounded exponential backoff, honor a valid `Retry-After`, and make no more than three attempts
- **And** network failures, timeouts, decoding failures, and generic HTTP failures have distinct user-facing recovery messages
- **And** the complete credential, project-resolution, and quota workflow has a bounded deadline so retries cannot block a refresh indefinitely
- **And** Core can continue showing the previous stale snapshot and refreshing other providers (core 01 AC4)
- **And** logs contain status and failure category only, never response bodies, tokens, project IDs, or account identifiers

### AC10: Keep the provider orthogonal and localized

- **Given** the provider is implemented
- **When** the package builds and tests run
- **Then** `GeminiCLIProvider` depends only on `Core` and Apple system frameworks
- **And** no existing provider changes and App/Core contain no behavior branch keyed on `"gemini-cli"`
- **And** all user-facing labels, setup guidance, and errors resolve through the provider's String Catalog in `en`, `de-DE`, `es-ES`, and `es-MX`
- **And** sanitized Keychain and `loadCodeAssist` contract fixtures, plus injected Keychain/network/logging doubles, cover valid credential envelopes, valid buckets, fraction-only buckets, multiple token types, malformed data, empty limits, token refresh, setup states, project-shape fallback, host rejection, retries, distinct failures, redaction, deterministic ordering, and concurrent fetch coalescing
- **And** the repository validation gate passes without new warnings in changed files

### AC11: Ship a license-safe Gemini provider glyph

- **Given** the `GeminiCLIProvider` target is built
- **When** the app renders Gemini CLI in Settings or the quota popover
- **Then** `scripts/provider-glyphs/gemini.svg` is the committed source for the generated monochrome assets
- **And** `Sources/Providers/GeminiCLI/Resources/ProviderGlyph.png` and `ProviderGlyph@2x.png` are bundled as monochrome 1× and 2× assets
- **And** the glyph is an original, license-safe rendering of the recognizable Gemini sparkle silhouette rather than a copied Google raster
- **And** `providerGlyph` returns `ProviderGlyph.asset(name: "ProviderGlyph", bundle: .module)` so the generic provider UI renders it without an App-layer provider-ID branch (ui 14 AC1)
- **And** an asset test verifies both files can be loaded from the provider bundle

### AC12: Document Gemini CLI support in the README

- **Given** Gemini CLI support is ready to ship
- **When** a user reads `README.md`
- **Then** the supported-providers table lists Gemini CLI as done and says it tracks model quotas and reset times from the local CLI login
- **And** the local-session count and surrounding setup text include Gemini CLI rather than claiming only the existing three providers use local sessions
- **And** a "Gemini CLI setup" section links to Google's official install and authentication documentation and explains that the user must install Gemini CLI and sign in with Google before enabling the provider
- **And** the section explains that Filbert reads Gemini CLI's macOS Keychain credential, may trigger a macOS access prompt, does not ask for a Gemini API key, and never sends a model prompt
- **And** the section distinguishes Gemini CLI / Code Assist quota from Gemini API, AI Studio, Vertex AI, and Cloud billing usage
- **And** the section warns that quota retrieval uses Google's private `v1internal` interface and may require a Filbert update if Google changes it

## Plan

1. [x] Add `GeminiCLIProvider` and `GeminiCLIProviderTests` package targets, provider resources, and the App registration.
2. [x] Add an injectable credential store backed by Security framework generic-password reads for Gemini CLI's current Keychain item. Decode only the token fields needed for this fetch.
3. [x] Add a small OAuth client that uses Gemini CLI's published installed-application client ID to obtain an ephemeral access token when necessary.
4. [x] Add a Code Assist client with fixed allow-listed hosts, redirect rejection, bounded timeouts, retry policy, and private wire types for `loadCodeAssist` and `retrieveUserQuota`.
5. [x] Map valid buckets into deterministically ordered `UsageLine` and activity metrics. Keep all model and token-type interpretation inside the provider.
6. [x] Add localized resources, a license-safe monochrome provider glyph, setup guidance, and redacted typed errors.
7. [x] Update the README provider table, local-session guidance, Keychain explanation, and setup documentation for Gemini CLI.
8. [x] Close review follow-ups with public-contract fixtures, project-shape fallback, empty-limit handling, complete localization, distinct failure handling, bounded workflow cancellation, logging redaction, glyph-source registration, README status text, and focused regression tests; then rerun the full validation gate.

No production code is written until this spec is reviewed.

## Risks

- **Private API contract.** `v1internal` is implemented by Google's open-source Gemini CLI but is not a public third-party API. Google may change the endpoint, payload, OAuth client, or access policy without notice.
- **Cross-application Keychain access.** macOS may show an access prompt or deny Filbert access to Gemini CLI's item. The provider must treat denial as setup state, not weaken Keychain protections or fall back to plaintext credentials.
- **Upstream storage changes.** Gemini CLI may change its Keychain service, account, or payload. Filbert supports only the reviewed format and fails closed on drift.
- **Incomplete quota reporting.** The server may omit enforced token buckets. Filbert can report only returned buckets and must not imply that a positive request quota guarantees model availability.
- **Project bootstrap dependency.** Resolving the managed Code Assist project adds one read-only request before each quota read. This avoids persisting a project/account identifier but adds latency and another upstream failure point.
- **OAuth client coupling.** Refresh uses Gemini CLI's published installed-application client identity. Rotation or a policy change can break refresh until Filbert is updated.

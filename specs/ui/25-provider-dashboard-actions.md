## Objective

Add a trailing dashboard action to provider settings cards and align each description with its enablement toggle.

## Context

- `Sources/App/SettingsVisualComponents.swift` — the shared header currently places the description below the entire status-and-toggle stack, creating the unwanted vertical gap.
- `Sources/App/SettingsView.swift` — API-key cards contain key actions and the Advanced disclosure.
- `Sources/App/APIKeyFreeSettingsRow.swift` — API-key-free cards contain helper and setup actions.
- `Sources/Core/ProviderMetadata.swift` — provider-owned metadata supplies optional external account destinations without provider-ID branches in App.
- `Sources/Providers/` — individual providers declare their destination.
- This refines the existing settings presentation and preserves enablement behavior (ui 15, ui 17).

## Acceptance Criteria

### AC1: Compact, aligned header

- **Given** any provider card at the supported Settings window width
- **When** its header renders
- **Then** the provider name and status pill occupy the first row, and the description and Enabled toggle occupy the second row, vertically centered with each other
- **And** the description remains aligned with the name after the provider icon
- **And** long descriptions can wrap without overlapping or displacing the toggle outside the card
- **And** any custom-URL annotation does not push the description beneath the toggle.

### AC2: Trailing external action

- **Given** a provider declares an account destination
- **When** its settings card renders
- **Then** a small, neutral “Go to Dashboard” button with a globe icon appears at the far right of the action row, opposite Clear Key or Remove Helper when present
- **And** the action appears only while the provider is enabled
- **And** an enabled, unconfigured provider still shows the action, with a trailing action row when there is no existing management button
- **And** Advanced remains below the action row and setup guidance remains readable
- **And** activating the action opens the destination in the default browser without changing credentials or enablement.

### AC3: Provider-owned destinations

- **Given** the seven destinations confirmed by the user
- **When** provider metadata is configured
- **Then** each registered provider uses its destination from the table below
- **And** every destination uses the “Go to Dashboard” label
- **And** providers without a declared destination omit the action without leaving an empty row
- **And** destinations are optional metadata owned by each provider; App and Core contain no provider-ID routing table.

| Provider | Destination |
| --- | --- |
| Claude Code | `https://claude.ai/settings/usage` |
| Cursor | `https://cursor.com/dashboard` |
| DeepSeek | `https://platform.deepseek.com/usage` |
| OpenAI Codex | `https://chatgpt.com/settings/general-settings` |
| OpenCode Go | `https://opencode.ai/console/` |
| Z.AI | `https://z.ai/manage-apikey/coding-plan/personal/usage` |
| Gemini CLI | `https://one.google.com/settings` |

### AC4: Native styling and accessibility

- **Given** supported locales, keyboard navigation, and VoiceOver
- **When** the updated cards are used
- **Then** new action labels are localized, the action has an accessible provider-specific label, and existing toggle accessibility is preserved
- **And** buttons match existing small neutral controls in light and dark appearance.

## Plan

1. [x] Add optional account-link metadata with source-compatible defaults and declare the supplied destinations in their provider modules.
2. [x] Restructure the shared header into name/status and description/toggle rows.
3. [x] Add a shared external action presentation to both card variants, preserving existing key, helper, setup, and Advanced controls.
4. [x] Add localized labels and verify metadata defaults and destinations with focused tests.
5. [x] Run the repository validation gate and inspect header wrapping and action placement across configured, unconfigured, and disabled cards.

## Risks

- Google One settings manage personal subscriptions; organizational Gemini Code Assist accounts may require their administrator's management console.
- External account URLs can change or require browser sign-in; Filbert passes no credentials to them.
- Long localized descriptions and setup states can affect card height; preserve readable wrapping and accessible controls.

## Validation

- All seven provider URLs match the approved destination table. New labels cover all four supported locales.
- SwiftFormat 0.62.1 passes. SwiftLint 0.65.0 reports zero serious violations and five existing warnings in untouched files when pointed at the Command Line Tools toolchain.
- Default `swift build` is blocked by a build-system initialization error (`Unknown error parsing property list`). Native SwiftPM reaches compilation, but the default macOS 27 SDK lacks the SwiftUI macro plugin used by existing `@State` properties. Debug and release builds pass using `--build-system native --sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`.
- The complete test suite was attempted with the same build settings but cannot compile because this Command Line Tools installation lacks `XCTest`. The full validation gate remains incomplete until a working Xcode test toolchain is available.
- Standalone executable checks pass for registry propagation of provider-owned links and nil defaults. The corresponding XCTest regression tests are included.
- Isolated renders of the actual card views were inspected in light and dark mode at the minimum 520-point Settings width: DeepSeek configured, Claude ready, disabled, and setup-needed. The description/toggle row and trailing account actions align correctly. Preview data uses a placeholder SF Symbol.

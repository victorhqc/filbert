## Objective

Remove the per-provider "Clear Key" button from the popover footer, since key
management now lives entirely in Settings (ui 02).

## Context

- `Sources/App/QuotaView.swift` — `quotaContent(_:providerId:)` renders a
  "Clear Key" button next to the Refresh control in the popover footer. It was
  the only key-management surface before Settings existed; Settings has since
  taken over (ui 02 AC3).
- `Sources/App/SettingsView.swift` — `ProviderSettingsRow` already renders a
  "Clear Key" button when the provider is configured, so removing the popover's
  copy loses no functionality.
- Builds on (ui 02 AC3) and (ui 05 AC8). The (ui 05 AC8) suppression rule for
  `.apiKeyFree` providers becomes moot — the button is gone for every provider.
- Cross-references: obsoletes the popover half of (ui 05 AC8); (ui 02 AC3) is
  untouched.

## Acceptance Criteria

### AC1: No "Clear Key" in the popover footer
- **Given** any configured provider (`.apiKey` or `.apiKeyFree`)
- **When** its section renders in the popover
- **Then** the footer shows only the last-updated label and the Refresh
  control — no "Clear Key" button

### AC2: Settings remains the sole key-management surface
- **Given** a `.apiKey` provider that is configured
- **When** the user opens Settings → that provider's row
- **Then** the "Clear Key" button is still present and still calls
  `viewModel.deleteKey(for:)` — unchanged from (ui 02 AC3)

### AC3: The view-model `isAPIKeyFree(_:)` forwarder is deleted; the registry
method stays
- **Given** the popover no longer calls `viewModel.isAPIKeyFree(_:)`
- **When** the codebase is grepped for callers of
  `QuotaViewModel.isAPIKeyFree(_:)`
- **Then** no caller remains — the forwarder in `QuotaViewModel.swift` is
  deleted to avoid dead code
- **And** `ProviderRegistry.isAPIKeyFree(_:)` is **kept**, because
  `QuotaViewModel.saveOverrideURL(_:for:)` still calls it to refuse base-URL
  overrides for `.apiKeyFree` providers (ui 03). Only the App-layer forwarder
  goes — the Core-layer method is untouched

## Plan

One file edit in `Sources/App/QuotaView.swift`:

1. Delete the `if !viewModel.isAPIKeyFree(providerId) { Button("Clear Key") … }`
   block in `quotaContent(_:providerId:)`.
2. Drop the now-unused `isAPIKeyFree(_:)` forwarder from
   `QuotaViewModel.swift` if grep confirms it has no other caller.

No change to `ProviderProtocol`, the registry, or any provider. No new
localization keys — the removed string stays in the catalog (harmless) or is
pruned in a follow-up.

## Risks

- Removing the button changes the popover's footer width; the Refresh control
  now sits flush with the trailing edge. Visual-only, no layout math affected.
- If a future provider wanted a per-section destructive action, it would need
  its own spec — this change cements the popover as read-only.

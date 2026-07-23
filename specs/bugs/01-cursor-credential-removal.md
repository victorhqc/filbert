## Objective

Make the Settings "Remove Helper" action delete everything Cursor-related that
filbert stores, so the provider leaves the popover.

## Context

- `Sources/Providers/Cursor/CursorProvider.swift` — the bug's home. `CursorProvider`
  never overrides `removeHelper()`, so it inherits the protocol default from
  `Sources/Core/ProviderProtocol.swift` that throws `ProviderSetupError.notSupported`.
  The Settings remove action therefore errors instead of clearing anything.
- `Sources/Providers/Cursor/CursorCredentialVault.swift` — the
  `CursorCredentialVault` protocol and `KeychainCursorCredentialVault` define
  `load`/`save`/`replaceAccessToken` but no `clear()`, so there is currently no
  path to drop the `cursor` entry from the shared Keychain vault.
- `Sources/Core/Keychain.swift` — already exposes `delete(for:)` (used by the
  `.apiKey` clear flow), which the new vault `clear()` can lean on.
- `Sources/App/SettingsView.swift` + `Sources/App/QuotaViewModel.swift` — the
  remove control routes `QuotaViewModel.removeHelper(for:)` → registry →
  `provider.removeHelper()`, then re-reads setup state. No UI changes are
  needed; once the provider clears its credentials and reports a `setup` state,
  the popover drops the section per (ui 02 AC3).
- Builds on (providers 07 AC4) for the credential store and (ui 05 AC5) for the
  remove control. Cursor has no helper — for this provider the remove action is
  a credential clear.

## Acceptance Criteria

### AC1: The remove action deletes Cursor's stored credentials
- **Given** Cursor has an imported credential pair in filbert's shared Keychain
  vault (the `cursor` entry)
- **When** the user clicks the remove control in the Cursor Settings row
- **Then** `CursorProvider.removeHelper()` deletes the `cursor` entry from the
  shared vault instead of throwing `ProviderSetupError.notSupported`

### AC2: Removed credentials move Cursor out of the popover
- **Given** Cursor is showing in the popover in the `loaded` state
- **When** removal completes successfully
- **Then** the provider transitions to a `setup(...)` state and the popover no
  longer renders the Cursor section, matching (ui 02 AC3)

### AC3: Removal is idempotent
- **Given** the vault entry is already absent
- **When** the remove action runs
- **Then** it succeeds without surfacing an error, so repeated clicks and a
  remove-then-relaunch sequence are safe

## Plan

1. **Vault: add `clear()`.** Extend the `CursorCredentialVault` protocol with
   `clear() throws` and implement it on `KeychainCursorCredentialVault` to
   delete the `cursor` provider entry via the existing `Keychain.delete(for:)`
   path. [x]
2. **Provider: override `removeHelper()` to clear credentials.** `CursorProvider`
   calls the new vault clear so the Settings remove action stops throwing and
   removes the stored pair. [x]
3. **Tests.**
   - `removeHelper()` clears the vault entry (vault stubbed) and `isConfigured()`
     reports `false` afterwards.
   - Removal is idempotent when the vault is already empty. [x]

No code is written until this spec is reviewed.

## Risks

- **Cross-launch re-bootstrap is out of scope.** This spec removes only what
  filbert owns. `CursorImportCoordinator.loadOrBootstrap` (providers 07 AC4)
  can re-import from Cursor's own first-party Keychain entries / Desktop SQLite
  on the *next* launch, resurrecting the provider. Within the session, clearing
  the vault correctly removes the popover section (the one-shot bootstrap guard
  already ran). We deliberately do not touch Cursor's own keychain items —
  whether the user uninstalls Cursor is their call, not filbert's. If the
  resurrection becomes annoying, a follow-up "suppress bootstrap after explicit
  removal" flag is the clean fix.
- **The button is labeled "Remove Helper".** Cursor has no helper; the copy
  ("Helper installed and active." / "Remove Helper" from ui 05 AC5) is
  Claude-Code-centric. This spec fixes behavior only; relabeling per provider is
  a separate UI follow-up.
- **Provider orthogonality.** The credential-clear behavior is owned entirely
  by the Cursor module; the App layer still dispatches only on `authShape`,
  preserving (ui 05 AC11) and (core 01).

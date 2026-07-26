## Objective

Make every provider explicitly enableable in Settings and prevent disabled providers from running setup discovery, credential import, refresh, synchronization, or quota gathering while preserving their keys and local installations.

## Context

- `Sources/Core/ProviderEnablement.swift` — new provider-ID-neutral `UserDefaults` storage for the user's enabled/disabled choice; enablement is preference state, not a secret.
- `Sources/Core/ProviderRegistry.swift` — becomes the enforcement boundary that rejects work for disabled providers before reading provider-owned state or invoking an `AIProvider` method.
- `Sources/Core/ProviderProtocol.swift` — keeps authentication shape and provider configuration separate from enablement; no provider-specific enablement requirement is added to individual provider modules.
- `Sources/App/QuotaViewModel.swift` — owns the observable enabled set, starts work only for enabled providers, and stops provider-owned tasks when a provider is disabled.
- `Sources/App/SettingsView.swift` and `Sources/App/SettingsVisualComponents.swift` — add one enable/disable toggle to every provider card and distinguish disabled, enabled-but-unconfigured, and ready states.
- `Sources/Providers/Cursor/CursorProvider.swift` — its `isConfigured()` and `currentSetupState()` paths can bootstrap credentials from Cursor-owned storage, so neither may be called while Cursor is disabled (providers 07 AC4, core 04 AC4).
- This changes the implicit configuration-based activation introduced by (ui 02 AC3, AC4, AC5, AC7) and the automatic API-key-free setup checks from (core 03 AC5, AC6) into an explicit enablement gate.
- Existing API-key-free setup and controls remain as specified by (ui 05), but they are reachable only after the user enables that provider.

## Acceptance Criteria

### AC1: Enablement and configuration are independent

- **Given** any registered provider
- **When** Core evaluates its lifecycle
- **Then** it treats `isEnabled` and `isConfigured` as separate predicates
- **And** a provider runs only when both predicates are true
- **And** authentication shape, a saved key, an installed CLI, a helper, cached data, or imported credentials do not override an explicit disabled choice
- **And** the implementation remains provider-ID-neutral and never branches on `"cursor"`, `"claude-code"`, or another provider ID.

### AC2: Every provider has a persistent Settings toggle

- **Given** the Providers tab lists the registered providers
- **When** a provider card renders
- **Then** its header contains a localized, accessible enable/disable `Toggle`
- **And** changing the toggle persists a Boolean for that provider ID in `UserDefaults`
- **And** the choice survives app relaunches and is independent of provider ordering, collapse state, credentials, and provider-owned files
- **And** adding a future provider requires no Settings or App-layer branch beyond registration (ui 02 AC9).

### AC3: New and upgraded installations preserve intentional opt-in

- **Given** no explicit enablement value exists for a provider
- **When** its initial value is resolved
- **Then** an API-key provider with a key already stored in Filbert's consolidated Keychain is enabled and the resolved value is persisted
- **And** an API-key provider without a stored key is disabled
- **And** every API-key-free provider is disabled, even if its CLI, helper, cache, or externally owned credentials can be found
- **And** once an explicit value exists, it is authoritative and no later credential or installation check changes it
- **And** this resolution reads only Filbert's own Keychain for API-key providers; it invokes no provider method and reads no CLI-owned Keychain item, SQLite database, settings file, cache, executable path, or network resource.

### AC4: Saving an API key enables the provider in the same action

- **Given** an API-key provider is disabled or enabled-but-unconfigured
- **When** the user submits a valid non-empty key in Settings
- **Then** Filbert saves the key first and enables the provider only after that save succeeds
- **And** one successful submission updates the toggle, configuration state, popover membership, refresh scheduling, and initial quota fetch without a second user action
- **And** a failed Keychain save leaves the previous enablement value unchanged and surfaces the existing inline error
- **And** clearing a key stops fetches by making the enabled provider unconfigured but does not silently change its toggle.

### AC5: Manual disable preserves configuration

- **Given** an enabled provider has a saved API key, installed CLI or helper, imported credentials, cached quota, or a custom base URL
- **When** the user switches the provider off
- **Then** Filbert persists the disabled choice and removes the provider from the popover immediately
- **And** it stops that provider's refresh loop, cancels Filbert-owned pending work for it where cancellation is supported, clears its transient loading/refresh presentation, and ignores any late result
- **And** it does not delete or modify the API key, imported credentials, helper, CLI installation, cache, custom base URL, or provider-owned data
- **And** switching the provider on later reuses the preserved configuration.

### AC6: Disabled providers have a hard no-work boundary

- **Given** a provider is disabled
- **When** the app launches, Settings opens, a global refresh runs, another provider refreshes, five minutes elapse, or provider ordering changes
- **Then** the registry does not call that provider's `isConfigured()`, `currentSetupState()`, `fetchQuota(...)`, `proactiveRefresh()`, `canInstallHelper()`, `installHelper()`, `removeHelper()`, or `importCredentials()`
- **And** no provider-owned filesystem lookup, executable discovery, helper migration, external credential bootstrap, cache read, token refresh, network request, or synchronization is started on its behalf
- **And** reading static `ProviderInfo` metadata to render the Settings card is allowed
- **And** API-key Settings actions may read or update Filbert's own Keychain only in direct response to the user.

### AC7: Enabling starts only the work appropriate to the provider

- **Given** a disabled provider
- **When** the user switches it on
- **Then** an API-key provider with a saved key begins its initial fetch and five-minute refresh loop
- **And** an API-key provider without a key remains enabled-but-unconfigured and performs no fetch until a key is saved
- **And** an API-key-free provider may then run its provider-owned configuration and setup-state checks
- **And** a configured API-key-free provider begins its initial fetch and refresh loop
- **And** an unconfigured API-key-free provider shows its existing setup guidance and performs no quota fetch until setup succeeds.

### AC8: Settings communicates disabled state without probing the provider

- **Given** a provider is disabled
- **When** its Settings card renders
- **Then** the status presentation says "Disabled" regardless of stored configuration
- **And** an API-key-free card shows a localized prompt to enable the provider before setup and does not show install, remove, import, or provider-derived setup controls
- **And** an API-key card retains its key-management controls so saving a key can satisfy AC4
- **And** enabled cards continue to show their configured, ready, setup-needed, loading, and error presentations from (ui 05, ui 15).

### AC9: Popover and refresh paths include only enabled, configured providers

- **Given** any mix of enabled, disabled, configured, and unconfigured providers
- **When** the popover derives its provider list or a refresh path executes
- **Then** only providers that are both enabled and configured appear in `configuredProviderIds` and the popover
- **And** initial bulk refresh filters disabled and unconfigured providers before creating child tasks
- **And** manual and automatic per-provider refresh use a provider-scoped registry operation rather than causing `fetchAll()` to call unrelated providers
- **And** one provider's enablement change does not restart, fetch, or cancel another provider.

### AC10: Registry gates every provider operation

- **Given** App code accidentally requests an operation for a disabled provider
- **When** the request reaches `ProviderRegistry`
- **Then** the registry returns without invoking the provider
- **And** setup, helper, credential-import, proactive-refresh, and quota APIs share the same enablement check
- **And** UI gating is treated as presentation convenience rather than the only safety boundary
- **And** registry tests verify the provider spy receives zero calls for every gated operation.

### AC11: Enablement behavior is tested across auth shapes and relaunches

- **Given** isolated `UserDefaults`, Keychain stubs, and provider spies
- **When** the Core and App test suites run
- **Then** they cover fresh defaults, the API-key upgrade rule, API-key-free default-off behavior, explicit values overriding later configuration changes, persistence across a recreated store, save-key auto-enable, clear-key independence, disable/re-enable with preserved configuration, late-result rejection, and provider isolation
- **And** a Cursor-shaped spy proves that launch and Settings rendering perform zero configuration, bootstrap, setup-state, import, filesystem, or fetch calls until its toggle is enabled
- **And** all existing provider suites continue to pass without adding enablement logic to individual provider implementations.

### AC12: New UI copy is localized and accessible

- **Given** the app runs in any supported locale or with assistive technology
- **When** the enablement control and disabled guidance render
- **Then** every new user-facing string is stored in the App String Catalog and resolved through `String(localized:)`
- **And** the toggle has a provider-specific accessibility label and value
- **And** enabled, disabled, configured, and error states are not communicated by color alone (ui 15 AC5).

## Plan

1. [x] Add a `ProviderEnablement` value in Core, backed by a `[String: Bool]` dictionary in `UserDefaults`, with test injection matching `ProviderOrder` and `ProviderCollapseState`. Resolve and persist a missing value using AC3 without invoking an API-key-free provider.
2. [x] Inject or otherwise share the enablement source with `ProviderRegistry`. Gate `isConfigured`, setup-state refresh, helper management, credential import, proactive refresh, bulk fetch, and provider-scoped fetch before any provider callback.
3. [x] Add a provider-scoped quota-fetch entry point. Keep `fetchAll()` for the one initial bulk refresh, but filter its task group to enabled, configured providers; use the scoped entry point for manual refresh and each five-minute loop.
4. [x] Add observable enablement state and a toggle action to `QuotaViewModel`. Enabling resolves setup/configuration before starting eligible work. Disabling stops the provider loop, cancels tracked work where possible, discards late results, removes the provider from derived popover state, and leaves persistent configuration untouched.
5. [x] Update key save and clear flows. A successful save persists enablement before starting the initial fetch; a failed save does not alter it. Clearing the key retains the toggle but stops work because configuration is now absent.
6. [x] Add the toggle to the shared provider-card header. Disabled API-key-free cards render static guidance without evaluating provider setup capabilities; disabled API-key cards keep key-management controls.
7. [x] Add localized App String Catalog entries for the toggle, disabled status, disabled guidance, and accessibility text.
8. [x] Add Core and App tests for AC3 through AC11, including spies for every provider protocol hook and isolated persistence tests.

No production code is written until this spec is reviewed.

## Risks

- **Upgrade behavior intentionally differs by auth shape.** Existing API keys are strong evidence of prior opt-in, so they migrate to enabled. An installed CLI or discoverable local session is not evidence that the user opted Filbert into reading it, so every API-key-free provider migrates to disabled.
- **Disabling cannot undo a provider call that already began while enabled.** Filbert cancels work it owns and rejects late results, but a network request or filesystem operation may already have crossed its side-effect boundary. The hard guarantee is that no new provider call starts after the disabled value is applied.
- **Enablement must be enforced below the UI.** A toggle-only implementation would leave launch, bulk refresh, setup-state, and future call sites able to probe disabled providers. The registry gate and zero-call spy tests are required to prevent that regression.
- **Keychain migration may still prompt once.** Resolving missing enablement for an existing API-key provider can require reading Filbert's consolidated Keychain item. It never accesses provider-owned credential stores, and the resolved Boolean is persisted so the migration is not repeated.
- **Enabled-but-unconfigured is a real state.** Clearing a key no longer implies disabling the provider. UI derivation must keep the toggle on while omitting the provider from the popover and suppressing refresh work.

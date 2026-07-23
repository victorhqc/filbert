## Objective
Rename the project and product to Filbert while preserving existing user configuration through a temporary, isolated migration bridge.

## Context
- `Package.swift` — owns the Swift package name and generated resource-bundle prefix.
- `Sources/App`, `Sources/Core`, and `Sources/Providers` — contain the displayed name, storage identifiers, client metadata, and Claude integration paths.
- `packaging`, `scripts/build-dmg.sh`, and `.github/workflows/release.yml` — define the app bundle, executable, bundle identifier, entitlements, DMG, checksums, and release notes.
- `README.md` and `CONTRIBUTING.md` — introduce the project and document installation, development, and release artifacts.
- `Tests` — contains storage namespaces, filesystem fixtures, and expected Claude chain markers.
- `specs` — records project-name references and paths that must match the renamed implementation.
- The Keychain layout builds on (core 01), and the Claude helper and cache behavior build on (providers 02).

## Acceptance Criteria

### [x] AC1: Establish the Filbert identity
- **Given** any user-facing project or product reference
- **When** the renamed application, documentation, or release metadata is inspected
- **Then** it uses `Filbert` as the proper product name and `filbert` for lowercase identifiers
- **And** the README expands FILBERT as “Friendly Icon Letting Budgets Explain Remaining Tokens”
- **And** it describes Filbert as a simple, friendly menu-bar companion that warns when token budgets are running low

### [x] AC2: Rename build and release artifacts
- **Given** a package build or DMG release build
- **When** SwiftPM and the packaging script produce their outputs
- **Then** the package is named `filbert`
- **And** the app bundle and executable are named `Filbert`
- **And** the bundle identifier is `com.victorhqc.filbert`
- **And** release artifacts follow `Filbert-<version>-<arch>` naming
- **And** generated resource bundles use the `filbert_` prefix
- **And** the entitlements file is named for Filbert

### [x] AC3: Rename runtime identity
- **Given** Filbert is running
- **When** the app exposes an accessibility label, localized message, provider client name, temporary path, cache path, helper path, chain marker, preference namespace, or Keychain service
- **Then** the canonical identifier refers to Filbert
- **And** provider-specific types such as `ZAIUsageDetail` remain unchanged because they describe provider usage rather than the project

### [x] AC4: Migrate Keychain secrets safely
- **Given** the Filbert Keychain service has no consolidated provider store and the previous service contains provider secrets
- **When** Filbert first loads a provider secret
- **Then** it reads the previous consolidated store and any supported per-provider items
- **And** it writes and verifies the consolidated store under service `filbert`
- **And** it deletes previous items only after verification succeeds
- **And** a migration failure leaves the previous items intact and returns a recoverable Keychain error
- **And** secret values are retained in memory only for the duration already required by the Keychain store

### [x] AC5: Migrate preferences without overwriting Filbert choices
- **Given** preferences exist under the previous bundle identifier
- **When** Filbert starts for the first time
- **Then** it copies only the known provider order, provider overrides, balance thresholds, collapse state, and icon preference keys
- **And** an existing Filbert value wins over a previous value
- **And** the migration is idempotent
- **And** the previous preference domain is removed only after every eligible value is verified in the Filbert domain

### [x] AC6: Migrate the Claude helper automatically
- **Given** the previous Claude helper is executable or Claude settings contain its sole-helper command or chain markers
- **When** Filbert runs its first-launch migration
- **Then** it treats the helper and settings artifacts as the installation signal without requiring the previous app bundle to remain in `/Applications`
- **And** it compiles the bundled Filbert helper without blocking app launch
- **And** it preserves any user-owned status-line command while replacing the previous sole-helper command or wrapper with Filbert paths and markers
- **And** it carries forward a valid cache when the Filbert cache does not already exist
- **And** it verifies that the Filbert helper is executable and Claude settings reference the expected command before removing the previous helper and cache
- **And** the migration is idempotent and does not alter a fresh Filbert installation
- **And** a failed or unavailable compilation leaves the previous helper, settings, and cache intact, permits the previous cache as a temporary fallback, and exposes a non-blocking retry action in Settings
- **Given** only the previous cache is present
- **When** first-launch migration runs
- **Then** it carries forward the valid cache without compiling a helper or changing Claude settings

### [x] AC7: Isolate temporary compatibility references
- **Given** the rename implementation is complete
- **When** the repository is searched case-insensitively for variants of the previous project name
- **Then** matches required for migration exist only in a clearly named legacy-brand migration boundary, its focused tests, and transition documentation
- **And** all normal production paths, tests, historical specs, comments, build metadata, and user documentation use Filbert
- **And** the compatibility boundary identifies the retirement requirement in (branding 02)

### [x] AC8: Keep repository handoff external
- **Given** the local project has been renamed
- **When** repository metadata is reviewed
- **Then** README clone and release links target `victorhqc/filbert`
- **And** the local workspace directory and Git remote are not mutated by the implementation
- **And** the handoff lists the commands or repository-host steps the user must perform after renaming the repository

### [x] AC9: Verify the renamed project
- **Given** all rename and migration changes are applied
- **When** validation runs
- **Then** the full Swift test suite passes
- **And** a release build completes
- **And** packaging verification finds the Filbert executable, resource bundles, icon, bundle identifier, and artifact names
- **And** focused tests cover successful, repeated, partial, and failed migrations without using the real user Keychain, preferences, Claude settings, or home-directory files

## Plan
Use Filbert for every canonical identifier in one implementation pass. Keep the old-name literals behind small migration collaborators rather than spreading fallback checks through normal storage and provider logic. Invoke preference migration before preference-backed UI state is read. Extend the existing Keychain consolidation path to migrate the previous service transactionally. Start Claude migration asynchronously on first launch, detect the previous integration from its actual filesystem and settings artifacts, stage the Filbert helper and settings changes, and remove previous artifacts only after verification. Retain a previous-cache fallback and Settings retry action for recoverable failures. Update docs and historical specs semantically rather than applying a blind replacement. Finish with targeted searches for spelling, case, separator, bundle-ID, artifact, and filename variants.

## Risks
- Changing the bundle identifier makes macOS treat Filbert as a distinct application; the previous app bundle can remain installed beside it.
- Keychain migration may prompt under unsigned or differently signed builds and must never delete the only valid copy.
- Both app versions running at once could compete over Claude settings or cache files.
- Users whose automatic Claude migration repeatedly fails must resolve the reported Settings error before the fallback is removed in (branding 02).
- Compiling the helper during first launch may fail when `swiftc` is unavailable, so the task must remain asynchronous and recoverable.
- Historical specs must retain accurate provider terminology while changing only references that identify the project.

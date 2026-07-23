## Objective
Remove the temporary legacy-brand migration bridge after users have had a defined opportunity to move to Filbert.

## Context
- The rename ships the compatibility bridge and isolates every previous-name reference (branding 01).
- `Sources/Core` — contains temporary Keychain and preference migration support.
- `Sources/Providers/ClaudeCode` — contains temporary cache fallback and helper-chain recognition.
- `Tests` — proves the transitional behavior and will be reduced to Filbert-only behavior.
- Transition documentation must warn users before compatibility is removed.

## Acceptance Criteria

### AC1: Enforce a migration window
- **Given** the first Filbert release includes the migration bridge
- **When** retirement is scheduled
- **Then** at least two consecutive tagged Filbert releases have shipped with the bridge
- **And** their release notes state that users should launch Filbert and resolve any reported automatic-migration failure before the compatibility cutoff
- **And** the cutoff release notes state that users skipping the transition releases must configure Filbert as a fresh install

### AC2: Remove compatibility code
- **Given** the migration window has elapsed
- **When** the retirement change is applied
- **Then** previous-service Keychain reads, previous-domain preference reads, previous-cache fallback, previous-helper recognition, and their migration-only tests are removed
- **And** Filbert’s normal storage, refresh, install, and uninstall behavior is unchanged

### AC3: Remove previous-name references
- **Given** compatibility code has been removed
- **When** tracked files and filenames are searched case-insensitively for spelling, case, separator, bundle-ID, marker, and artifact variants of the previous project name
- **Then** no project-related matches remain in the working tree
- **And** legitimate provider usage terminology remains unchanged

### AC4: Verify the clean architecture
- **Given** only Filbert identifiers remain
- **When** validation runs
- **Then** the full Swift test suite passes
- **And** a release build and packaging verification pass
- **And** fresh-install tests cover Keychain, preferences, and Claude helper behavior without a migration dependency

## Plan
Schedule this work only after the release condition in AC1 is documented and met. Delete the isolated migration collaborators and fallback branches, simplify their callers, remove transition-only fixtures, and update the rename spec to describe the previous brand generically so its literal spelling does not survive the cleanup. Run the same exhaustive search and packaging checks used for (branding 01).

## Risks
- A user who upgrades directly from a pre-Filbert build after the cutoff will need to re-enter provider keys and reinstall the Claude helper.
- Removing the bridge too early would turn a cosmetic rename into silent configuration loss.
- Search-based cleanup must distinguish project branding from legitimate references to AI usage as a general concept.

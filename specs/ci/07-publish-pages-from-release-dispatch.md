# Publish Pages from a release-triggered dispatch

## Objective
Publish the release site and appcast through a dispatched Pages run, so GitHub never drops the deployment when the tag's commit was already deployed from `main`.

## Context
- `.github/workflows/release.yml` — its `publish-pages` job calls `pages.yml` through `workflow_call`, which inherits the `release` event.
- `.github/workflows/pages.yml` — the only Pages deployer. `actions/deploy-pages` sets `pages_build_version` from `GITHUB_SHA`, so a release deploy reuses the push deploy's version and is discarded.
- `scripts/test-automatic-updates.py` — asserts the current release wiring; it must assert the dispatch instead.
- `docs/automatic-updates.md` — describes the release flow; step 9 must describe the dispatch.
- Builds on (site 01) and (ci 05). Supersedes the `workflow_call` trigger described in (site 01).

## Acceptance Criteria

### AC1: Release dispatches the Pages workflow
- **Given** a published stable release whose build and appcast upload succeed
- **When** the release workflow reaches the publishing job
- **Then** it dispatches `pages.yml` on the default branch with the release tag as an input

### AC2: The release workflow never deploys Pages itself
- **Given** the release workflow
- **When** it is inspected
- **Then** it contains no `deploy-pages` step and no `workflow_call` to `pages.yml`

### AC3: A failed build skips the dispatch
- **Given** the DMG build or the appcast upload fails
- **When** the release workflow ends
- **Then** the publishing job does not run and no Pages dispatch happens

### AC4: A rejected dispatch fails the job
- **Given** `gh workflow run` exits non-zero, for example from a missing permission
- **When** the publishing job runs
- **Then** the job fails instead of reporting success

### AC5: The wiring is tested
- **Given** `scripts/test-automatic-updates.py`
- **When** it runs
- **Then** it asserts the dispatch command, the tag input, the `actions: write` permission, and the absence of the `deploy-pages` action outside `pages.yml`

## Plan
Replace the `uses:` job in `release.yml` with a job on `ubuntu-latest` that runs:

```sh
gh workflow run pages.yml --repo "$GITHUB_REPOSITORY" --ref "$DEFAULT_BRANCH" -f tag="$TAG_NAME"
```

The job keeps `needs: release` and the success condition, and asks for `actions: write` plus `contents: read`. Remove the now-unused `workflow_call` trigger from `pages.yml`. Update the test and the release-flow docs.

## Risks
- The release job does not wait for the dispatched run. A failed Pages run shows as a red run in the Actions tab, not as a failed release.
- A dispatch runs the `pages.yml` from the default branch, not from the tag.
- Removing `workflow_call` breaks any external caller that still uses it.

## Findings
- v0.21.0 exposed the bug: the release deploy reported success at 13:00 UTC, but Pages kept serving the 12:51 artifact. A `workflow_dispatch` for the same tag published correctly.
- `scripts/test-local-signing.py` fails on
  `test_native_foundation_argument_bridge_preserves_temporary_persistent_domain`
  (`Foundation home is not isolated`) in this environment. The failure also
  reproduces on a clean checkout and is recorded in (providers 14).

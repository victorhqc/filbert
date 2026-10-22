# Homebrew tap cask

## Objective
Publish a `filbert` cask in a project-owned Homebrew tap, updated by each stable release, so users can run `brew install --cask victorhqc/tap/filbert`.

## Context
- `.github/workflows/release.yml` — gains a job that renders the cask from the published DMG and pushes it to the tap after the release job succeeds.
- `packaging/homebrew/filbert.rb` — new cask template with `@VERSION@` and `@SHA256@` placeholders, matching the `packaging/Info.plist` convention. The cask is reviewed here, in the app repository. The tap repository only receives rendered output.
- `scripts/render-homebrew-cask.py` — new renderer. Fills the placeholders, validates them, and decides whether the tap must change.
- `scripts/test-homebrew-cask.py` — new tests for the renderer and the workflow wiring. `.github/workflows/ci.yml` runs them next to `scripts/test-automatic-updates.py`.
- `docs/homebrew-tap.md` — new maintainer guide: create the tap, the deploy key, the environment, and the first cask.
- `README.md` and `site/index.html` — document the Homebrew install.
- `victorhqc/homebrew-tap` — new public repository, created by the maintainer. Homebrew maps `victorhqc/tap` to `github.com/victorhqc/homebrew-tap`.
- Sparkle stays the updater (updates 01, updates 04). The cask declares `auto_updates true`, so `brew upgrade` skips Filbert unless the user passes `--greedy`.
- Builds on the release pipeline from (ci 05) and runs beside the Pages dispatch from (ci 07).
- The official `homebrew/cask` repository is out of scope. A submission by the author needs 90 forks, 90 watchers, or 225 stars. The repository has 4 stars.

## Acceptance Criteria

`[~]` marks a plausible AC. The code is in place and is assumed to work, but no published release has proved it. Change it back to `[ ]` when someone reports a bug against it.

### [~] AC1: The cask installs the released DMG
- **Given** the rendered cask for version `X.Y.Z`
- **When** a user runs `brew install --cask victorhqc/tap/filbert`
- **Then** Homebrew downloads `https://github.com/victorhqc/filbert/releases/download/vX.Y.Z/Filbert-X.Y.Z-arm64.dmg`, verifies its SHA-256, and installs `Filbert.app` to `/Applications`

### [x] AC2: The cask hands updates to Sparkle
- **Given** the cask
- **When** it is inspected
- **Then** it declares `auto_updates true`
- **And** its `livecheck` reads `https://victorhqc.github.io/filbert/appcast.xml` with `strategy :sparkle`

### [x] AC3: The cask states the platform requirements
- **Given** the cask
- **When** a user installs it on an Intel Mac or on a macOS release older than the minimum
- **Then** Homebrew refuses before it downloads the DMG
- **And** the minimum is macOS 14 (`depends_on macos: :sonoma`), the `LSMinimumSystemVersion` of the binary

### [x] AC4: Zap removes only files Filbert owns
- **Given** an installed Filbert
- **When** a user runs `brew uninstall --zap --cask filbert`
- **Then** Homebrew removes the app, its preferences, caches, HTTP storage, `~/Library/Logs/Filbert`, and `~/.cache/filbert`
- **And** it does not touch `~/.claude/filbert-statusline` or `~/.claude/settings.json`

### [~] AC5: A stable release updates the tap
- **Given** a published stable release whose release job succeeds
- **When** the release workflow finishes
- **Then** `Casks/filbert.rb` in `victorhqc/homebrew-tap` names the new version and the SHA-256 of the DMG attached to the release
- **And** the tap commit message is `filbert X.Y.Z`

### [~] AC6: The hash comes from the published asset
- **Given** the release job has uploaded the DMG and its `.sha256` file
- **When** the cask job runs
- **Then** it downloads both assets from the release, hashes the downloaded DMG, and fails if the two values differ

### [x] AC7: The tap never moves backwards
- **Given** the tap already holds version `A`
- **When** the cask job runs for version `B`
- **Then** it pushes when `B` is newer than `A`
- **And** it pushes when `B` equals `A` and the hash differs, which covers a re-run that rebuilt the DMG
- **And** it pushes nothing, and succeeds, when `B` is older than `A` or the rendered file is unchanged

### [~] AC8: A broken cask is never pushed
- **Given** a rendered cask
- **When** `brew style` or `brew audit --cask --strict --online` reports a problem
- **Then** the job fails and the tap is not changed

### [~] AC9: A failed release skips the tap
- **Given** the DMG build, upload, or appcast step fails
- **When** the release workflow ends
- **Then** the cask job does not run

### [x] AC10: The tap credential is scoped to the tap
- **Given** the release workflow
- **When** it is inspected
- **Then** only the cask job can read `HOMEBREW_TAP_DEPLOY_KEY`, from a `homebrew-tap` environment
- **And** that job has no Apple or Sparkle secrets and only `contents: read` on this repository
- **And** the job fails before rendering when the key is missing

### [x] AC11: The renderer rejects bad input
- **Given** a version that is not plain `X.Y.Z`, a hash that is not 64 lowercase hex characters, or a template with a leftover placeholder
- **When** `scripts/render-homebrew-cask.py` runs
- **Then** it exits non-zero and writes no file

### [x] AC12: The wiring is tested
- **Given** `scripts/test-homebrew-cask.py`
- **When** CI runs it
- **Then** it covers AC7 and AC11 against the renderer
- **And** it asserts that the cask job needs the release job, uses the `homebrew-tap` environment, and downloads the assets from the release tag

### [x] AC13: Users and maintainers can find it
- **Given** the README, the landing page, and `docs/homebrew-tap.md`
- **When** they are read
- **Then** the README and landing page show `brew install --cask victorhqc/tap/filbert` and say that Filbert updates itself
- **And** the README explains `brew uninstall --zap --cask filbert`, and says that the Keychain items stay
- **And** the maintainer guide covers the tap repository, the deploy key, the environment, key rotation, and the first cask

## Plan
1. Add the cask template:

   ```ruby
   cask "filbert" do
     version "@VERSION@"
     sha256 "@SHA256@"
     url "https://github.com/victorhqc/filbert/releases/download/v#{version}/Filbert-#{version}-arm64.dmg"
     # name, desc, homepage, livecheck, auto_updates, depends_on, app, zap
   end
   ```

2. Add the Python renderer. It takes `--template`, `--version`, `--sha256`, `--existing`, and `--output`. It reads the version and hash from the existing cask, applies AC7, and prints `update` or `skip` for the workflow.
3. Add a `publish-homebrew-cask` job to `release.yml` with `needs: release`, the release success condition, `environment: homebrew-tap`, and `contents: read`. It runs on `macos-26` because Homebrew is preinstalled there. Steps:
   - download the DMG and `.sha256` with `gh release download`, then compare the hashes
   - write the deploy key to a temporary file, pin GitHub's SSH host key, and clone the tap into Homebrew's taps directory with `core.sshCommand` set
   - render the cask; stop when the renderer prints `skip`
   - run `brew style` and `brew audit --cask --strict --online victorhqc/tap/filbert`
   - commit as `github-actions[bot]` and push to the tap's default branch
4. Add the tests and the CI step.
5. Write `docs/homebrew-tap.md`. The maintainer creates the tap, adds the deploy key with write access, and stores the private key in the `homebrew-tap` environment. Then they push the first cask for the current release, which they render locally with the same script.
6. Update the README install section and the landing page.

A deploy key is used rather than a personal access token. GitHub limits it to one repository, and it does not expire.

## Decisions
- **Minimum macOS.** `README.md` says Filbert needs macOS 26. `packaging/Info.plist` and the appcast declare 14.0. `brew audit --strict` compares the cask's `depends_on macos:` with the app's declared minimum, so the cask declares `:sonoma` to match the binary. The user confirmed macOS 14 as the minimum on 2026-10-22, with macOS 26 as the best experience. The README and landing page say so.
- **Zap keeps the Claude Code helper.** The installer wraps the user's own `statusLine` command in `~/.claude/settings.json` and points it at `~/.claude/filbert-statusline`. Zap can only delete files. Deleting the helper would leave `settings.json` calling a missing file and break the user's original statusline. The in-app uninstall restores `settings.json` first, so it stays the only safe removal path. `~/.cache/filbert` holds only cached usage, and the helper recreates its directory, so zap removes it.

## Risks
- The cask job runs after the release is public. A failed job leaves the tap one version behind until someone re-runs it. Installs still work, and Sparkle updates them afterwards.
- `brew audit --online` depends on GitHub and Homebrew being reachable. A network failure fails the job. Re-running the job is safe because of AC7.
- A leaked deploy key lets someone push a malicious cask to the tap. The key is in its own environment, and only one job reads it. The DMG's Developer ID signature, notarization, and Sparkle signature are still checked separately.
- Sparkle updates the app in place, so Homebrew's recorded version gets out of date. `brew upgrade --greedy` then reinstalls a DMG that may be the same version. This is expected for `auto_updates` casks.
- `macos-26` minutes cost more than Ubuntu minutes. That costs nothing for a public repository.
- New Homebrew audit rules can fail a release-time job that passed before. The job fails before it pushes, so the tap stays valid.

## Findings
- Homebrew 7.0.9 `brew style` rejects `depends_on macos: ">= :sonoma"` (`Homebrew/OSDependsOn`). The cask uses `depends_on macos: :sonoma`.
- The cask rendered for v0.22.0 passed `brew style`, `brew audit --cask --strict --online`, and `brew livecheck` (`0.22.0 ==> 0.22.0`) in a temporary local tap on 2026-10-22.
- `HOMEBREW_NO_INSTALL_FROM_API=1` makes `brew audit` clone `homebrew/core` (1.5 GB). The workflow does not set it.
- AC1, AC5, AC6, AC8, and AC9 need a published release and are marked `[~]`.

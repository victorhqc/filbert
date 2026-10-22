# Homebrew tap

Filbert is published as a cask in the project-owned tap
[`victorhqc/homebrew-tap`](https://github.com/victorhqc/homebrew-tap). Users
install it with:

```sh
brew install --cask victorhqc/tap/filbert
```

The cask is reviewed in this repository, in `packaging/homebrew/filbert.rb`.
The tap repository only receives the rendered file. The official
`homebrew/cask` repository is out of scope until the project meets Homebrew's
notability rules: 90 forks, 90 watchers, or 225 stars when the author submits.

## How the cask works with Sparkle

The cask declares `auto_updates true`. Sparkle stays the only updater:

- `brew upgrade` skips Filbert. `brew upgrade --greedy` reinstalls the newest
  DMG.
- After Sparkle updates the app, Homebrew still records the version it
  installed. This is expected for every `auto_updates` cask.
- `livecheck` reads the same appcast as the app, so `brew livecheck` reports
  the version Sparkle offers.

`brew uninstall --zap --cask filbert` removes the app, its preferences, caches,
logs, and `~/.cache/filbert`. It keeps `~/.claude/filbert-statusline`.
Claude Code's `settings.json` wraps the user's own statusline around that
helper, and zap cannot edit JSON. Remove the helper from Filbert's settings
before uninstalling. Keychain items also stay.

## How a release updates the tap

The `publish-homebrew-cask` job in `.github/workflows/release.yml` runs after
the `release` job succeeds:

1. It downloads the DMG and its `.sha256` file from the GitHub Release and
   fails when the downloaded DMG does not match the published hash.
2. It clones the tap with the deploy key. GitHub's SSH host key is pinned in
   the workflow.
3. `scripts/render-homebrew-cask.py` fills the version and hash into the
   template. It prints `skip`, and the job stops, when the tap already holds a
   newer version or the same file.
4. `brew style` and `brew audit --cask --strict --online` must pass.
5. It commits `filbert <version>` and pushes to the tap's default branch.

The job is safe to re-run. It never moves the tap to an older version.

## One-time setup

### Create the tap repository

The repository must be public and must have a first commit, so the job can
push to its default branch:

```sh
gh repo create victorhqc/homebrew-tap --public --add-readme \
  --description "Homebrew tap for Filbert"
```

### Create the deploy key

A deploy key has write access to one repository only and does not expire. Run
the commands in a subshell so the private key never stays on disk:

```sh
(
  set -euo pipefail
  KEY_DIRECTORY="$(mktemp -d -t filbert-tap-key)"
  trap 'rm -rf "$KEY_DIRECTORY"' EXIT

  ssh-keygen -t ed25519 -N "" -C "filbert release workflow" \
    -f "$KEY_DIRECTORY/deploy_key"
  gh repo deploy-key add "$KEY_DIRECTORY/deploy_key.pub" \
    --repo victorhqc/homebrew-tap \
    --allow-write \
    --title "filbert release workflow"
  gh api --method PUT repos/victorhqc/filbert/environments/homebrew-tap
  gh secret set HOMEBREW_TAP_DEPLOY_KEY \
    --repo victorhqc/filbert \
    --env homebrew-tap < "$KEY_DIRECTORY/deploy_key"
)
```

The key must have no passphrase. The runner cannot answer a prompt.

### Protect the environment

1. Open **Settings → Environments → homebrew-tap** in `victorhqc/filbert`.
2. Under "Deployment branches and tags", choose **Selected branches and
   tags**, add a tag rule for `v*`, and save it.

Only `publish-homebrew-cask` uses this environment. It holds no Apple or
Sparkle secrets, and the jobs that hold them cannot read the deploy key.

### Publish the first cask

The job runs on the next release. To publish the current release now, render
the cask locally and push it to the tap:

```sh
(
  set -euo pipefail
  VERSION=0.22.0
  WORK="$(mktemp -d -t filbert-tap)"
  trap 'rm -rf "$WORK"' EXIT

  gh release download "v$VERSION" --repo victorhqc/filbert --dir "$WORK" \
    --pattern "Filbert-$VERSION-arm64.dmg.sha256"
  SHA256=$(awk '{ print $1 }' "$WORK/Filbert-$VERSION-arm64.dmg.sha256")

  gh repo clone victorhqc/homebrew-tap "$WORK/tap"
  python3 scripts/render-homebrew-cask.py \
    --template packaging/homebrew/filbert.rb \
    --version "$VERSION" \
    --sha256 "$SHA256" \
    --existing "$WORK/tap/Casks/filbert.rb" \
    --output "$WORK/tap/Casks/filbert.rb"

  git -C "$WORK/tap" add Casks/filbert.rb
  git -C "$WORK/tap" commit -m "filbert $VERSION"
  git -C "$WORK/tap" push
)
```

Run it from the root of this repository. Then check the install:

```sh
brew install --cask victorhqc/tap/filbert
brew livecheck --cask victorhqc/tap/filbert
```

## Changing the cask

Edit `packaging/homebrew/filbert.rb` and run
`python3 scripts/test-homebrew-cask.py`. To lint a change before a release,
render it to a temporary file and run `brew style` on that file.
`brew style` turns on Homebrew's developer mode. Run `brew developer off`
afterwards if you do not want it.

A template change reaches the tap with the next release. For an earlier
update, publish the cask by hand as described above.

## Recovery

| Symptom | Cause | Fix |
|---------|-------|-----|
| `HOMEBREW_TAP_DEPLOY_KEY is missing from homebrew-tap` | The environment or the secret is absent | Repeat "Create the deploy key", then re-run the job |
| `Permission denied (publickey)` in "Clone the tap" or "Push the cask" | The deploy key was removed, rotated, or added without write access | Repeat "Create the deploy key" |
| `Released DMG does not match its .sha256 asset` | A release asset was replaced or corrupted | Re-run the release workflow so it uploads a matching pair |
| `brew audit` fails | A cask error or a new Homebrew rule | Fix the template, then re-run the job. The tap is unchanged |
| The tap is one version behind | The job failed after the release was published | Re-run the job. Installs still work, and Sparkle updates them |

## Key rotation

Run "Create the deploy key" again. It adds a new key and replaces the secret.
Then delete the old key under **Settings → Deploy keys** in
`victorhqc/homebrew-tap`. Rotate at once if the key may have leaked: a leaked
key can push a malicious cask to the tap.

# Signing and notarization guide

How Filbert releases get Developer ID-signed, Apple-notarized, and stapled —
and how to create, store, rotate, and revoke the credentials that make that
possible. Written for a maintainer who has an active Apple Developer Program
membership and no signing experience.

What the pipeline does, in order (implemented in `scripts/build-dmg.sh`):

1. Import the `.p12` certificate into a temporary, randomly passworded
   keychain on the ephemeral build runner.
2. Sign `Filbert.app` with the **Developer ID Application** identity,
   hardened runtime, `packaging/Filbert.entitlements`, and a trusted
   timestamp; verify the signature strictly and check its Team ID.
3. Wrap the app in a temporary ZIP, submit it to Apple's notary service, and
   require an **Accepted** result; staple the ticket to the app.
4. Build the DMG, notarize and staple it too, then verify the exact artifact
   that ships: `codesign --verify --deep --strict`, `spctl --assess`, and
   `stapler validate` on a copy of the app taken from the mounted DMG.

Only after every check passes does the release workflow upload the DMG, its
SHA-256 checksum, and the release notes to the GitHub Release.

## The credentials, at a glance

| # | Artifact | What it is | Example / format | Where it should live |
|---|----------|------------|------------------|----------------------|
| 1 | Certificate | The public Developer ID Application certificate issued by Apple | `Developer ID Application.cer` | Login keychain (your Mac) + inside the `.p12` |
| 2 | Private key | The secret half generated when you created the CSR; **cannot be recreated** | 2048-bit RSA key in your login keychain | Login keychain (your Mac) + inside the `.p12` |
| 3 | `.p12` archive | Certificate + private key bundled together, encrypted by the `.p12` password | `DeveloperIDApplication.p12` | Password manager / encrypted backup **only** — never in the repo |
| 4 | `.p12` password | Unlocks the `.p12` archive | a long unique password | Password manager (also GitHub secret `APPLE_DEVELOPER_ID_P12_PASSWORD`) |
| 5 | Team ID | Apple's 10-character identifier for your developer team | `ABCD123456` | Public-ish (printed on every signed app); GitHub secret `APPLE_DEVELOPER_ID_TEAM_ID` |
| 6 | Identity name | The full signing identity string | `Developer ID Application: Victor Quiroz Castro (ABCD123456)` | GitHub secret `APPLE_DEVELOPER_ID_NAME` |
| 7 | Apple Account email | The account that owns the membership | `you@example.com` | GitHub secret `APP_NOTARY_APPLE_ID` |
| 8 | App-specific password | Dedicated password for `notarytool` | `abcd-wxyz-1234-5678` | Password manager + GitHub secret `APP_NOTARY_APP_SPECIFIC_PASSWORD` |

Three things to internalize before you start:

- **Base64 is transport encoding, not encryption.** The GitHub secret
  `APPLE_DEVELOPER_ID_P12` holds the `.p12` re-encoded as base64 because
  GitHub secrets are text fields and a `.p12` is binary. Base64 hides nothing;
  the only thing protecting the key inside is the `.p12` password — so make
  that password strong.
- **You do not need a provisioning profile.** Profiles are for App Store /
  TestFlight and certain managed distributions. Direct Developer ID
  distribution of Filbert needs none, and the app's entitlements are empty.
- **You do not need a Developer ID Installer certificate.** That certificate
  type signs `.pkg` installers. Filbert ships as a DMG containing a signed
  `.app`, which requires only the one **Developer ID Application**
  certificate.

> **Never store your Apple Account's normal password in GitHub.** Not as a
> secret, not in a variable, not in a comment. The only Apple credential that
> belongs there is the *app-specific* password created in Part 2.

## Part 1 — Apple: create the Developer ID Application certificate

You create the certificate once. Renewal (same flow) is needed roughly every
five years — see [Expiration and rotation](#expiration-and-rotation).

### 1.1 Create a certificate signing request (CSR)

The private key is generated on your Mac as part of this step, so do it on
the Mac you keep the signing key on.

1. Open **Keychain Access** (Applications → Utilities).
2. Menu bar: **Keychain Access → Certificate Assistant → Request a
   Certificate from a Certificate Authority…**
3. In the dialog:
   - **User Email Address**: your Apple Account email (`you@example.com`).
     This is informational — it does not have to match anything.
   - **Common Name**: something you will recognize later, e.g.
     `Filbert Release`.
   - **CA Email Address**: leave it **empty**.
   - Select **Saved to disk** (not "Sent to CA").
4. Click **Continue**, save the file (e.g. `FilbertRelease.certSigningRequest`
   to your Desktop), then **Done**.

Nothing is sent to Apple yet. The request file is public; the private key it
references stays in your login keychain.

### 1.2 Issue the certificate on the Apple Developer portal

1. Go to <https://developer.apple.com/account> and sign in. Approve the
   two-factor prompt.
2. Open **Certificates, Identifiers & Profiles** (under "Program Resources").
3. Select **Certificates** in the sidebar, then click the **+** button.
4. Under "Software", choose **Developer ID Application** → **Continue**.
   (If the option is greyed out, you are not signed in with the Account
   Holder role, or the membership is inactive.)
5. When asked to upload a certificate signing request, upload the
   `.certSigningRequest` file from step 1.1 → **Continue**.
6. Click **Download** and save `developerIDapplication.cer`.

### 1.3 Install the certificate with its private key

1. On the **same Mac** where you created the CSR, double-click the downloaded
   `.cer` file. Keychain Access installs it into your **login** keychain and
   pairs it with the private key generated in step 1.1.
2. Verify in Keychain Access under **My Certificates**:
   `Developer ID Application: <your name or company> (<Team ID>)`. Clicking
   its disclosure triangle must reveal a private key underneath. If the
   triangle is missing, the CSR came from a different Mac or the key was
   deleted — redo Part 1 on the Mac that holds the key.

### 1.4 Find your Team ID and full signing identity

Run:

```sh
security find-identity -v -p codesigning
```

You should see one line like:

```
  1) ABCD123456 "Developer ID Application: Victor Quiroz Castro (ABCD123456)"
     1 valid identities found
```

- The **10-character code before the quote** is your Team ID → GitHub secret
  `APPLE_DEVELOPER_ID_TEAM_ID`.
- The **entire quoted string** is the identity name → GitHub secret
  `APPLE_DEVELOPER_ID_NAME`. Copy it exactly, including the
  `Developer ID Application:` prefix and the parenthesized Team ID.

(You can also read the Team ID on the portal: **Account → Membership** →
"Team ID".)

### 1.5 Export the password-protected `.p12`

1. In Keychain Access → **My Certificates**, click the
   `Developer ID Application: …` entry — clicking the certificate line
   selects it together with its private key.
2. **File → Export Items…**
3. Save as format **Personal Information Exchange (.p12)**, e.g.
   `DeveloperIDApplication.p12`.
4. Choose a **strong, unique password**. This is the `.p12` password →
   GitHub secret `APPLE_DEVELOPER_ID_P12_PASSWORD` (and your backup's
   password — see [Backup](#backup)).

This `.p12` is the crown jewel: it contains the private key that can sign
software as you. Store the copy on your Mac's keychain, one copy in a
password manager, and optionally one on encrypted external media. Never
commit it, never paste it into a chat, never email it.

## Part 2 — Apple: enable 2FA and create an app-specific password

Notarization submits builds to Apple under your Apple Account. Apple requires
two-factor authentication on that account and, instead of your real password,
you give `notarytool` a dedicated **app-specific password**.

1. Enable 2FA if it is off: <https://appleid.apple.com> → sign in →
   **Sign-In and Security → Two-Factor Authentication** → turn it on and
   follow the prompts.
2. Back on <https://appleid.apple.com> → **Sign-In and Security →
   App-Specific Passwords** → click **+** (or "Generate an app-specific
   password").
3. Give it a label you will recognize when auditing later, e.g.
   `filbert-notarytool`.
4. Apple shows a password in the form `abcd-wxyz-1234-5678`. **Copy it now** —
   it is not shown again. This is the value for the GitHub secret
   `APP_NOTARY_APP_SPECIFIC_PASSWORD`.

Two things Apple does that will bite you later if unnoticed:

- Changing or resetting your Apple Account password **revokes every
  app-specific password**. The next release will fail at the `notarytool`
  submit step until you generate a new one and update the secret.
- You can revoke an individual app-specific password at any time from the
  same screen (useful if you ever think it leaked).

## Part 3 — GitHub: create the `release-signing` Environment

The release workflow's `release` job declares
`environment: release-signing`. GitHub only injects an environment's secrets
into jobs that run in that environment, which keeps the signing credentials
scoped to the Release workflow alone. The environment must exist with the
exact name below, or every release build fails before doing anything.

1. Open the repository on GitHub → **Settings** → left sidebar **Environments**
   → **New environment**.
2. Name: `release-signing` → **Configure environment**.
3. (Recommended) Under "Deployment protection rules", either require a
   reviewer or restrict deployment branches/tags so only `v*` tags can use
   the credentials.
4. Under **Environment secrets** → **Add secret**, create all six:

| Secret name | Value |
|-------------|-------|
| `APPLE_DEVELOPER_ID_P12` | Base64 of your `.p12` — run `base64 -i DeveloperIDApplication.p12 \| pbcopy` on your Mac and paste the clipboard contents. Use the exact file, not a re-typed path, and avoid trailing newlines. |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | The `.p12` export password from Part 1.5 |
| `APPLE_DEVELOPER_ID_TEAM_ID` | Your 10-character Team ID from Part 1.4 |
| `APPLE_DEVELOPER_ID_NAME` | The full identity string from Part 1.4, e.g. `Developer ID Application: Victor Quiroz Castro (ABCD123456)` |
| `APP_NOTARY_APPLE_ID` | Your Apple Account email |
| `APP_NOTARY_APP_SPECIFIC_PASSWORD` | The app-specific password from Part 2 |

Keep the six names byte-for-byte identical — the workflow maps them to
environment variables of the same name, and `scripts/build-dmg.sh
--require-signing` fails closed listing anything missing or empty.

Limit who can administer the environment ("Environment permissions" on the
same page). Anyone who can edit the environment's secrets can extract the
private key.

### What the runner does with the secrets

For transparency, during a release build the runner: decodes the `.p12` into
a temporary directory, imports it into a fresh keychain with a random
one-shot password, signs, deletes the `.p12` file immediately, notarizes via
`notarytool` with the app-specific password, and deletes the keychain and the
notarization ZIP on exit — success or failure. Secret values are never
echoed, and the workflow never uploads anything except the DMG, its
`.sha256`, and the release notes.

## Sanity checks before the first release

Run these on your Mac; nothing secret is printed.

```sh
# The .p12 decodes and matches its password (replace the file path):
base64 --decode filbert-cert.b64 > /tmp/check.p12
openssl pkcs12 -info -in /tmp/check.p12 -noout -passin env:P12_PASSWORD
# (export P12_PASSWORD='…' first; the env var keeps it out of shell history)
rm /tmp/check.p12
```

And a dry check that the build script's fail-closed mode works as designed:

```sh
env -i PATH="$PATH" HOME="$HOME" scripts/build-dmg.sh --version 0.0.0-dryrun --require-signing
# Expected: immediate fatal error listing the missing secrets — no build runs.
```

## First release: end-to-end checklist

1. **Publish the release.** On GitHub → Releases → **Draft a new release** →
   choose a new tag `v<version>` → fill in notes → **Publish release**.
   Publishing (not tag pushing) triggers the **Release** workflow.
2. **Watch the run.** Actions tab → **Release** → the job should show:
   Developer ID signing → ZIP notarization accepted → staple → DMG
   notarization accepted → staple → artifact verification → upload.
3. **Check the release page.** `Filbert-<version>-arm64.dmg`,
   `Filbert-<version>-arm64.dmg.sha256`, and the generated notes (with the
   SHA-256) are attached.
4. **Fresh-download test on a Mac.** In a browser where you are *not* signed
   into GitHub (or in a private window), download the DMG from the release
   page, mount it, drag Filbert to `/Applications`, and double-click. It must
   launch normally — no right-click → Open dance, no `xattr`. The standard
   "downloaded from the internet" confirmation may still appear; confirming
   it is expected and is not a signing failure.
5. **Verify the displayed Developer ID** on the downloaded copy:

   ```sh
   codesign -dvv /Applications/Filbert.app
   # → Authority=Developer ID Application: … (your identity)
   # → TeamIdentifier=… (your team)

   spctl --assess --type execute -vv /Applications/Filbert.app
   # → accepted, source=Developer ID

   xcrun stapler validate /Applications/Filbert.app
   # → The validate action worked!
   ```

## Troubleshooting

Every failure below stops the job **before** anything is uploaded. After
fixing, re-run: Actions → the failed **Release** run → **Re-run all jobs**
(the upload step re-attaches assets with `--clobber`, so no stale DMG
lingers). The published release page simply shows no DMG until a run
succeeds.

| Symptom (log line) | Cause | Fix |
|--------------------|-------|-----|
| `Release signing is required but … secret(s) are missing or empty` in "Build signed and notarized DMG" | A secret from Part 3 is absent or blank, or the environment is named wrongly | Compare the listed names against the table in Part 3; fix spelling/emptiness; re-run |
| `Could not import APPLE_DEVELOPER_ID_P12` | The base64 doesn't decode to a valid `.p12`, or the `.p12` password secret doesn't match the export password | Re-run `base64 -i DeveloperIDApplication.p12 \| pbcopy` from the exact file, update the secret; re-check the password secret; verify locally with the openssl command under "Sanity checks" |
| `APPLE_DEVELOPER_ID_NAME does not match any imported identity` | The identity-name secret doesn't byte-match the certificate's identity | Copy the exact quoted string from `security find-identity -v -p codesigning` (Part 1.4) |
| `The imported certificate belongs to team …` | Team ID secret and certificate disagree | Fix `APPLE_DEVELOPER_ID_TEAM_ID` to the certificate's Team ID |
| `notarytool could not submit …` with credentials/Apple ID error in its output | Wrong `APP_NOTARY_APPLE_ID`, wrong/revoked app-specific password, or 2FA turned off | Regenerate the app-specific password (Part 2), update the secret, confirm 2FA is on. Remember: changing your Apple Account password revokes app-specific passwords |
| `Notarization did not reach Accepted …` followed by a JSON notary log | Apple rejected the build; the log's `issues` array names the exact file and rule | Read the log — common causes are bundle-structure damage or unsigned nested code introduced by packaging changes. Fix in `scripts/build-dmg.sh`, publish a new tag |
| `stapler could not staple …` / `stapler validation failed` | The ticket doesn't match the exact artifact (e.g. the file changed after notarization), or notarization never reached Accepted | Check the notary log printed above it; ensure nothing re-signs or modifies files between notarization and stapling |
| `spctl rejected the signed app` in "Verify the release artifact" | Signature is Developer ID but Gatekeeper assessment failed — typically wrong team, missing timestamp, or notarization not actually accepted | Read the `Authority=`/`TeamIdentifier=` lines the step prints; resolve against Parts 1–3 |

## Backup

- Keep the `.p12` **and its password** in a password manager, plus one
  offline copy (encrypted disk image) in case the manager is unavailable.
- The private key cannot be re-downloaded from Apple. If you lose every copy
  of the `.p12`, the certificate is unusable and must be revoked and replaced
  with a new CSR/cert (Part 1) — no data is lost, but every future release
  must use the new identity.
- Back up the six secret *names* (this page is the record) but never write
  their values into the repo.

## Expiration and rotation

- **Developer ID certificates are valid for five years.** Apple emails the
  Account Holder before expiry. Timestamped signatures keep validating after
  expiry, so already-shipped releases keep launching — but you cannot sign
  new releases with an expired certificate.
- **Renew before expiry:** repeat Part 1 (new CSR on your Mac → new
  certificate → export a fresh `.p12`). The identity string keeps the same
  Team ID, so `APPLE_DEVELOPER_ID_NAME` and `APPLE_DEVELOPER_ID_TEAM_ID`
  usually stay unchanged; update `APPLE_DEVELOPER_ID_P12` and
  `APPLE_DEVELOPER_ID_P12_PASSWORD`. Revoke the old certificate on the
  portal once nothing uses it.
- **Rotate the app-specific password** any time you are uneasy: generate a
  new one (Part 2), update `APP_NOTARY_APP_SPECIFIC_PASSWORD`, revoke the old
  one. Cost: none.
- **Rotate the `.p12` password** by re-exporting the certificate from
  Keychain Access with a new password and updating the two related secrets.

## If you suspect the private key leaked

Treat the key as compromised the moment it left your control (leaked CI log,
lost laptop with an unlocked keychain, shared `.p12` in a chat).

1. **Revoke the certificate immediately**:
   developer.apple.com → Account → Certificates → select the certificate →
   **Revoke**. New notarizations and signatures under it stop working at
   once; already-notarized, stapled releases keep launching for users.
2. Rotate the app-specific password (Part 2) — cheap insurance.
3. Review who can administer the `release-signing` environment and the
   repository (Settings → Environments / Collaborators) and remove anyone
   unexpected.
4. Create a fresh key pair and certificate via Part 1, export a new `.p12`
   with a **new password**, update the secrets from Part 3.
5. Publish a new patch release and confirm it passes the end-to-end
   checklist above.
6. If users could have downloaded a tampered build in the window, say so in
   the release notes of the new version.

## Official documentation

Steps above that Apple or GitHub may renumber are documented at:

- Apple — Developer ID overview and requirements:
  <https://developer.apple.com/support/developer-id/>
- Apple — notarizing macOS software:
  <https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
- Apple — two-factor authentication for your Apple Account:
  <https://support.apple.com/en-us/HT204397>
- Apple — app-specific passwords:
  <https://support.apple.com/en-us/HT204398>
- GitHub — using environments for deployment:
  <https://docs.github.com/en/actions/reference/environments>
- GitHub — using secrets in GitHub Actions:
  <https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions>

#!/usr/bin/env bash
# scripts/build-dmg.sh
#
# Builds Filbert.app and packages it into an arm64 DMG.
# Single entry point for local and CI builds.
#
# Requires: create-dmg (brew install create-dmg) for DMG packaging.
#
# Usage:
#   scripts/build-dmg.sh --version <semver> [--output <dir>] [--no-sign]
#                         [--require-signing]
#
# Lane selection:
#   --require-signing    signed lane is mandatory — any missing secret is a
#                        hard error before anything is built
#   six secrets present  Developer ID sign + notarize + staple
#   any secret missing   ad-hoc sign, skip notarization
#   --no-sign            forces the unsigned lane regardless of secrets
#
# Never echo secret values. Credentials are read from the environment at the
# point of use and never logged.

set -euo pipefail

APP_NAME="Filbert"
APP_BUNDLE_ID="com.victorhqc.filbert"
ARCH="arm64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/$ARCH-apple-macosx/release"
ENTITLEMENTS="$REPO_ROOT/packaging/Filbert.entitlements"
INFO_PLIST_TEMPLATE="$REPO_ROOT/packaging/Info.plist"

# Minimum macOS SDK the app must be built against. SwiftUI/AppKit gate their
# rendering on the SDK an app links against ("linked on or after"). Below
# macOS 26 they serve the pre-Tahoe codepath at runtime — wrong popover
# vibrancy material and a MenuBarExtra(.window) that won't resize to fit
# content. The build runner's image dictates the SDK (macos-14 → SDK 14.x);
# assert_build_sdk fails the build loudly rather than shipping the old look.
MIN_SDK_MAJOR=26

# Secrets required for the signed lane.
SIGN_SECRET_NAMES=(
    APPLE_DEVELOPER_ID_P12
    APPLE_DEVELOPER_ID_P12_PASSWORD
    APPLE_DEVELOPER_ID_TEAM_ID
    APPLE_DEVELOPER_ID_NAME
    APP_NOTARY_APPLE_ID
    APP_NOTARY_APP_SPECIFIC_PASSWORD
)

VERSION=""
OUTPUT_DIR="$REPO_ROOT/dist"
FORCE_NO_SIGN=false
REQUIRE_SIGNING=false

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*" >&2; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 --version <semver> [--output <dir>] [--no-sign] [--require-signing]

Options:
  --version <semver>   Version string baked into Info.plist and DMG name.
  --output <dir>       Destination directory for the DMG (default: ./dist).
  --no-sign            Force the unsigned lane even when all
                       signing secrets are present. Useful for local test
                       builds.
  --require-signing    Fail unless all six signing secrets are present; the
                       release workflow uses this so a public release can
                       never fall back to ad-hoc signing. Mutually
                       exclusive with --no-sign.
  -h, --help           Show this help.

Signing secrets (all six required for the signed lane):
$(printf '  %s\n' "${SIGN_SECRET_NAMES[@]}")
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version)
                [[ $# -ge 2 ]] || fatal "--version requires a value"
                VERSION="$2"; shift 2 ;;
            --output)
                [[ $# -ge 2 ]] || fatal "--output requires a value"
                OUTPUT_DIR="$2"; shift 2 ;;
            --no-sign)
                FORCE_NO_SIGN=true; shift ;;
            --require-signing)
                REQUIRE_SIGNING=true; shift ;;
            -h|--help)
                usage; exit 0 ;;
            *)
                fatal "Unknown argument: $1 (see --help)" ;;
        esac
    done

    [[ "$FORCE_NO_SIGN" != "true" || "$REQUIRE_SIGNING" != "true" ]] \
        || fatal "--no-sign and --require-signing are mutually exclusive"
    [[ -n "$VERSION" ]] || fatal "--version is required (e.g. 0.1.0)"
    [[ -f "$INFO_PLIST_TEMPLATE" ]] || fatal "Missing Info.plist template: $INFO_PLIST_TEMPLATE"
    [[ -f "$ENTITLEMENTS" ]] || fatal "Missing entitlements: $ENTITLEMENTS"
}

# The probe is a single check, not duplicated per step. With
# --require-signing, a missing secret is fatal so the public release workflow
# cannot drift into the ad-hoc lane.
detect_lane() {
    if [[ "$FORCE_NO_SIGN" == "true" ]]; then
        echo "unsigned"
        return
    fi
    local missing=()
    for name in "${SIGN_SECRET_NAMES[@]}"; do
        local value="${!name:-}"
        [[ -n "$value" ]] || missing+=("$name")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        echo "signed"
    elif [[ "$REQUIRE_SIGNING" == "true" ]]; then
        fatal "Release signing is required but ${#missing[@]} secret(s) are missing or empty: ${missing[*]}. Configure the release-signing GitHub Environment — see docs/signing-and-notarization.md."
    else
        warn "Signing lane disabled — missing: ${missing[*]}"
        warn "Falling through to the unsigned lane."
        echo "unsigned"
    fi
}

build_release() {
    info "Building $APP_NAME release ($ARCH)…"
    (
        cd "$REPO_ROOT"
        swift build -c release --arch arm64
    )
    [[ -x "$BUILD_DIR/App" ]] || fatal "Build produced no executable at $BUILD_DIR/App"
    ok "Release build complete"

    # SPM's generated Bundle.module accessor looks up resources at
    # Bundle.main.bundleURL (the .app top level). assemble_bundle places
    # the bundles at Contents/Resources/ instead, because that is the
    # only layout macOS code sealing accepts. Patch the accessor and
    # relink so Bundle.module resolves against Contents/Resources/ at runtime.
    patch_resource_bundle_accessors

    # Fail loudly if the build linked against too old an SDK (e.g. a stale
    # CI runner image). Runs after the relink so it checks the exact binary
    # that ships.
    assert_build_sdk "$BUILD_DIR/App"
}

# Reads the SDK version stamped into the executable's LC_BUILD_VERSION and
# fails the build if it predates MIN_SDK_MAJOR. This is the version SwiftUI
# and AppKit read at runtime to pick a rendering codepath; a too-old value
# ships the pre-Tahoe look and the non-resizing MenuBarExtra popover even
# when the app later runs on macOS 26. The runner image, not this script,
# controls the SDK — this only refuses to package a bad one.
assert_build_sdk() {
    local exe="$1"
    local sdk major
    sdk=$(otool -l "$exe" | awk '/LC_BUILD_VERSION/{f=1} f&&$1=="sdk"{print $2; exit}')
    [[ -n "$sdk" ]] || fatal "Could not read LC_BUILD_VERSION sdk from $exe"
    major="${sdk%%.*}"
    if (( major < MIN_SDK_MAJOR )); then
        fatal "Built against macOS SDK $sdk, need >= ${MIN_SDK_MAJOR}.0. The \
build runner's SDK is too old — SwiftUI would ship its pre-Tahoe codepath \
(wrong popover material, MenuBarExtra that won't resize). Use a macOS 26 / \
Xcode 26 runner."
    fi
    ok "Built against macOS SDK $sdk"
}

# Rewrites SPM's generated resource_bundle_accessor.swift so Bundle.module
# resolves resource bundles from the host .app's Contents/Resources/, where
# assemble_bundle places them and macOS code sealing allows them to live.
#
# SPM's template (Swift 5.3+) generates:
#   let mainPath = Bundle.main.bundleURL
#       .appendingPathComponent("<module>.bundle").path
# which looks at the .app top level — not Contents/Resources/. macOS code
# sealing rejects bundles at the .app root ("unsealed contents"), so we
# cannot place them there. Instead we keep the signable layout and teach
# the accessor to look in the right place via Bundle.main.resourceURL
# (which points at Contents/Resources/ in a packaged .app). The
# `?? Bundle.main.bundleURL` fallback preserves dev-tree lookup when
# resourceURL is nil (e.g. running tests against the test runner bundle).
#
# CRUCIAL: SPM regenerates this accessor from its template during the
# "Write sources" plan phase of EVERY `swift build`. A plain patch + a
# second `swift build` therefore reverts the patch before swiftc reads it.
# Blocking the regeneration (making the file immutable/read-only) is not
# portable — it makes llbuild's "Write sources" fail on some runners.
# Instead we let the first build regenerate freely, patch the accessors,
# and then REPLAY the exact swiftc compile + link commands SPM recorded in
# its llbuild manifest (.build/release.yaml), bypassing `swift build`
# entirely. Those commands read the patched accessor and never regenerate
# it, so the patch lands in the linked executable deterministically.
#
# Every accessor under .build/<arch>-apple-macosx/release/ is patched, the
# executable is relinked against the patched accessors, and no original-form
# line survives. If a future Swift changes the template, the post-relink
# assertion fails loudly rather than shipping a broken app.
patch_resource_bundle_accessors() {
    local release_tree="$REPO_ROOT/.build/$ARCH-apple-macosx/release"
    local manifest="$REPO_ROOT/.build/release.yaml"
    local app_link_file_list="$release_tree/App.product/Objects.LinkFileList"
    local original='Bundle\.main\.bundleURL\.appendingPathComponent'
    local patched='(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent'

    [[ -f "$manifest" ]] \
        || fatal "Missing llbuild manifest at $manifest — cannot replay relink"
    [[ -f "$app_link_file_list" ]] \
        || fatal "Missing App link file list at $app_link_file_list"
    command -v python3 >/dev/null \
        || fatal "python3 is required to replay the SPM build commands"

    local accessors=()
    local modules=()
    while IFS= read -r accessor; do
        local mod="${accessor#"$release_tree"/}"
        mod="${mod%%.build/*}"
        local object="$release_tree/$mod.build/resource_bundle_accessor.swift.o"
        grep -Fqx -- "$object" "$app_link_file_list" || continue
        accessors+=("$accessor")
        modules+=("$mod")
    done < <(find "$release_tree" \
        -path '*/DerivedSources/resource_bundle_accessor.swift' \
        -type f)
    [[ ${#accessors[@]} -gt 0 ]] \
        || fatal "No resource_bundle_accessor.swift under $release_tree"

    info "Patching ${#accessors[@]} resource_bundle_accessor.swift file(s)…"
    for accessor in "${accessors[@]}"; do
        sed -i '' "s|$original|$patched|g" "$accessor"
    done

    # Replay SPM's recorded compile + link commands so the patch is compiled
    # in without a `swift build` regenerating the accessor (see block comment).
    info "Recompiling ${#modules[@]} module(s) and relinking against patched accessors…"
    replay_release_relink "$manifest" "$BUILD_DIR/App" "${modules[@]}"

    [[ -x "$BUILD_DIR/App" ]] \
        || fatal "Relink produced no executable at $BUILD_DIR/App"

    # Assert the patch is in the on-disk accessors (they are not regenerated
    # by the replay, so the patched form must survive). If a future SPM
    # template no longer matches the sed anchor, the original form persists
    # and we fail loudly rather than shipping a broken app.
    local unpatched=()
    for accessor in "${accessors[@]}"; do
        grep -q "$original" "$accessor" && unpatched+=("$accessor")
    done
    [[ ${#unpatched[@]} -eq 0 ]] \
        || fatal "Unpatched resource_bundle_accessor.swift after patch (SPM template drift?): ${unpatched[*]}"

    ok "Patched and relinked ${#accessors[@]} resource_bundle_accessor.swift file(s)"
}

# Replays the swiftc compile commands for the given modules and the App link
# command, exactly as SPM recorded them in the llbuild manifest. Args:
#   $1  path to .build/release.yaml
#   $2  path to the expected linked executable (BUILD_DIR/App)
#   $3… module names to recompile
# swiftc is invoked with SPM's own flags (which include -parseable-output);
# its noisy JSON stdout is suppressed unless a command fails.
replay_release_relink() {
    local manifest="$1" exe_path="$2"
    shift 2
    local modules=("$@")

    MANIFEST="$manifest" EXE_PATH="$exe_path" MODULES="${modules[*]}" \
        python3 <<'PY' || fatal "Replay of SPM compile/link commands failed"
import json, os, re, subprocess, sys

manifest = os.environ["MANIFEST"]
exe_path = os.environ["EXE_PATH"]
wanted = set(os.environ["MODULES"].split())

compiles = {}
link = None
for line in open(manifest):
    m = re.match(r'\s*args:\s*(\[.*\])\s*$', line)
    if not m:
        continue
    args = json.loads(m.group(1))
    if "-emit-executable" in args and "-o" in args \
            and args[args.index("-o") + 1] == exe_path:
        link = args
    elif "-emit-module" in args and "-module-name" in args:
        name = args[args.index("-module-name") + 1]
        if name in wanted:
            compiles[name] = args

missing = wanted - set(compiles)
if missing:
    sys.exit(f"no compile command in manifest for module(s): {sorted(missing)}")
if link is None:
    sys.exit(f"no link command in manifest for executable: {exe_path}")

# Stamp the correct SDK version into the relinked binary's LC_BUILD_VERSION.
# The recorded swiftc link command carries -sdk, but ld reads the SDK version
# for LC_BUILD_VERSION from the SDKROOT environment variable, which `swift
# build` sets and this bare replay does not. Without it ld falls back to
# stamping sdk = the deployment target (14.0) instead of the real SDK (e.g.
# 26.5). A binary that claims it was built against the macOS 14 SDK makes
# SwiftUI/AppKit serve their old-SDK codepath at runtime — wrong popover
# vibrancy material and a MenuBarExtra(.window) that won't resize to fit
# content. Mirror `swift build` by exporting the exact -sdk path the manifest
# recorded, so the stamp matches a normal link byte-for-byte.
if "-sdk" in link:
    os.environ["SDKROOT"] = link[link.index("-sdk") + 1]

def run(label, args):
    p = subprocess.run(args, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, text=True)
    if p.returncode != 0:
        sys.stdout.write(p.stdout)
        sys.exit(f"{label} failed (exit {p.returncode})")

# Recompile every patched module (order is irrelevant — the patch is internal
# and does not change any module's public interface), then relink.
for name in sorted(compiles):
    run(f"compile {name}", compiles[name])
run("link App", link)
PY
}

# Assembles Filbert.app into the passed staging dir and echoes its path.
# Layout:
#   Filbert.app/
#     Contents/
#       Info.plist                            (generated from template)
#       MacOS/Filbert                        (renamed release executable)
#       Resources/                            (SPM resource bundles + icon)
#         filbert_App.bundle/                (Bundle.module lookup target)
#         filbert_ClaudeCodeProvider.bundle/
#         filbert_Core.bundle/
#         filbert_DeepSeekProvider.bundle/
#         filbert_ZAIProvider.bundle/
#         AppIcon.icns                        (for Finder/Dock pre-launch)
#
assemble_bundle() {
    local stage_dir="$1"
    local app_dir="$stage_dir/$APP_NAME.app"

    mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

    # Rename the executable to the display name. CFBundleExecutable matches.
    cp "$BUILD_DIR/App" "$app_dir/Contents/MacOS/$APP_NAME"
    chmod +x "$app_dir/Contents/MacOS/$APP_NAME"

    # SPM resource bundles live at Contents/Resources/ because that is the
    # only layout macOS code sealing accepts. Bundle.module does NOT
    # natively resolve against Contents/Resources/ — SPM's generated
    # accessor looks at Bundle.main.bundleURL (the .app top level).
    # patch_resource_bundle_accessors (called from build_release) rewrites
    # the accessor to look here via Bundle.main.resourceURL.
    # If either piece is missing, statusline_helper.swift
    # and AppIcon/Localizable lookups fail at runtime.
    local bundle_count=0
    while IFS= read -r bundle; do
        cp -R "$bundle" "$app_dir/Contents/Resources/"
        bundle_count=$((bundle_count + 1))
    done < <(find "$BUILD_DIR" -maxdepth 1 -name 'filbert_*.bundle' -type d)
    [[ $bundle_count -gt 0 ]] || fatal "No SPM resource bundles found in $BUILD_DIR"
    ok "Copied $bundle_count resource bundle(s)"

    # App icon at the bundle top level so Finder/Dock show it before launch.
    # The app also sets it at runtime via Bundle.module (AppMain.swift).
    cp "$REPO_ROOT/Sources/App/Resources/AppIcon.icns" "$app_dir/Contents/Resources/"

    # Info.plist from template. @VERSION@ is the only substitution.
    sed "s/@VERSION@/$VERSION/g" "$INFO_PLIST_TEMPLATE" > "$app_dir/Contents/Info.plist"

    ok "Bundle assembled at $app_dir"
    echo "$app_dir"
}

sign_adhoc() {
    # Ad-hoc signing lets the bundle run on the maintainer's machine without
    # re-signing. --options runtime keeps this command symmetric with the
    # Developer ID lane.
    local app_dir="$1"
    info "Ad-hoc signing…"
    codesign -s - --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "$app_dir"
    ok "Ad-hoc signed"
}

# Fresh keychain for the signing certificate. Cleaned up on exit.
SIGN_KEYCHAIN_DIR=""
SIGN_KEYCHAIN=""
SIGN_IDENTITY=""
NOTARY_WORK_DIR=""
# Held while the release DMG is mounted for verification; the exit trap
# detaches it if the script dies mid-verification.
VERIFY_MOUNT_POINT=""

import_signing_certificate() {
    # All six secrets are present (detect_lane already verified). Import the
    # p12 into a temporary keychain that is deleted on script exit.
    SIGN_KEYCHAIN_DIR="$(mktemp -d)"
    SIGN_KEYCHAIN="$SIGN_KEYCHAIN_DIR/signing.keychain-db"
    local keychain_password
    keychain_password="$(uuidgen)"

    security create-keychain -p "$keychain_password" "$SIGN_KEYCHAIN" >/dev/null
    security set-keychain-settings -lut 21600 "$SIGN_KEYCHAIN"
    security unlock-keychain -p "$keychain_password" "$SIGN_KEYCHAIN"

    local p12_path="$SIGN_KEYCHAIN_DIR/cert.p12"
    printf '%s' "$APPLE_DEVELOPER_ID_P12" | base64 --decode > "$p12_path"
    # -A lets codesign use the key without prompting. The keychain is
    # short-lived and local to this script run.
    security import "$p12_path" \
        -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" \
        -A -f pkcs12 -k "$SIGN_KEYCHAIN" >/dev/null \
        || fatal "Could not import APPLE_DEVELOPER_ID_P12. Check that the secret holds a valid base64 .p12 and that APPLE_DEVELOPER_ID_P12_PASSWORD matches its export password. See docs/signing-and-notarization.md."
    rm -f "$p12_path"

    # Without a partition list trusting Apple's signing tools, codesign
    # cannot use the imported private key non-interactively on CI runners.
    security set-key-partition-list -S apple-tool:,apple: \
        -k "$keychain_password" "$SIGN_KEYCHAIN" >/dev/null

    # Make the temporary keychain visible to the security toolchain. The
    # unquoted expansion is deliberate: it word-splits the previous search
    # list back into one argument per keychain.
    security list-keychains -d user -s "$SIGN_KEYCHAIN" $(security list-keychains -d user | tr -d '"')

    resolve_signing_identity
}

# Reject a valid certificate from a different developer team rather than
# accidentally signing a release with it.
resolve_signing_identity() {
    command -v openssl >/dev/null \
        || fatal "openssl is required to verify the imported certificate's team"

    local identities
    identities=$(security find-identity -v -p codesigning "$SIGN_KEYCHAIN")

    SIGN_IDENTITY=$(printf '%s\n' "$identities" \
        | sed -n 's/.*"\(.*\)".*/\1/p' \
        | grep -Fx "$APPLE_DEVELOPER_ID_NAME" || true)
    if [[ -z "$SIGN_IDENTITY" ]]; then
        # List what the p12 actually contains; the configured secret value
        # itself is never echoed (identity names are printed from the
        # keychain only, and only on this failure path).
        printf '%s' 'Identities found in the temporary keychain:' >&2
        printf '%s\n' "$identities" | sed -n 's/.*"\(.*\)".*/  \1/p' >&2
        fatal "APPLE_DEVELOPER_ID_NAME does not match any imported identity. Fix the secret or re-export the .p12 — see docs/signing-and-notarization.md."
    fi

    # The Team ID is the certificate's Organizational Unit (OU).
    local cert_team
    cert_team=$(security find-certificate -c "$SIGN_IDENTITY" -p "$SIGN_KEYCHAIN" \
        | openssl x509 -noout -subject | tr -d ' ' \
        | grep -oE 'OU=[A-Z0-9]+' | head -1 || true)
    cert_team="${cert_team#OU=}"
    [[ -n "$cert_team" ]] \
        || fatal "Could not read the Team ID (OU) from the imported certificate."
    if [[ "$cert_team" != "$APPLE_DEVELOPER_ID_TEAM_ID" ]]; then
        fatal "The imported certificate belongs to team $cert_team, which does not match APPLE_DEVELOPER_ID_TEAM_ID. One of the two secrets is wrong."
    fi

    ok "Imported signing identity for team $cert_team"
}

sign_devid() {
    # --timestamp embeds a trusted timestamp so the signature remains valid
    # after certificate expiry.
    local app_dir="$1"
    info "Developer ID signing…"
    codesign --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp \
        -s "$SIGN_IDENTITY" \
        "$app_dir"
    verify_devid_signature "$app_dir"
    ok "Developer ID signed and verified"
}

# Verify the signature and team on the exact app that will be notarized.
verify_devid_signature() {
    local target="$1"
    codesign --verify --deep --strict --verbose=4 "$target"

    local signed_team
    signed_team=$(codesign -dvv "$target" 2>&1 | sed -n 's/^TeamIdentifier=//p')
    [[ "$signed_team" == "$APPLE_DEVELOPER_ID_TEAM_ID" ]] \
        || fatal "Signature carries TeamIdentifier=${signed_team:-<none>}, expected the team named by APPLE_DEVELOPER_ID_TEAM_ID."
}

# One authentication path for every notarytool call, built once after lane
# detection. Never logged.
NOTARY_ARGS=()
init_notary_args() {
    NOTARY_ARGS=(
        --apple-id  "$APP_NOTARY_APPLE_ID"
        --team-id   "$APPLE_DEVELOPER_ID_TEAM_ID"
        --password  "$APP_NOTARY_APP_SPECIFIC_PASSWORD"
    )
}

# The JSON response avoids parsing progress output, whose format is intended for
# people and can include status spinners.
notary_json_field() {
    local field="$1"
    /usr/bin/python3 -c '
import json
import sys

try:
    value = json.load(sys.stdin).get(sys.argv[1])
except (json.JSONDecodeError, AttributeError, IndexError):
    raise SystemExit(1)

if value is not None:
    print(value)
' "$field"
}

notary_submission_id() {
    local output="$1"
    local submission_id

    submission_id=$(printf '%s\n' "$output" | notary_json_field id || true)
    if [[ -z "$submission_id" ]]; then
        submission_id=$(printf '%s\n' "$output" | /usr/bin/python3 -c '
import re
import sys

match = re.search(
    r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
    sys.stdin.read(),
)
if match:
    print(match.group(0))
' || true)
    fi
    printf '%s' "$submission_id"
}

# Submit a supported container and require an accepted verdict.
notarize() {
    local target="$1"
    info "Notarizing $(basename "$target")…"

    # Only stdout is captured — it carries the JSON verdict parsed below.
    # notarytool's diagnostics go to stderr and flow straight to the log, so
    # they can never corrupt the JSON status parse.
    local output submission_id status
    if ! output=$(xcrun notarytool submit "$target" "${NOTARY_ARGS[@]}" \
        --wait --no-progress --output-format json); then
        printf '%s\n' "$output" >&2
        submission_id=$(notary_submission_id "$output")
        if [[ -n "$submission_id" ]]; then
            xcrun notarytool log "$submission_id" "${NOTARY_ARGS[@]}" >&2 || true
        fi
        fatal "notarytool could not submit $(basename "$target"). For Apple ID or app-specific-password errors, see docs/signing-and-notarization.md §Troubleshooting."
    fi

    submission_id=$(notary_submission_id "$output")
    status=$(printf '%s\n' "$output" | notary_json_field status || true)

    if [[ "$status" != "Accepted" ]]; then
        warn "Notarization status for $(basename "$target"): ${status:-unknown}"
        if [[ -n "$submission_id" ]]; then
            xcrun notarytool log "$submission_id" "${NOTARY_ARGS[@]}" >&2 || true
        else
            warn "No submission ID captured; cannot fetch the notary log."
        fi
        fatal "Notarization did not reach Accepted for $(basename "$target")."
    fi
    ok "Notary service accepted $(basename "$target") (submission ${submission_id:-unknown})"
}

staple_and_validate() {
    local target="$1"
    xcrun stapler staple "$target" \
        || fatal "stapler could not staple $(basename "$target") — the notary ticket is missing or does not match this exact artifact."
    xcrun stapler validate "$target" \
        || fatal "stapler validation failed for $(basename "$target")."
    ok "Stapled and validated: $(basename "$target")"
}

# The notary service does not accept a bare .app — it accepts a zip that
# preserves the bundle wrapper. ditto --keepParent keeps Filbert.app/ as the
# zip's root directory; the zip is temporary and never shipped.
notarize_app() {
    local app_dir="$1"
    NOTARY_WORK_DIR="$(mktemp -d)"
    local zip_path="$NOTARY_WORK_DIR/$APP_NAME-notarization.zip"
    ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$zip_path"
    notarize "$zip_path"
    staple_and_validate "$app_dir"
}

# create-dmg (https://github.com/create-dmg/create-dmg) is a hard dependency.
# It produces the conventional drag-to-/Applications presentation: fixed
# window size, icon positioning, and the Applications
# drop-link. Rolling this by hand would mean reimplementing its AppleScript
# and .DS_Store logic for no gain — create-dmg is the community standard.
#
# We do NOT use create-dmg's --codesign/--notarize flags: those use
# notarytool's --keychain-profile flow, which diverges from the spec's
# --apple-id/--team-id/--password environment-secret flow. Keeping
# one auth path for both the .app and the DMG is simpler.
create_dmg() {
    local stage_dir="$1"
    local dmg_path="$2"

    command -v create-dmg >/dev/null 2>&1 \
        || fatal "create-dmg not found. Install with: brew install create-dmg"

    mkdir -p "$(dirname "$dmg_path")"

    # --no-internet-enable: deprecated macOS feature that auto-mounted and
    # copied DMG contents on download. Modern macOS ignores it; passing the
    # flag silences create-dmg's warning.
    create-dmg \
        --volname "$APP_NAME $VERSION" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 100 \
        --icon "$APP_NAME.app" 175 190 \
        --app-drop-link 425 190 \
        --no-internet-enable \
        "$dmg_path" \
        "$stage_dir"
}

# Verifies the exact DMG that will be uploaded: the DMG's own staple, then a
# copy of the app taken from a mounted read-only image — codesign deep+strict,
# spctl Gatekeeper assessment, and the app's stapled ticket.
verify_release() {
    local dmg_path="$1"
    info "Verifying the release artifact…"

    if [[ "${LANE:-}" == "signed" ]]; then
        xcrun stapler validate "$dmg_path" \
            || fatal "stapler validation failed for the DMG."
    fi

    local mount_point
    mount_point="$(mktemp -d)"
    VERIFY_MOUNT_POINT="$mount_point"
    hdiutil attach -readonly -nobrowse -mountpoint "$mount_point" "$dmg_path" >/dev/null

    local verify_app="/tmp/filbert-verify-$$"
    rm -rf "$verify_app"
    cp -R "$mount_point/$APP_NAME.app" "$verify_app"
    hdiutil detach "$mount_point" >/dev/null
    VERIFY_MOUNT_POINT=""
    rmdir "$mount_point" 2>/dev/null || true

    codesign --verify --deep --strict --verbose=4 "$verify_app"
    if [[ "${LANE:-}" == "signed" ]]; then
        spctl --assess --type execute -vv "$verify_app" \
            || fatal "spctl rejected the signed app — Gatekeeper assessment failed."
        xcrun stapler validate "$verify_app" \
            || fatal "stapler validation failed for the app copied out of the DMG."
        codesign -dvv "$verify_app" 2>&1 | grep -E '^(Authority|TeamIdentifier)=' >&2 || true
    else
        # spctl only meaningfully assesses Developer-ID-signed binaries; for
        # ad-hoc it returns an error, which we tolerate on the unsigned lane.
        spctl --assess --type execute -vv "$verify_app" \
            || warn "spctl rejected ad-hoc signed app (expected on unsigned lane)."
    fi

    rm -rf "$verify_app"
    ok "Release artifact verified"
}

# Writes the release notes for this lane to <dmg>.release-notes.md so the
# workflow can attach them to the GitHub Release. The note text is static
# (checked in via this script), never generated by an LLM at release time.
write_release_notes() {
    local dmg_path="$1"
    local notes_path="${dmg_path%.dmg}.release-notes.md"
    local checksum
    checksum=$(shasum -a 256 "$dmg_path" | awk '{print $1}')

    if [[ "$LANE" == "signed" ]]; then
        cat > "$notes_path" <<EOF
## Filbert $VERSION

Developer ID-signed and Apple-notarized macOS build (Apple Silicon).

- **DMG:** $(basename "$dmg_path")
- **SHA-256:** \`$checksum\`

## Install

1. Mount the DMG and drag **Filbert** to **/Applications**.
2. Launch **Filbert** normally.

No Gatekeeper bypass is needed. macOS may still show its standard
first-open confirmation for apps downloaded from the internet — confirm
and open.
EOF
    else
        cat > "$notes_path" <<EOF
## Filbert $VERSION — local build

Unsigned macOS build (Apple Silicon). Direct distribution, ad-hoc signed.
This is a local development artifact, not an official GitHub Release;
official releases are Developer ID-signed and notarized.

- **DMG:** $(basename "$dmg_path")
- **SHA-256:** \`$checksum\`

## Install

1. Mount the DMG and drag **Filbert** to **/Applications**.
2. On first launch, macOS Gatekeeper will block the app because it is
   only ad-hoc signed. Do one of:
   - **Right-click** Filbert in /Applications → **Open** → confirm the
     prompt. Only needed once.
   - Or run this in Terminal:

     \`\`\`sh
     xattr -cr '/Applications/Filbert.app'
     \`\`\`
EOF
    fi

    shasum -a 256 "$dmg_path" > "${dmg_path}.sha256"
    ok "Wrote release notes: $notes_path"
}

cleanup() {
    if [[ -n "${SIGN_KEYCHAIN:-}" && -f "$SIGN_KEYCHAIN" ]]; then
        security delete-keychain "$SIGN_KEYCHAIN" 2>/dev/null || true
    fi
    [[ -z "${SIGN_KEYCHAIN_DIR:-}" ]] || rm -rf "$SIGN_KEYCHAIN_DIR"
    [[ -z "${NOTARY_WORK_DIR:-}" ]] || rm -rf "$NOTARY_WORK_DIR"
    if [[ -n "${VERIFY_MOUNT_POINT:-}" ]]; then
        hdiutil detach "$VERIFY_MOUNT_POINT" >/dev/null 2>&1 || true
        rmdir "$VERIFY_MOUNT_POINT" 2>/dev/null || true
    fi
}
trap cleanup EXIT

main() {
    parse_args "$@"

    LANE=$(detect_lane)
    info "Release lane: $LANE"

    build_release

    local stage_dir app_dir dmg_name dmg_path
    stage_dir="$(mktemp -d)"
    app_dir=$(assemble_bundle "$stage_dir")

    case "$LANE" in
        signed)
            import_signing_certificate
            init_notary_args
            sign_devid "$app_dir"
            notarize_app "$app_dir"
            ;;
        unsigned)
            sign_adhoc "$app_dir"
            ;;
    esac

    codesign --verify --verbose=4 "$app_dir"

    dmg_name="Filbert-$VERSION-$ARCH.dmg"
    dmg_path="$OUTPUT_DIR/$dmg_name"
    rm -f "$dmg_path"
    create_dmg "$stage_dir" "$dmg_path"

    case "$LANE" in
        signed)
            # Notarize the DMG itself so Gatekeeper passes before mount.
            notarize "$dmg_path"
            staple_and_validate "$dmg_path"
            ;;
    esac

    verify_release "$dmg_path"
    write_release_notes "$dmg_path"

    rm -rf "$stage_dir"

    ok "Done: $dmg_path"
    echo "$dmg_path"
}

main "$@"

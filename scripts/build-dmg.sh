#!/usr/bin/env bash
# scripts/build-dmg.sh
#
# Builds AI Usage.app and packages it into an arm64 DMG.
# Single entry point for local and CI builds (ci 02 AC8).
#
# Requires: create-dmg (brew install create-dmg) for DMG packaging.
#
# Usage:
#   scripts/build-dmg.sh --version <semver> [--output <dir>] [--no-sign]
#
# Signing lane is auto-detected from the environment (ci 02 Plan §3):
# all six secrets present  → Developer ID sign + notarize + staple (AC2/AC3)
# any secret missing       → ad-hoc sign, skip notarization (AC0)
# --no-sign                → forces the unsigned lane regardless of secrets
#
# Never echo secret values. Credentials are read from the environment at the
# point of use and never logged (ci 02 AC6).

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────

APP_NAME="AI Usage"
APP_BUNDLE_ID="com.victorhqc.ai-usage"
ARCH="arm64"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build/$ARCH-apple-macosx/release"
ENTITLEMENTS="$REPO_ROOT/packaging/AIUsage.entitlements"
INFO_PLIST_TEMPLATE="$REPO_ROOT/packaging/Info.plist"

# Secrets that flip the script into the signed lane (ci 02 Plan §8).
SIGN_SECRET_NAMES=(
    APPLE_DEVELOPER_ID_P12
    APPLE_DEVELOPER_ID_P12_PASSWORD
    APPLE_DEVELOPER_ID_TEAM_ID
    APPLE_DEVELOPER_ID_NAME
    APP_NOTARY_APPLE_ID
    APP_NOTARY_APP_SPECIFIC_PASSWORD
)

# ─── Defaults ───────────────────────────────────────────────────────────────

VERSION=""
OUTPUT_DIR="$REPO_ROOT/dist"
FORCE_NO_SIGN=false

# ─── Logging ────────────────────────────────────────────────────────────────

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*" >&2; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# ─── Argument parsing ───────────────────────────────────────────────────────

usage() {
    cat <<EOF
Usage: $0 --version <semver> [--output <dir>] [--no-sign]

Options:
  --version <semver>   Version string baked into Info.plist and DMG name.
  --output <dir>       Destination directory for the DMG (default: ./dist).
  --no-sign            Force the unsigned lane (ci 02 AC0) even when all
                       signing secrets are present. Useful for local test
                       builds.
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
            -h|--help)
                usage; exit 0 ;;
            *)
                fatal "Unknown argument: $1 (see --help)" ;;
        esac
    done

    [[ -n "$VERSION" ]] || fatal "--version is required (e.g. 0.1.0)"
    [[ -f "$INFO_PLIST_TEMPLATE" ]] || fatal "Missing Info.plist template: $INFO_PLIST_TEMPLATE"
    [[ -f "$ENTITLEMENTS" ]] || fatal "Missing entitlements: $ENTITLEMENTS"
}

# ─── Lane detection (ci 02 Plan §3) ─────────────────────────────────────────

# Echoes "signed" or "unsigned". The probe is a single check, not duplicated
# per step (ci 02 Plan §3).
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
    else
        warn "Signing lane disabled — missing: ${missing[*]}"
        warn "Falling through to the unsigned lane (ci 02 AC0)."
        echo "unsigned"
    fi
}

# ─── Build ──────────────────────────────────────────────────────────────────

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
    # relink so Bundle.module resolves against Contents/Resources/ at
    # runtime (ci 03).
    patch_resource_bundle_accessors
}

# ─── Resource accessor patch (ci 03) ─────────────────────────────────────────

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
# AC1: every accessor under .build/<arch>-apple-macosx/release/ is patched,
# the executable is relinked against the patched accessors, and no
# original-form line survives. If a future Swift changes the template, the
# post-rebuild assertion fails loudly rather than shipping a broken app.
patch_resource_bundle_accessors() {
    local release_tree="$REPO_ROOT/.build/$ARCH-apple-macosx/release"
    local original='Bundle\.main\.bundleURL\.appendingPathComponent'
    local patched='(Bundle.main.resourceURL ?? Bundle.main.bundleURL).appendingPathComponent'

    # Collect every generated accessor (one per module with resources:
    # App, Core, ClaudeCodeProvider, DeepSeekProvider, ZAIProvider).
    local accessors=()
    while IFS= read -r accessor; do
        accessors+=("$accessor")
    done < <(find "$release_tree" \
        -path '*/DerivedSources/resource_bundle_accessor.swift' \
        -type f)
    [[ ${#accessors[@]} -gt 0 ]] \
        || fatal "No resource_bundle_accessor.swift under $release_tree"

    info "Patching ${#accessors[@]} resource_bundle_accessor.swift file(s)…"
    for accessor in "${accessors[@]}"; do
        sed -i '' "s|$original|$patched|g" "$accessor"
    done

    # Relink the executable against the patched accessors. SPM regenerates
    # the accessor from its template only when its inputs (Package.swift
    # resource declarations) change; a second no-op build treats the
    # accessor as a regular source edit and recompiles only the affected
    # modules.
    (
        cd "$REPO_ROOT"
        swift build -c release --arch arm64
    )
    [[ -x "$BUILD_DIR/App" ]] \
        || fatal "Relink produced no executable at $BUILD_DIR/App"

    # Assert the patch survived the relink. If SPM regenerated the
    # accessor from its template (template drift), the original form
    # reappears and we fail loudly per ci 03 AC1 / Risks.
    local unpatched=()
    local still_present=()
    while IFS= read -r accessor; do
        still_present+=("$accessor")
        grep -q "$original" "$accessor" && unpatched+=("$accessor")
    done < <(find "$release_tree" \
        -path '*/DerivedSources/resource_bundle_accessor.swift' \
        -type f)

    [[ ${#still_present[@]} -eq ${#accessors[@]} ]] \
        || fatal "Accessor count changed across rebuild (before=${#accessors[@]}, after=${#still_present[@]})"
    [[ ${#unpatched[@]} -eq 0 ]] \
        || fatal "Unpatched resource_bundle_accessor.swift after rebuild (SPM template drift?): ${unpatched[*]}"

    ok "Patched and relinked ${#accessors[@]} resource_bundle_accessor.swift file(s)"
}

# ─── Bundle assembly (ci 02 AC1, Plan §1B) ──────────────────────────────────

# Assembles AI Usage.app into the passed staging dir and echoes its path.
# Layout (ci 02 AC1, ci 03 AC2):
#   AI Usage.app/
#     Contents/
#       Info.plist                            (generated from template)
#       MacOS/AI Usage                        (renamed release executable)
#       Resources/                            (SPM resource bundles + icon)
#         ai-usage_App.bundle/                (Bundle.module lookup target)
#         ai-usage_ClaudeCodeProvider.bundle/
#         ai-usage_Core.bundle/
#         ai-usage_DeepSeekProvider.bundle/
#         ai-usage_ZAIProvider.bundle/
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
    # the accessor to look here via Bundle.main.resourceURL (ci 03 AC2).
    # If either piece is missing, statusline_helper.swift (providers 02 §5)
    # and AppIcon/Localizable lookups fail at runtime.
    local bundle_count=0
    while IFS= read -r bundle; do
        cp -R "$bundle" "$app_dir/Contents/Resources/"
        bundle_count=$((bundle_count + 1))
    done < <(find "$BUILD_DIR" -maxdepth 1 -name 'ai-usage_*.bundle' -type d)
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

# ─── Signing ────────────────────────────────────────────────────────────────

sign_adhoc() {
    # ci 02 AC0: ad-hoc sign so the bundle runs on the maintainer's machine
    # without re-signing. --options runtime is harmless here and keeps the
    # command symmetric with the Developer ID lane.
    local app_dir="$1"
    info "Ad-hoc signing (ci 02 AC0)…"
    codesign -s - --force --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        "$app_dir"
    ok "Ad-hoc signed"
}

# Fresh keychain for the signing cert (ci 02 AC6). Cleaned up on exit.
SIGN_KEYCHAIN=""
SIGN_IDENTITY=""

import_signing_certificate() {
    # All six secrets are present (detect_lane already verified). Import the
    # p12 into a temporary keychain that is deleted on script exit.
    SIGN_KEYCHAIN="$(mktemp -d)/signing.keychain-db"
    local keychain_password
    keychain_password="$(uuidgen)"

    security create-keychain -p "$keychain_password" "$SIGN_KEYCHAIN" >/dev/null
    security set-keychain-settings -lut 21600 "$SIGN_KEYCHAIN"
    security unlock-keychain -p "$keychain_password" "$SIGN_KEYCHAIN"

    local p12_path="$SIGN_KEYCHAIN/cert.p12"
    printf '%s' "$APPLE_DEVELOPER_ID_P12" | base64 --decode > "$p12_path"
    # -A lets codesign use the key without prompting. The keychain is
    # short-lived and local to this script run.
    security import "$p12_path" \
        -P "$APPLE_DEVELOPER_ID_P12_PASSWORD" \
        -A -t cert -f pkcs12 -k "$SIGN_KEYCHAIN" >/dev/null
    rm -f "$p12_path"

    # Make the temporary keychain visible to the security toolchain.
    security list-keychains -d user -s "$SIGN_KEYCHAIN" "$(security list-keychains -d user | tr -d '"')"

    # Resolve the imported identity. Prefer the explicit name from secrets;
    # fall back to whatever Developer ID Application cert was imported.
    if security find-identity -v -p codesigning "$SIGN_KEYCHAIN" | grep -q "$APPLE_DEVELOPER_ID_NAME"; then
        SIGN_IDENTITY="$APPLE_DEVELOPER_ID_NAME"
    else
        SIGN_IDENTITY=$(security find-identity -v -p codesigning "$SIGN_KEYCHAIN" \
            | grep "Developer ID Application" \
            | head -1 \
            | sed 's/.*"\(.*\)".*/\1/')
    fi
    [[ -n "$SIGN_IDENTITY" ]] || fatal "Could not resolve Developer ID Application identity"
    ok "Imported signing identity"
}

sign_devid() {
    # ci 02 AC2: sign with Developer ID Application. --timestamp embeds a
    # trusted time stamp so the signature stays valid after cert expiry.
    local app_dir="$1"
    info "Developer ID signing (ci 02 AC2)…"
    codesign --deep --options runtime \
        --entitlements "$ENTITLEMENTS" \
        --timestamp \
        -s "$SIGN_IDENTITY" \
        "$app_dir"
    codesign --verify --verbose=4 "$app_dir"
    ok "Developer ID signed and verified"
}

# ─── Notarization ───────────────────────────────────────────────────────────

# Notarizes any target (.app or .dmg). On rejection, pulls the notary log
# and fails — no silent success (ci 02 AC3).
notarize_and_staple() {
    local target="$1"
    info "Notarizing $(basename "$target") (ci 02 AC3)…"

    local submission_id submission_state
    submission_id=$(xcrun notarytool submit "$target" \
        --apple-id  "$APP_NOTARY_APPLE_ID" \
        --team-id   "$APPLE_DEVELOPER_ID_TEAM_ID" \
        --password  "$APP_NOTARY_APP_SPECIFIC_PASSWORD" \
        --wait \
        2>&1 | tee /dev/stderr | grep -E '^\s*id:' | head -1 | awk '{print $2}')

    if ! xcrun stapler staple "$target"; then
        warn "Staple failed — pulling notary log for diagnosis."
        [[ -n "$submission_id" ]] \
            && xcrun notarytool log "$submission_id" \
                --apple-id  "$APP_NOTARY_APPLE_ID" \
                --team-id   "$APPLE_DEVELOPER_ID_TEAM_ID" \
                --password  "$APP_NOTARY_APP_SPECIFIC_PASSWORD" \
            || warn "No submission id captured; cannot fetch log."
        fatal "Notarization or stapling failed for $target"
    fi
    xcrun stapler validate "$target"
    ok "Notarized and stapled: $(basename "$target")"
}

# ─── DMG packaging (ci 02 AC4) ──────────────────────────────────────────────
#
# create-dmg (https://github.com/create-dmg/create-dmg) is a hard dependency.
# It produces the conventional drag-to-/Applications presentation that AC4
# calls for: fixed window size, icon positioning, and the Applications
# drop-link. Rolling this by hand would mean reimplementing its AppleScript
# and .DS_Store logic for no gain — create-dmg is the community standard.
#
# We do NOT use create-dmg's --codesign/--notarize flags: those use
# notarytool's --keychain-profile flow, which diverges from the spec's
# --apple-id/--team-id/--password env-secret flow (ci 02 Plan §8). Keeping
# one auth path for both the .app and the DMG is simpler and matches AC6.
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

# ─── Verification (ci 02 AC5) ───────────────────────────────────────────────

verify_release() {
    local dmg_path="$1"
    info "Verifying DMG (ci 02 AC5)…"

    local mount_point
    mount_point="$(mktemp -d)"
    hdiutil attach -readonly -nobrowse -mountpoint "$mount_point" "$dmg_path" >/dev/null

    local verify_app="/tmp/ai-usage-verify-$$"
    rm -rf "$verify_app"
    cp -R "$mount_point/$APP_NAME.app" "$verify_app"
    hdiutil detach "$mount_point" >/dev/null
    rmdir "$mount_point" 2>/dev/null || true

    codesign --verify --verbose=4 "$verify_app"
    # spctl only meaningfully assesses Developer-ID-signed binaries; for ad-hoc
    # it returns an error, which we tolerate on the unsigned lane.
    if [[ "${LANE:-}" == "signed" ]]; then
        spctl --assess --type execute -vv "$verify_app"
    else
        spctl --assess --type execute -vv "$verify_app" || warn "spctl rejected ad-hoc signed app (expected on unsigned lane)."
    fi

    rm -rf "$verify_app"
    ok "DMG verified"
}

# ─── Release body (ci 02 Plan §7, AC10) ─────────────────────────────────────

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
# AI Usage $VERSION

Signed and notarized macOS build (Apple Silicon).

- **DMG:** $(basename "$dmg_path")
- **SHA-256:** \`$checksum\`

Drag **AI Usage** to **/Applications**. The app is signed and notarized, so
it launches with no Gatekeeper warning.
EOF
    else
        cat > "$notes_path" <<EOF
# AI Usage $VERSION

Unsigned macOS build (Apple Silicon). Direct distribution, ad-hoc signed.

- **DMG:** $(basename "$dmg_path")
- **SHA-256:** \`$checksum\`

## Install

1. Mount the DMG and drag **AI Usage** to **/Applications**.
2. On first launch, macOS Gatekeeper will block the app because it is
   unsigned. Do one of:
   - **Right-click** AI Usage in /Applications → **Open** → confirm the
     prompt. Only needed once.
   - Or run this in Terminal:

     \`\`\`sh
     xattr -cr '/Applications/AI Usage.app'
     \`\`\`

## Why unsigned?

This is a transitional state. The moment an Apple Developer Program
membership is configured, releases automatically become signed and
notarized with no action on your part.
EOF
    fi

    shasum -a 256 "$dmg_path" > "${dmg_path}.sha256"
    ok "Wrote release notes: $notes_path"
}

# ─── Cleanup ────────────────────────────────────────────────────────────────

cleanup() {
    if [[ -n "$SIGN_KEYCHAIN" && -f "$SIGN_KEYCHAIN" ]]; then
        security delete-keychain "$SIGN_KEYCHAIN" 2>/dev/null || true
        rm -rf "$(dirname "$SIGN_KEYCHAIN")"
    fi
}
trap cleanup EXIT

# ─── Main ───────────────────────────────────────────────────────────────────

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
            sign_devid "$app_dir"
            notarize_and_staple "$app_dir"
            ;;
        unsigned)
            sign_adhoc "$app_dir"
            ;;
    esac

    codesign --verify --verbose=4 "$app_dir"

    dmg_name="AI-Usage-$VERSION-$ARCH.dmg"
    dmg_path="$OUTPUT_DIR/$dmg_name"
    rm -f "$dmg_path"
    create_dmg "$stage_dir" "$dmg_path"

    case "$LANE" in
        signed)
            # Notarize the DMG itself so Gatekeeper passes before mount.
            notarize_and_staple "$dmg_path"
            ;;
    esac

    verify_release "$dmg_path"
    write_release_notes "$dmg_path"

    rm -rf "$stage_dir"

    ok "Done: $dmg_path"
    echo "$dmg_path"
}

main "$@"

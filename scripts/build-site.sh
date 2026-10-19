#!/usr/bin/env bash
# scripts/build-site.sh
#
# Assembles the GitHub Pages site: the landing page from site/ plus the Sparkle
# appcast. Single entry point for local previews and the Pages workflow.
#
# Usage:
#   scripts/build-site.sh --version <semver> --out <dir> [--appcast <file>]
#
# Pages deployments replace the whole site, and installed apps read
# appcast.xml from it. The Pages workflow therefore always passes --appcast;
# omit it only for a local preview.

set -euo pipefail

VERSION_TOKEN="__FILBERT_VERSION__"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_DIR="$REPO_ROOT/site"

VERSION=""
OUT_DIR=""
APPCAST=""

info()  { printf '\033[1;34m▸\033[0m %s\n' "$*" >&2; }
ok()    { printf '\033[1;32m✓\033[0m %s\n' "$*" >&2; }
fatal() { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Usage: $0 --version <semver> --out <dir> [--appcast <file>]

Options:
  --version <semver>   Release version the download links point to (X.Y.Z).
  --out <dir>          Destination directory. Must not exist or be empty.
  --appcast <file>     Sparkle appcast to publish as appcast.xml. It must be
                       well-formed and reference the DMG of --version.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="${2:-}"; shift 2 ;;
        --out)     OUT_DIR="${2:-}"; shift 2 ;;
        --appcast) APPCAST="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; fatal "Unknown argument: $1" ;;
    esac
done

[[ -n "$VERSION" ]] || { usage >&2; fatal "--version is required"; }
[[ -n "$OUT_DIR" ]] || { usage >&2; fatal "--out is required"; }
[[ "$VERSION" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
    || fatal "Version must be plain X.Y.Z: $VERSION"

if [[ -e "$OUT_DIR" ]]; then
    [[ -d "$OUT_DIR" ]] || fatal "--out exists and is not a directory: $OUT_DIR"
    [[ -z "$(ls -A "$OUT_DIR")" ]] || fatal "--out is not empty: $OUT_DIR"
fi

DMG_URL="https://github.com/victorhqc/filbert/releases/download/v${VERSION}/Filbert-${VERSION}-arm64.dmg"

if [[ -n "$APPCAST" ]]; then
    info "Checking appcast $APPCAST"
    [[ -s "$APPCAST" ]] || fatal "Appcast is missing or empty: $APPCAST"
    python3 -I - "$APPCAST" "$DMG_URL" <<'PY' || fatal "Appcast check failed"
import sys
import xml.etree.ElementTree as ET

path, expected = sys.argv[1:]
try:
    root = ET.parse(path).getroot()
except ET.ParseError as error:
    sys.exit(f"Appcast is not well-formed XML: {error}")
urls = {node.get("url") for node in root.iter("enclosure")}
if expected not in urls:
    sys.exit(f"Appcast does not reference {expected}")
PY
fi

info "Building site for v$VERSION into $OUT_DIR"
mkdir -p "$OUT_DIR"
cp -R "$SITE_DIR/." "$OUT_DIR/"
find "$OUT_DIR" -name '.DS_Store' -delete

while IFS= read -r -d '' page; do
    sed -i.bak "s/${VERSION_TOKEN}/${VERSION}/g" "$page"
    rm "$page.bak"
done < <(find "$OUT_DIR" -name '*.html' -print0)

if grep -rl "$VERSION_TOKEN" "$OUT_DIR" >/dev/null; then
    fatal "Unreplaced $VERSION_TOKEN in: $(grep -rl "$VERSION_TOKEN" "$OUT_DIR" | tr '\n' ' ')"
fi

missing=()
while IFS= read -r ref; do
    [[ -e "$OUT_DIR/$ref" ]] || missing+=("$ref")
done < <(grep -ohE '(src|href|srcset)="[^"]+"' "$OUT_DIR"/*.html \
    | sed -E 's/^(src|href|srcset)="([^"]*)"$/\2/' \
    | tr ',' '\n' \
    | awk '{ print $1 }' \
    | sed -E 's/[#?].*$//' \
    | grep -vE '^(https?:|mailto:|\./?$|$)' \
    | sort -u)
[[ ${#missing[@]} -eq 0 ]] || fatal "Missing referenced files: ${missing[*]}"

if [[ -n "$APPCAST" ]]; then
    cp "$APPCAST" "$OUT_DIR/appcast.xml"
fi

ok "Site ready: $OUT_DIR"

#!/bin/bash
# Build both architectures and create signed feeds locally; never publishes.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_DIR/scripts/sparkle-tools.sh"
VERSION=1.2.0
[[ $# -le 1 ]] || { echo "Too many arguments" >&2; exit 1; }
if [[ "${1:-}" != --feeds-only ]]; then
    [[ $# -eq 0 ]] || { echo 'Usage: bash scripts/release-updates.sh [--feeds-only]' >&2; exit 1; }
    bash "$PROJECT_DIR/scripts/build.sh" arm64
    bash "$PROJECT_DIR/scripts/build.sh" x86_64
fi
PUBLIC_KEY="$(tr -d '\r\n' < "$PROJECT_DIR/Resources/UpdatePublicKey.txt")"
[[ "$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_ACCOUNT" -p)" == "$PUBLIC_KEY" ]] || {
    echo 'Signing Keychain account does not match bundled public key' >&2; exit 1;
}
DIST_DIR="$PROJECT_DIR/dist"
RELEASE_TMP="$(mktemp -d "$DIST_DIR/.signed-feeds.XXXXXX")"
trap 'rm -rf -- "$RELEASE_TMP"' EXIT
for target in arm64 x86_64; do
    archive="FeatherSweep-${VERSION}-${target}.dmg"
    [[ -f "$DIST_DIR/$archive" ]] || { echo "Missing $archive" >&2; exit 1; }
    mkdir "$RELEASE_TMP/$target"
    ln "$DIST_DIR/$archive" "$RELEASE_TMP/$target/$archive"
    "$SPARKLE_BIN/generate_appcast" --account "$SPARKLE_ACCOUNT" \
        --download-url-prefix "https://github.com/zimuoo/FeatherSweep/releases/download/v${VERSION}/" \
        --maximum-deltas 0 -o "$RELEASE_TMP/$target/appcast.xml" "$RELEASE_TMP/$target"
    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" "$RELEASE_TMP/$target/appcast.xml"
    "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$RELEASE_TMP/$target/appcast.xml"
    python3 -I "$PROJECT_DIR/scripts/verify-update-feed.py" "$RELEASE_TMP/$target/appcast.xml" "$DIST_DIR/$archive" "$target" "$VERSION" "$SPARKLE_BIN/sign_update" "$SPARKLE_ACCOUNT"
    # A modified signed feed must fail verification.
    cp "$RELEASE_TMP/$target/appcast.xml" "$RELEASE_TMP/tampered.xml"
    python3 -I - "$RELEASE_TMP/tampered.xml" <<'PYTAMPER'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
data = path.read_bytes()
assert b"<title>" in data
path.write_bytes(data.replace(b"<title>", b"<title>TAMPER", 1))
PYTAMPER
    if "$SPARKLE_BIN/sign_update" --account "$SPARKLE_ACCOUNT" --verify "$RELEASE_TMP/tampered.xml"; then
        echo 'Tampered feed unexpectedly verified' >&2; exit 1
    fi
    mv "$RELEASE_TMP/$target/appcast.xml" "$RELEASE_TMP/appcast-${target}.xml"
done
(cd "$DIST_DIR" && shasum -a 256 "FeatherSweep-${VERSION}-arm64.dmg" "FeatherSweep-${VERSION}-x86_64.dmg") > "$RELEASE_TMP/SHA256SUMS"
for name in appcast-arm64.xml appcast-x86_64.xml SHA256SUMS; do
    mv "$RELEASE_TMP/$name" "$DIST_DIR/$name"
done
echo "Signed feeds and SHA256SUMS: $DIST_DIR"

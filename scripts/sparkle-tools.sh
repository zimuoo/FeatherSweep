#!/bin/bash
# Source this file to use the pinned official Sparkle SDK tools.
set -euo pipefail
SPARKLE_VERSION=2.10.1
SPARKLE_ACCOUNT=io.github.zimuoo.FeatherSweep.updates
SPARKLE_SHA256=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
SPARKLE_ROOT="${PROJECT_DIR:?}/.build/sparkle-sdk-${SPARKLE_VERSION}"
if [[ ! -f "$SPARKLE_ROOT/.verified-$SPARKLE_SHA256" ]]; then
    mkdir -p "$PROJECT_DIR/.build"
    SPARKLE_TMP="$(mktemp -d "$PROJECT_DIR/.build/sparkle-download.XXXXXX")"
    trap 'rm -rf -- "$SPARKLE_TMP"' EXIT
    curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
        "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
        -o "$SPARKLE_TMP/sdk.tar.xz"
    echo "$SPARKLE_SHA256  $SPARKLE_TMP/sdk.tar.xz" | shasum -a 256 -c -
    mkdir "$SPARKLE_TMP/sdk"
    tar -xJf "$SPARKLE_TMP/sdk.tar.xz" -C "$SPARKLE_TMP/sdk"
    touch "$SPARKLE_TMP/sdk/.verified-$SPARKLE_SHA256"
    rm -rf -- "$SPARKLE_ROOT"
    mv "$SPARKLE_TMP/sdk" "$SPARKLE_ROOT"
    rm -rf -- "$SPARKLE_TMP"
    trap - EXIT
fi
SPARKLE_BIN="$SPARKLE_ROOT/bin"

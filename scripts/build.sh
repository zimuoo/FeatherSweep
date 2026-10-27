#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="轻扫"
VERSION="1.2.0"
HOST_ARCH="$(uname -m)"
TARGET_ARCH="${1:-$HOST_ARCH}"
if [[ "$#" -gt 1 || ( "$TARGET_ARCH" != "arm64" && "$TARGET_ARCH" != "x86_64" ) ]]; then
    echo "Usage: bash scripts/build.sh [arm64|x86_64] (defaults to the host architecture)" >&2
    exit 1
fi
DMG_NAME="FeatherSweep-${VERSION}-${TARGET_ARCH}.dmg"

if [[ "$(uname -s)" != "Darwin" || ( "$HOST_ARCH" != "arm64" && "$HOST_ARCH" != "x86_64" ) ]]; then
    echo "This build script requires a Mac with Apple's command-line tools." >&2
    exit 1
fi
for tool in swift swiftc iconutil codesign hdiutil strip plutil lipo ditto otool curl shasum; do
    command -v "$tool" >/dev/null || { echo "Missing system tool: $tool" >&2; exit 1; }
done

source "$PROJECT_DIR/scripts/sparkle-tools.sh"
PUBLIC_KEY="$(tr -d '\r\n' < "$PROJECT_DIR/Resources/UpdatePublicKey.txt")"
[[ ${#PUBLIC_KEY} -eq 44 ]] || { echo "Invalid Sparkle public key" >&2; exit 1; }

mkdir -p "$DIST_DIR" "$PROJECT_DIR/Resources/AppIcon.iconset"
# A private directory prevents shared scratch/cache paths or preexisting symlinks.
# Keep it on dist's filesystem so publishing the verified DMG is an atomic rename.
BUILD_ROOT="$(mktemp -d "$DIST_DIR/.feathersweep-build.XXXXXX")"
trap 'rm -rf -- "$BUILD_ROOT"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
RENDERED_RESOURCES="$BUILD_ROOT/resources"
export MACOSX_DEPLOYMENT_TARGET=14.0
export SWIFT_MODULECACHE_PATH="$BUILD_ROOT/swift-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BUILD_ROOT/swiftpm-module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_ROOT/clang-module-cache"
mkdir -p "$SWIFT_MODULECACHE_PATH" "$SWIFTPM_MODULECACHE_OVERRIDE" "$CLANG_MODULE_CACHE_PATH"

echo "Rendering the shared vector logo…"
xcrun swiftc -O -parse-as-library -target "${HOST_ARCH}-apple-macos14.0" \
    -module-cache-path "$SWIFT_MODULECACHE_PATH" \
    "$PROJECT_DIR/Sources/FeatherSweep/Branding.swift" "$PROJECT_DIR/scripts/render-icon.swift" \
    -o "$BUILD_ROOT/render-icon"
"$BUILD_ROOT/render-icon" "$RENDERED_RESOURCES"
iconutil -c icns "$RENDERED_RESOURCES/AppIcon.iconset" -o "$RENDERED_RESOURCES/AppIcon.icns"
# These source asset exports are not inputs to the bundle being packaged.
cp "$RENDERED_RESOURCES/AppLogo.png" "$PROJECT_DIR/Resources/AppLogo.png"
cp "$RENDERED_RESOURCES/AppIcon.icns" "$PROJECT_DIR/Resources/AppIcon.icns"
cp "$RENDERED_RESOURCES/AppIcon.iconset/"*.png "$PROJECT_DIR/Resources/AppIcon.iconset/"

echo "Building FeatherSweep release for ${TARGET_ARCH}…"
BUILD_OPTIONS=(--package-path "$PROJECT_DIR" --scratch-path "$BUILD_ROOT/swiftpm"
    --cache-path "$PROJECT_DIR/.build/packaging-cache"
    --configuration release --triple "${TARGET_ARCH}-apple-macosx14.0" --disable-sandbox
    -Xswiftc -module-cache-path -Xswiftc "$SWIFT_MODULECACHE_PATH"
    -Xcc "-fmodules-cache-path=$CLANG_MODULE_CACHE_PATH"
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks)
xcrun swift build "${BUILD_OPTIONS[@]}" --product FeatherSweep
BIN_DIR="$(xcrun swift build "${BUILD_OPTIONS[@]}" --show-bin-path)"

# All generated intermediate files belong to this run's private work directory.
STAGING_DIR="$BUILD_ROOT/staging"
DMG_TEMP="$BUILD_ROOT/$DMG_NAME"
PAYLOAD_DIR="$STAGING_DIR/payload"
APP_DIR="$PAYLOAD_DIR/$APP_NAME.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/FeatherSweep" "$APP_DIR/Contents/MacOS/FeatherSweep"
chmod 755 "$APP_DIR/Contents/MacOS/FeatherSweep"
strip -x "$APP_DIR/Contents/MacOS/FeatherSweep"
ACTUAL_ARCH="$(lipo -archs "$APP_DIR/Contents/MacOS/FeatherSweep")"
if [[ "$ACTUAL_ARCH" != "$TARGET_ARCH" ]]; then
    echo "Architecture mismatch: expected $TARGET_ARCH, got $ACTUAL_ARCH" >&2
    exit 1
fi
cp "$RENDERED_RESOURCES/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
# The complete official framework retains its signed nested components and symlinks.
mkdir -p "$APP_DIR/Contents/Frameworks"
SPARKLE_FRAMEWORK="$(find "$BUILD_ROOT/swiftpm/artifacts" -type d -name Sparkle.framework -print)"
[[ -d "$SPARKLE_FRAMEWORK" && "$SPARKLE_FRAMEWORK" != *$'\n'* ]] || {
    echo "Expected exactly one resolved SwiftPM Sparkle framework" >&2; exit 1;
}
ditto "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE_ROOT/LICENSE" "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"
codesign --verify --deep --strict "$APP_DIR/Contents/Frameworks/Sparkle.framework"
otool -L "$APP_DIR/Contents/MacOS/FeatherSweep" | grep '@rpath/Sparkle.framework/' >/dev/null
otool -l "$APP_DIR/Contents/MacOS/FeatherSweep" | grep '@executable_path/../Frameworks' >/dev/null
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>轻扫</string>
    <key>CFBundleExecutable</key><string>FeatherSweep</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>io.github.zimuoo.FeatherSweep</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>轻扫</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.2.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSDesktopFolderUsageDescription</key>
    <string>扫描桌面下已批准项目的编译缓存和打包副本；仅在你点击“清理垃圾”后清理已确认的候选文件。</string>
</dict>
</plist>
PLIST
plutil -insert SUFeedURL -string "https://github.com/zimuoo/FeatherSweep/releases/latest/download/appcast-${TARGET_ARCH}.xml" "$APP_DIR/Contents/Info.plist"
plutil -insert SUPublicEDKey -string "$PUBLIC_KEY" "$APP_DIR/Contents/Info.plist"
for key in SUEnableAutomaticChecks SUAutomaticallyUpdate SUVerifyUpdateBeforeExtraction SURequireSignedFeed; do
    plutil -insert "$key" -bool true "$APP_DIR/Contents/Info.plist"
done
plutil -insert SUScheduledCheckInterval -integer 21600 "$APP_DIR/Contents/Info.plist"
plutil -insert SUSendProfileInfo -bool false "$APP_DIR/Contents/Info.plist"
plutil -lint "$APP_DIR/Contents/Info.plist"

echo "Signing locally (ad hoc; no Developer ID or Apple notarization)…"
codesign --force --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
ln -s /Applications "$PAYLOAD_DIR/Applications"

echo "Creating compressed drag-to-install disk image…"
hdiutil create -volname "$APP_NAME" -srcfolder "$PAYLOAD_DIR" -format UDZO \
    -imagekey zlib-level=9 -ov "$DMG_TEMP"
hdiutil verify "$DMG_TEMP"
# Both paths share a filesystem; mv replaces the final file atomically.
if [[ -d "$DIST_DIR/$DMG_NAME" ]]; then
    echo "Refusing to replace a directory at $DIST_DIR/$DMG_NAME" >&2
    exit 1
fi
mv -f "$DMG_TEMP" "$DIST_DIR/$DMG_NAME"

echo "Artifact: $DIST_DIR/$DMG_NAME"
echo "App size: $(du -sk "$APP_DIR" | awk '{print $1}') KiB on disk"
echo "DMG size: $(stat -f '%z' "$DIST_DIR/$DMG_NAME") bytes"
shasum -a 256 "$DIST_DIR/$DMG_NAME"

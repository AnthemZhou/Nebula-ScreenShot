#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${NEBULA_OUTPUT_DIR:-dist}"
# Sign outside synced folders, where Finder metadata may reappear after xattr cleanup.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nebula-build.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/Nebula ScreenShot.app"
if [[ "${1:-}" == "--universal" ]]; then
    swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64
    BIN_DIR="$(swift build -c "$CONFIGURATION" --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build -c "$CONFIGURATION"
    BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" .build/AppIcon.iconset
cp "$BIN_DIR/NebulaScreenShot" "$APP/Contents/MacOS/NebulaScreenShot"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
# Build outputs can inherit Finder metadata when the checkout is in a synced folder.
xattr -cr "$APP"
codesign --force --deep --sign "${CODE_SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$OUTPUT_DIR"
ditto --norsrc --noextattr --noqtn "$APP" "$OUTPUT_DIR/Nebula ScreenShot.app"
echo "Built: $OUTPUT_DIR/Nebula ScreenShot.app"

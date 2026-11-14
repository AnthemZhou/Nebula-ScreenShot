#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PACKAGE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nebula-package.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT
NEBULA_OUTPUT_DIR="$PACKAGE_DIR" ./scripts/build.sh "${@}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
if [[ "${1:-}" == "--universal" ]]; then ARCH=universal; else ARCH="$(uname -m)"; fi
ARCHIVE="dist/Nebula-ScreenShot-${VERSION}-${ARCH}.zip"
mkdir -p dist
# Finder / cloud-provider metadata is not part of the signed app and must not ship.
ditto -c -k --norsrc --noextattr --noqtn --keepParent "$PACKAGE_DIR/Nebula ScreenShot.app" "$ARCHIVE"
ditto --norsrc --noextattr --noqtn "$PACKAGE_DIR/Nebula ScreenShot.app" "dist/Nebula ScreenShot.app"
(cd dist && shasum -a 256 "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
echo "Packaged: $ARCHIVE"

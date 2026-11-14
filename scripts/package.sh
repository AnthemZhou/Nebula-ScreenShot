#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh "${@}"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
if [[ "${1:-}" == "--universal" ]]; then ARCH=universal; else ARCH="$(uname -m)"; fi
ARCHIVE="dist/Nebula-ScreenShot-${VERSION}-${ARCH}.zip"
# Finder / cloud-provider metadata is not part of the signed app and must not ship.
ditto -c -k --norsrc --noextattr --noqtn --keepParent "dist/Nebula ScreenShot.app" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "${ARCHIVE}.sha256"
echo "Packaged: $ARCHIVE"

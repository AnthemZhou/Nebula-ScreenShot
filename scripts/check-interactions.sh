#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nebula-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
CHECK_ARCH="$(uname -m)"
swiftc -swift-version 5 -target "$CHECK_ARCH-apple-macos14.0" -emit-library -emit-module \
    -module-name NebulaCore Sources/NebulaCore/*.swift \
    -emit-module-path "$CHECK_DIR/NebulaCore.swiftmodule" -o "$CHECK_DIR/libNebulaCore.dylib"
swiftc -swift-version 5 -target "$CHECK_ARCH-apple-macos14.0" \
    -I "$CHECK_DIR" -L "$CHECK_DIR" -lNebulaCore -Xlinker -rpath -Xlinker "$CHECK_DIR" \
    Sources/NebulaScreenShot/AnnotationToolbar.swift Sources/NebulaScreenShot/CaptureHint.swift Sources/NebulaScreenShot/CaptureCursor.swift \
    Sources/NebulaScreenShot/CaptureCanvas.swift Tests/InteractionChecks/main.swift \
    -o "$CHECK_DIR/interaction-checks"
"$CHECK_DIR/interaction-checks" "${1:-$CHECK_DIR/result.png}"

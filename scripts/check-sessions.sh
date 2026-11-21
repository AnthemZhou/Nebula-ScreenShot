#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nebula-sessions.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
CHECK_ARCH="$(uname -m)"
swiftc -swift-version 5 -target "$CHECK_ARCH-apple-macos14.0" -emit-library -emit-module \
    -module-name NebulaCore Sources/NebulaCore/*.swift \
    -emit-module-path "$CHECK_DIR/NebulaCore.swiftmodule" -o "$CHECK_DIR/libNebulaCore.dylib"
swiftc -swift-version 5 -target "$CHECK_ARCH-apple-macos14.0" \
    -I "$CHECK_DIR" -L "$CHECK_DIR" -lNebulaCore -Xlinker -rpath -Xlinker "$CHECK_DIR" \
    Sources/NebulaScreenShot/{HotKey,GlassShader,GlassMetalRenderer,AnnotationToolbar,CaptureHint,CaptureCursor,CaptureCanvas,DemoArtwork,CaptureExclusion,CaptureSource,CaptureCoordinator}.swift \
    Tests/SessionChecks/main.swift -o "$CHECK_DIR/session-checks"
"$CHECK_DIR/session-checks"

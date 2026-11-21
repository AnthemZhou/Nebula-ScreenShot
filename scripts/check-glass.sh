#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nebula-glass-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
swiftc -swift-version 5 -target "$(uname -m)-apple-macos14.0" -emit-library -emit-module \
    -module-name NebulaCore Sources/NebulaCore/*.swift \
    -emit-module-path "$CHECK_DIR/NebulaCore.swiftmodule" -o "$CHECK_DIR/libNebulaCore.dylib"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
    -I "$CHECK_DIR" -L "$CHECK_DIR" -lNebulaCore -Xlinker -rpath -Xlinker "$CHECK_DIR" \
    Sources/NebulaScreenShot/{GlassShader,GlassMetalRenderer,AnnotationToolbar}.swift \
    Tests/GlassChecks/main.swift -o "$CHECK_DIR/glass-checks"
"$CHECK_DIR/glass-checks" "${1:-$CHECK_DIR/results}"

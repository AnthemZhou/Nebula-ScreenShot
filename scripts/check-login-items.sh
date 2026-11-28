#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nebula-login-checks.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
CHECK_ARCH="$(uname -m)"
swiftc -swift-version 5 -target "$CHECK_ARCH-apple-macos14.0" \
    Sources/NebulaScreenShot/LoginItemController.swift Tests/LoginItemChecks/main.swift \
    -o "$CHECK_DIR/login-checks"
"$CHECK_DIR/login-checks"

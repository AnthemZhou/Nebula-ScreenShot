#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Own-process metadata only; no screen capture, consent prompts or posted input."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import uuid

repo = Path(__file__).resolve().parent.parent
root = Path(tempfile.mkdtemp(prefix="nebula-exclusion-check-"))
app = root / "Exclusion Fixture.app"
output = root / "result.txt"
(app / "Contents/MacOS").mkdir(parents=True)
try:
    with (app / "Contents/Info.plist").open("wb") as file:
        plistlib.dump({
            "CFBundleIdentifier": "io.github.anthemzhou.NebulaExclusionFixture." + uuid.uuid4().hex,
            "CFBundleExecutable": "ExclusionFixture", "CFBundleName": "Exclusion Fixture",
            "CFBundlePackageType": "APPL", "LSUIElement": True, "FixtureResultPath": str(output)
        }, file)
    subprocess.run([
        "swiftc", "-swift-version", "5",
        str(repo / "Sources/NebulaScreenShot/CaptureExclusion.swift"),
        str(repo / "Tests/CaptureExclusionChecks/main.swift"),
        "-o", str(app / "Contents/MacOS/ExclusionFixture")
    ], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True)
    subprocess.run(["open", "-g", str(app)], check=True)
    deadline = time.monotonic() + 15
    while not output.exists() and time.monotonic() < deadline:
        time.sleep(0.1)
    result = output.read_text() if output.exists() else "FAIL: metadata fixture timed out"
    print(result)
    if not result.startswith(("PASS:", "SKIP:")):
        raise SystemExit(1)
finally:
    subprocess.run([
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        "-u", str(app)
    ], capture_output=True)
    shutil.rmtree(root)

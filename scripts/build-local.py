#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Build for this Mac with a pinned Apple Development identity; never fall back to ad-hoc."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "io.github.anthemzhou.NebulaScreenShot"
STATE = Path.home() / "Library/Application Support/Nebula ScreenShot/LocalSigning.json"


def run(*args):
    result = subprocess.run(args, check=True, text=True, capture_output=True)
    return result.stdout + result.stderr


def development_identities(output):
    return {fingerprint.upper(): name for fingerprint, name in
            re.findall(r'\b([0-9A-Fa-f]{40}) "(Apple Development:[^"\n]+)"', output)}


def select_identity(identities, requested, saved):
    requested = requested.upper() if requested else None
    pinned = saved.get("identity")
    if pinned and requested and requested != pinned:
        raise ValueError("This Mac already has a pinned signing identity. Refusing to change it silently.")
    selected = pinned or requested
    if selected is None:
        if len(identities) != 1:
            raise ValueError("Create an Apple Development certificate in Xcode → Settings → Accounts → "
                             "Manage Certificates. If several exist, use --identity with its SHA-1 fingerprint.")
        selected = next(iter(identities))
    if selected not in identities:
        raise ValueError("The requested/pinned Apple Development identity is unavailable or expired. "
                         "No build was started; ad-hoc fallback is disabled.")
    return selected


def read_state(path):
    if not path.exists():
        return {}
    state = json.loads(path.read_text())
    if (not isinstance(state, dict) or state.get("format") != 1 or
            re.fullmatch(r"[0-9A-F]{40}", state.get("identity", "")) is None or
            not isinstance(state.get("requirements"), dict) or not state["requirements"] or
            any(arch not in ("arm64", "x86_64") or not isinstance(req, str) or not req.strip()
                for arch, req in state["requirements"].items())):
        raise ValueError("Invalid local signing record; refusing to discard the previous identity.")
    return state


def verify_app(app, previous):
    with (app / "Contents/Info.plist").open("rb") as f:
        info = plistlib.load(f)
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("CFBundleExecutable") != "NebulaScreenShot":
        raise ValueError("Unexpected app identity.")
    # Validate Apple's certificate chain, not merely a certificate name or bundle identifier.
    run("/usr/bin/codesign", "--verify", "--strict", "--all-architectures",
        '-R=anchor apple generic and identifier "' + BUNDLE_ID + '"', str(app))
    architectures = run("/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/NebulaScreenShot")).split()
    if set(architectures) != {"arm64", "x86_64"}:
        raise ValueError("Expected a universal app.")
    requirements = {}
    for arch in architectures:
        details = run("/usr/bin/codesign", "-d", "--verbose=4", "-r-", "--arch", arch, str(app))
        requirement = re.search(r"^(?:# )?designated => (.+)$", details, re.MULTILINE)
        if ("Signature=adhoc" in details or "Authority=Apple Development:" not in details or
                not re.search(r"^TeamIdentifier=[A-Z0-9]{10}$", details, re.MULTILINE) or
                not requirement or re.search(r"\bcdhash\b", requirement.group(1))):
            raise ValueError("The built app lacks a stable Apple Development signature.")
        requirements[arch] = requirement.group(1)
        if previous:
            if arch not in previous:
                raise ValueError("The previous signing record is missing an architecture.")
            # TCC records the old designated requirement. The new code must satisfy it.
            run("/usr/bin/codesign", "--verify", "--strict", "--arch", arch,
                "-R=" + previous[arch], str(app))
    return requirements


def save_state(path, identity, requirements):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".signing-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump({"format": 1, "identity": identity, "requirements": requirements}, f, indent=2)
            f.write("\n")
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--identity", help="Apple Development certificate SHA-1 fingerprint (first setup only)")
    parser.add_argument("--check", action="store_true", help="Check certificate availability without building or changing anything")
    args = parser.parse_args()
    state = read_state(STATE)
    identities = development_identities(run("/usr/bin/security", "find-identity", "-v", "-p", "codesigning"))
    identity = select_identity(identities, args.identity, state)
    print("Apple Development identity is available.", flush=True)
    if args.check:
        return
    # Keep signed local output outside cloud-synced checkouts, where Finder metadata
    # can reappear after packaging and invalidate a strict signature verification.
    destination = STATE.parent / "LocalBuild/Nebula ScreenShot.app"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".nebula-local-build-", dir=destination.parent) as directory:
        env = dict(os.environ, CODE_SIGN_IDENTITY=identity, NEBULA_OUTPUT_DIR=directory)
        subprocess.run([str(ROOT / "scripts/build.sh"), "--universal"], cwd=ROOT, env=env, check=True)
        app = Path(directory) / "Nebula ScreenShot.app"
        requirements = verify_app(app, state.get("requirements", {}))
        # Keep the public release and installed application untouched.
        backup = Path(directory) / "Previous.app"
        if destination.exists():
            destination.rename(backup)
        try:
            app.rename(destination)
            verify_app(destination, requirements)
            save_state(STATE, identity, requirements)
        except Exception:
            if destination.exists():
                destination.rename(app)
            if backup.exists():
                backup.rename(destination)
            raise
    print(f"Built and checked: {destination}")
    print("Install in the same Applications location. Initial migration may require consent once.")
    print("This is a local development build, not a notarized distribution package.")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        detail = (error.stderr or error.stdout or str(error)) if isinstance(error, subprocess.CalledProcessError) else str(error)
        raise SystemExit(f"Local signing stopped: {detail}")

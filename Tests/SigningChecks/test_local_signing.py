# SPDX-License-Identifier: GPL-3.0-only
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("local_signing", ROOT / "scripts/build-local.py")
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
FIRST, SECOND = "A" * 40, "B" * 40
REQUIREMENTS = {arch: 'identifier "io.github.anthemzhou.NebulaScreenShot" and anchor apple generic'
                for arch in ("arm64", "x86_64")}


class LocalSigningChecks(unittest.TestCase):
    def test_only_valid_development_identity_listing_is_selected(self):
        listing = f'  1) {FIRST} "Apple Development: Test (1234567890)"\n'
        listing += f'  2) {SECOND} "Developer ID Application: Test (1234567890)"\n'
        listing += '  2 valid identities found\n'
        identities = signing.development_identities(listing)
        self.assertEqual(set(identities), {FIRST})
        self.assertEqual(signing.select_identity(identities, None, {}), FIRST)

    def test_missing_certificate_never_falls_back_to_ad_hoc(self):
        with self.assertRaises(ValueError):
            signing.select_identity({}, None, {})
        with self.assertRaises(ValueError):
            signing.select_identity({SECOND: "another"}, None, {"identity": FIRST})

    def test_multiple_certificates_require_a_deliberate_choice(self):
        identities = {FIRST: "one", SECOND: "two"}
        with self.assertRaises(ValueError):
            signing.select_identity(identities, None, {})
        self.assertEqual(signing.select_identity(identities, SECOND.lower(), {}), SECOND)

    def test_pinned_certificate_wins_and_cannot_be_silently_replaced(self):
        identities = {FIRST: "one", SECOND: "two"}
        self.assertEqual(signing.select_identity(identities, None, {"identity": FIRST}), FIRST)
        with self.assertRaises(ValueError):
            signing.select_identity(identities, SECOND, {"identity": FIRST})

    def test_record_preserves_previous_requirements(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "signing.json"
            self.assertEqual(signing.read_state(path), {})
            signing.save_state(path, FIRST, REQUIREMENTS)
            state = signing.read_state(path)
            self.assertEqual(state["identity"], FIRST)
            self.assertEqual(state["requirements"], REQUIREMENTS)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)

    def test_corrupt_record_cannot_reset_the_signing_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "signing.json"
            for value in ([], {}, {"format": 1, "identity": FIRST, "requirements": {}},
                          {"format": 1, "identity": FIRST, "requirements": {"arm64": None}}):
                path.write_text(json.dumps(value))
                with self.assertRaises(ValueError):
                    signing.read_state(path)

    @unittest.skipUnless(os.environ.get("NEBULA_SIGNING_CHECK_APP"), "Requires the ad-hoc CI app fixture")
    def test_real_ad_hoc_app_is_rejected_by_apple_signature_check(self):
        source = Path(os.environ["NEBULA_SIGNING_CHECK_APP"])
        self.assertTrue(source.is_dir())
        with tempfile.TemporaryDirectory(prefix="nebula-signature-check-") as directory:
            app = Path(directory) / "Nebula ScreenShot.app"
            signing.run("/usr/bin/ditto", "--norsrc", "--noextattr", "--noqtn", str(source), str(app))
            signing.run("/usr/bin/codesign", "--verify", "--strict", "--all-architectures", str(app))
            details = signing.run("/usr/bin/codesign", "-d", "--verbose=4", str(app))
            self.assertIn("Signature=adhoc", details)
            with self.assertRaises(subprocess.CalledProcessError) as raised:
                signing.verify_app(app, {})
            self.assertIn("code requirement", raised.exception.stderr)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Exercise the release gate with deliberately contaminated fixture bundles."""
import pathlib
import tempfile
import unittest
from privacy_check import FILES, LINKS, audit_bundle


class PrivacyGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = pathlib.Path(self.temporary.name) / "Halo.app"
        for name in FILES:
            path = self.app / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture")
        for name, target in LINKS.items():
            (self.app / name).symlink_to(target)

    def test_clean_bundle_passes(self):
        audit_bundle(self.app)

    def test_embedded_build_path_is_rejected_without_echoing_value(self):
        (self.app / "Contents/MacOS/Halo").write_bytes(b"/Users/test-account/project/file.o")
        with self.assertRaises(ValueError) as error:
            audit_bundle(self.app)
        self.assertIn("local home/build path", str(error.exception))
        self.assertNotIn("test-account", str(error.exception))

    def test_unexpected_preferences_are_rejected(self):
        (self.app / "Contents/Resources/preferences.plist").write_bytes(b"fixture")
        with self.assertRaisesRegex(ValueError, "unexpected file"):
            audit_bundle(self.app)

    def test_external_symlink_is_rejected(self):
        link = self.app / next(iter(LINKS))
        link.unlink()
        link.symlink_to(self.temporary.name)
        with self.assertRaisesRegex(ValueError, "unexpected symlink"):
            audit_bundle(self.app)

    def test_credential_is_rejected_without_echoing_value(self):
        token = b"ghp_" + b"a" * 36
        (self.app / "Contents/MacOS/Halo").write_bytes(token)
        with self.assertRaises(ValueError) as error:
            audit_bundle(self.app)
        self.assertIn("GitHub credential", str(error.exception))
        self.assertNotIn(token.decode(), str(error.exception))

    def test_missing_payload_is_rejected(self):
        (self.app / "Contents/Resources/Halo.icns").unlink()
        with self.assertRaisesRegex(ValueError, "missing release payload"):
            audit_bundle(self.app)


if __name__ == "__main__":
    unittest.main()

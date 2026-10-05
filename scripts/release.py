#!/usr/bin/env python3
"""Package an already built Halo.app; notarize only with an explicit profile."""
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
import tempfile
from privacy_check import audit_bundle

ROOT = pathlib.Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
APP = DIST / "Halo.app"
VERSION = "1.4.0"
STEM = f"Halo-{VERSION}-macOS-arm64"


def run(*args, capture=False):
    result = subprocess.run([str(arg) for arg in args], check=True, text=True,
                            stdout=subprocess.PIPE if capture else None,
                            stderr=subprocess.PIPE if capture else None)
    return (result.stdout + result.stderr) if capture else ""


def verify(app):
    with (app / "Contents/Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if (info.get("CFBundleIdentifier"), info.get("CFBundleShortVersionString"), info.get("CFBundleVersion")) != ("dev.kevin.halo", VERSION, "6"):
        raise ValueError("Expected Halo 1.4.0 build 6 (dev.kevin.halo); run scripts/build.sh")
    audit_bundle(app)
    if (info.get("CFBundleExecutable"), info.get("LSMinimumSystemVersion"), info.get("LSUIElement")) != ("Halo", "14.2", True):
        raise ValueError("Unexpected executable, minimum macOS version, or menu-bar app metadata")
    run("codesign", "--verify", "--deep", "--strict", app)
    signature = run("codesign", "--display", "--verbose=4", app, capture=True)
    if "Identifier=dev.kevin.halo\n" not in signature:
        raise ValueError("Unexpected code-signing identifier")
    adhoc = "Signature=adhoc" in signature
    if not adhoc and "Authority=Developer ID Application:" not in signature:
        raise ValueError("Release requires ad hoc or Developer ID Application signing")
    for executable in ["MacOS/Halo", "MacOS/MediaRemoteAdapterTestClient",
                       "Frameworks/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"]:
        architectures = run("lipo", "-archs", app / "Contents" / executable, capture=True).strip().split()
        if architectures != ["arm64"]:
            raise ValueError(f"Expected arm64 in {executable}, found {architectures}")
        # Reject accidental Homebrew/build-machine linkage in a portable app.
        dependencies = run("otool", "-L", app / "Contents" / executable, capture=True)
        for line in dependencies.splitlines()[1:]:
            dependency = line.strip().split(" (", 1)[0]
            if not dependency.startswith(("/System/Library/", "/usr/lib/", "@rpath/", "@loader_path/", "@executable_path/")):
                raise ValueError(f"Nonportable dependency in {executable}: {dependency}")
        nested_signature = run("codesign", "--display", "--verbose=4", app / "Contents" / executable, capture=True)
        if adhoc != ("Signature=adhoc" in nested_signature):
            raise ValueError(f"Mixed ad hoc and identity signing in {executable}")
        if not adhoc and ("Authority=Developer ID Application:" not in nested_signature or "runtime" not in nested_signature):
            raise ValueError(f"Developer ID and hardened runtime required in {executable}")
    for resource in ["mediaremote-adapter.pl", "MediaRemoteAdapter-LICENSE.txt", "Halo.icns"]:
        if not (app / "Contents/Resources" / resource).is_file():
            raise ValueError(f"Missing portable resource: {resource}")
    return adhoc


def archive(app, output):
    run("ditto", "-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--keepParent", app, output)


def notarize(path, profile):
    result = subprocess.run(["xcrun", "notarytool", "submit", str(path),
                             "--keychain-profile", profile, "--wait", "--output-format", "json"],
                            check=True, text=True, capture_output=True)
    response = json.loads(result.stdout)
    if response.get("status") != "Accepted":
        raise RuntimeError(f"Notarization failed: {response.get('status')} (submission {response.get('id')})")


def main():
    adhoc = verify(APP)
    profile = os.environ.get("HALO_NOTARY_PROFILE", "").strip()
    if profile and adhoc:
        raise ValueError("Notarization requires Developer ID signing; this app is ad hoc signed")
    identity = os.environ.get("HALO_SIGNING_IDENTITY", "").strip()
    if profile and (not identity or identity == "-"):
        raise ValueError("Set HALO_SIGNING_IDENTITY to sign the notarized DMG")
    if profile:
        signature = run("codesign", "--display", "--verbose=4", APP, capture=True)
        if "Authority=Developer ID Application:" not in signature:
            raise ValueError("Notarization requires a Developer ID Application identity")
    DIST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="release-", dir=DIST) as temporary:
        work = pathlib.Path(temporary)
        image_root = work / "image"
        image_root.mkdir()
        packaged = image_root / "Halo.app"
        run("ditto", APP, packaged)
        verify(packaged)
        if profile:
            submission = work / "notary-submission.zip"
            archive(packaged, submission)
            notarize(submission, profile)
            run("xcrun", "stapler", "staple", packaged)
            run("xcrun", "stapler", "validate", packaged)
        (image_root / "Applications").symlink_to("/Applications")
        status = ("Ad hoc signed locally; not notarized. macOS may block a downloaded copy."
                  if adhoc else ("Developer ID signed and notarized." if profile else "Developer ID signed; not notarized."))
        (image_root / "README.txt").write_text(
            f"Halo {VERSION} — macOS 14.2 or later, Apple silicon (arm64).\n\n"
            "Quit any running Halo before installing. Drag Halo.app to Applications, then open it.\n"
            "Halo runs in the menu bar. Open Settings from its menu to configure the island and login startup.\n\n"
            f"{status}\n", encoding="utf-8")
        zipped = work / f"{STEM}.zip"
        dmg = work / f"{STEM}.dmg"
        archive(packaged, zipped)
        run("hdiutil", "create", "-volname", f"Halo {VERSION}", "-srcfolder", image_root,
            "-format", "UDZO", dmg)
        if profile:
            run("codesign", "--force", "--sign", identity, "--timestamp", dmg)
            notarize(dmg, profile)
            run("xcrun", "stapler", "staple", dmg)
            run("xcrun", "stapler", "validate", dmg)
        sums = work / "SHA256SUMS.txt"
        sums.write_text("".join(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
                                for path in [zipped, dmg]), encoding="ascii")
        for path in [zipped, dmg, sums]:
            os.replace(path, DIST / path.name)
    print(f"Created {DIST / (STEM + '.zip')} and {DIST / (STEM + '.dmg')}")
    print("Ad hoc signed (not notarized)." if adhoc else
          ("Developer ID signed and notarized." if profile else "Developer ID signed; not notarized."))


if __name__ == "__main__":
    main()

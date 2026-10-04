#!/usr/bin/env python3
"""Build the pinned adapter from source and assemble a self-contained local app."""
import os
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import uuid

ROOT = pathlib.Path(__file__).resolve().parent.parent
(ROOT / ".build").mkdir(parents=True, exist_ok=True)
STAGING = pathlib.Path(tempfile.mkdtemp(prefix="bundle-", dir=ROOT / ".build"))
APP = STAGING / "Halo.app"
FINAL_APP = ROOT / "dist/Halo.app"
CONTENTS = APP / "Contents"
VENDOR = ROOT / "Vendor/mediaremote-adapter"
FRAMEWORK = CONTENTS / "Frameworks/MediaRemoteAdapter.framework"
VERSION = FRAMEWORK / "Versions/A"

def run(*args):
    subprocess.run([str(a) for a in args], check=True, cwd=ROOT)

try:
    for directory in (CONTENTS / "MacOS", CONTENTS / "Resources", VERSION / "Resources"):
        directory.mkdir(parents=True, exist_ok=True)

    with (CONTENTS / "Info.plist").open("wb") as file:
        plistlib.dump({
            "CFBundleName": "Halo", "CFBundleDisplayName": "Halo",
            "CFBundleIdentifier": "dev.kevin.halo", "CFBundleExecutable": "Halo",
            "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.3.0",
            "CFBundleVersion": "4", "LSMinimumSystemVersion": "14.2",
            "LSUIElement": True, "NSHighResolutionCapable": True,
            "NSAudioCaptureUsageDescription": "Halo uses system audio samples to display an accurate live waveform. Audio is never recorded or saved.",
            "NSCameraUsageDescription": "Halo shows a live mirrored camera preview in the notch. Video is never recorded or saved.",
            "NSAppleEventsUsageDescription": "Halo can optionally read track details and control Apple Music and Spotify when system media information is unavailable.",
            "NSPrincipalClass": "NSApplication", "CFBundleIconFile": "Halo.icns",
        }, file)

    with (VERSION / "Resources/Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": "dev.kevin.halo.MediaRemoteAdapter", "CFBundleExecutable": "MediaRemoteAdapter", "CFBundlePackageType": "FMWK", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "CFBundleName": "MediaRemoteAdapter"}, file)

    for link, target in ((FRAMEWORK / "Versions/Current", "A"), (FRAMEWORK / "MediaRemoteAdapter", "Versions/Current/MediaRemoteAdapter"), (FRAMEWORK / "Resources", "Versions/Current/Resources")):
        if not link.is_symlink():
            link.symlink_to(target)

    sources = sorted((VENDOR / "src/adapter").glob("*.m")) + sorted((VENDOR / "src/private").glob("*.m")) + sorted((VENDOR / "src/utility").glob("*.m"))
    run("xcrun", "clang", "-dynamiclib", "-fobjc-arc", "-fvisibility=default", "-mmacosx-version-min=14.2", "-O2",
        "-I", VENDOR / "include", "-I", VENDOR / "src", *sources,
        "-framework", "Foundation", "-framework", "AppKit", "-framework", "UniformTypeIdentifiers",
        "-install_name", "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter",
        "-o", VERSION / "MediaRemoteAdapter")
    run("xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=14.2", "-O2",
        VENDOR / "src/test/main.m", VENDOR / "src/test/NowPlayingTest.m",
        "-I", VENDOR / "src/test", "-framework", "Foundation", "-framework", "MediaPlayer",
        "-o", CONTENTS / "MacOS/MediaRemoteAdapterTestClient")

    bin_path = subprocess.check_output(["swift", "build", "-c", "release", "--show-bin-path"], cwd=ROOT, text=True).strip()
    shutil.copy2(pathlib.Path(bin_path) / "Halo", CONTENTS / "MacOS/Halo")
    shutil.copy2(VENDOR / "bin/mediaremote-adapter.pl", CONTENTS / "Resources/mediaremote-adapter.pl")
    shutil.copy2(VENDOR / "LICENSE", CONTENTS / "Resources/MediaRemoteAdapter-LICENSE.txt")

    icon_dir = ROOT / ".build/Halo.iconset"
    icon_dir.mkdir(parents=True, exist_ok=True)
    run("swift", ROOT / "scripts/icon.swift", icon_dir)
    run("iconutil", "-c", "icns", icon_dir, "-o", CONTENTS / "Resources/Halo.icns")
    # Swift release binaries can retain object/source paths in debug symbols.
    # Remove them before signing, and do not ship local extended attributes.
    for executable in (CONTENTS / "MacOS/Halo", CONTENTS / "MacOS/MediaRemoteAdapterTestClient", VERSION / "MediaRemoteAdapter"):
        run("xcrun", "strip", "-S", executable)
    run("xattr", "-cr", APP)
    identity = os.environ.get("HALO_SIGNING_IDENTITY", "-").strip()
    if not identity:
        raise ValueError("HALO_SIGNING_IDENTITY must be '-' or a signing identity")
    signing = ["codesign", "--force", "--sign", identity]
    if identity != "-":
        signing += ["--timestamp", "--options", "runtime"]
    run(*signing, FRAMEWORK)
    run(*signing, CONTENTS / "MacOS/MediaRemoteAdapterTestClient")
    run(*signing, "--entitlements", ROOT / "scripts/Halo.entitlements", APP)
    run("codesign", "--verify", "--deep", "--strict", APP)
    run("python3", ROOT / "scripts/privacy_check.py", APP)
    FINAL_APP.parent.mkdir(parents=True, exist_ok=True)
    previous = None
    if FINAL_APP.exists():
        # Keep old executable inodes for processes still running the previous build.
        preserved = ROOT / ".build/previous-apps"
        preserved.mkdir(parents=True, exist_ok=True)
        previous = preserved / f"Halo-{uuid.uuid4().hex}.app"
        FINAL_APP.rename(previous)
    try:
        APP.rename(FINAL_APP)
    except BaseException:
        if previous is not None:
            previous.rename(FINAL_APP)
        raise
    print(f"\nBuilt {FINAL_APP}\nOpen it with: open '{FINAL_APP}'")
finally:
    shutil.rmtree(STAGING, ignore_errors=True)

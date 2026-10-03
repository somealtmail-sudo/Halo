#!/usr/bin/env python3
"""Opt-in audible integration check: quiet tone/silence, actual Core Audio tap."""
import pathlib
import plistlib
import re
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = ROOT / ".build/HaloAudioFixture.app/Contents"
FIXTURE.mkdir(parents=True, exist_ok=True)
(FIXTURE / "MacOS").mkdir(exist_ok=True)
with (FIXTURE / "Info.plist").open("wb") as file:
    plistlib.dump({"CFBundleIdentifier": "dev.kevin.halo.audiofixture", "CFBundleExecutable": "HaloAudioFixture", "CFBundleName": "Halo Audio Fixture", "CFBundlePackageType": "APPL", "LSUIElement": True}, file)
subprocess.run(["xcrun", "swiftc", str(ROOT / "scripts/AudioFixture.swift"), "-o", str(FIXTURE / "MacOS/HaloAudioFixture")], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(FIXTURE.parent)], check=True)
fixture = subprocess.Popen([str(FIXTURE / "MacOS/HaloAudioFixture"), "--waveform-tone"])
try:
    time.sleep(0.5)
    result = subprocess.run([str(ROOT / "dist/Halo.app/Contents/MacOS/Halo"), "--waveform-diagnostics"], capture_output=True, text=True, timeout=20, check=True)
    print(result.stdout)
    match = re.search(r"peak: ([\d.eE+-]+); changed frames: (\d+)", result.stdout)
    assert match and float(match[1]) > 0 and int(match[2]) > 10, "No changing samples received. Check system audio permission and output routing."
    assert "Capture released; flat: true" in result.stdout
    print("PASS: real tone drives waveform; capture cleanup clears history")
finally:
    fixture.terminate()
    try:
        fixture.wait(timeout=3)
    except subprocess.TimeoutExpired:
        fixture.kill()
        fixture.wait()

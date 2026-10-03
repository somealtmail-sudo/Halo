#!/usr/bin/env python3
"""Local, silent end-to-end checks against real macOS audio and Now Playing."""
import json
import os
import pathlib
import plistlib
import re
import signal
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTENTS = ROOT / "dist/Halo.app/Contents"
FIXTURE = ROOT / ".build/HaloAudioFixture.app/Contents"
FIXTURE_ID = "dev.kevin.halo.audiofixture"
ADAPTER = ["/usr/bin/perl", str(CONTENTS / "Resources/mediaremote-adapter.pl"), str(CONTENTS / "Frameworks/MediaRemoteAdapter.framework")]

def run(args):
    return subprocess.run([str(a) for a in args], check=True, text=True, capture_output=True, timeout=30).stdout

def read():
    return json.loads(run(ADAPTER + ["get", "--micros", "--no-artwork"]))

def wait_for(predicate):
    deadline = time.monotonic() + 8
    last = None
    while time.monotonic() < deadline:
        last = read()
        if last and last.get("bundleIdentifier") == FIXTURE_ID and predicate(last):
            return last
        time.sleep(0.2)
    raise AssertionError(f"Expected fixture state did not arrive; last source: {(last or {}).get('bundleIdentifier')}")

def launch(*args):
    child = subprocess.Popen([str(FIXTURE / "MacOS/HaloAudioFixture"), *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    time.sleep(1.5)
    if child.poll() is not None:
        raise RuntimeError(child.stderr.read())
    return child

def stop(child):
    child.terminate()
    try: child.wait(timeout=3)
    except subprocess.TimeoutExpired: child.kill(); child.wait()

(FIXTURE / "MacOS").mkdir(parents=True, exist_ok=True)
with (FIXTURE / "Info.plist").open("wb") as file:
    plistlib.dump({"CFBundleIdentifier": FIXTURE_ID, "CFBundleExecutable": "HaloAudioFixture", "CFBundleName": "Halo Audio Fixture", "CFBundlePackageType": "APPL", "LSUIElement": True}, file)
run(["xcrun", "swiftc", ROOT / "scripts/AudioFixture.swift", "-o", FIXTURE / "MacOS/HaloAudioFixture"])
run(["codesign", "--force", "--sign", "-", FIXTURE.parent])

fixture = launch()
try:
    output = run([CONTENTS / "MacOS/Halo", "--diagnostics"])
    assert "Halo Audio Fixture" in output or "HaloAudioFixture" in output or FIXTURE_ID in output, output
    print("PASS: CoreAudio detects a real output-IO process without Now Playing metadata")
finally:
    stop(fixture)

fixture = launch("--metadata")
try:
    wait_for(lambda value: value.get("title") == "Halo Integration Test" and value.get("playing") is True)
    print("PASS: system Now Playing receives metadata from an independent player")
    run(ADAPTER + ["send", "2"])
    wait_for(lambda value: value.get("playing") is False)
    print("PASS: play/pause command reaches the player")
    run(ADAPTER + ["seek", "90000000"])
    wait_for(lambda value: abs(value.get("elapsedTimeMicros", 0) - 90_000_000) < 1_000_000)
    print("PASS: seeking uses the correct microsecond units")
    run(ADAPTER + ["send", "4"])
    wait_for(lambda value: value.get("title") == "Halo Next Track")
    run(ADAPTER + ["send", "5"])
    wait_for(lambda value: value.get("title") == "Halo Integration Test")
    print("PASS: next/previous commands and track changes")
finally:
    stop(fixture)

app_executable = str(CONTENTS / "MacOS/Halo")

def process_identity(pid):
    result = subprocess.run(["ps", "-p", str(pid), "-o", "lstart=", "-o", "command="],
                            capture_output=True, text=True, timeout=5)
    if result.returncode == 1: return None
    result.check_returncode()
    return result.stdout.strip() or None

def lifecycle_check(stall_helper=False):
    app = subprocess.Popen([app_executable], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    owned_helpers = {}
    try:
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            result = subprocess.run(["pgrep", "-P", str(app.pid), "-f", re.escape(str(CONTENTS / "Resources/mediaremote-adapter.pl"))],
                                    capture_output=True, text=True, timeout=5)
            assert result.returncode in (0, 1), result.stderr
            for pid in map(int, result.stdout.split()):
                identity = process_identity(pid)
                if identity: owned_helpers[pid] = identity
            if owned_helpers: break
            assert app.poll() is None, "Halo exited before its media helper started"
            time.sleep(0.1)
        assert owned_helpers, "Halo did not start its media helper"
        if stall_helper:
            for pid, identity in owned_helpers.items():
                assert process_identity(pid) == identity, "Media helper exited before the stall check"
                os.kill(pid, signal.SIGSTOP)
            deadline = time.monotonic() + 1
            while time.monotonic() < deadline:
                states = [run(["ps", "-p", str(pid), "-o", "stat="]).strip() for pid in owned_helpers]
                if all("T" in state for state in states): break
                time.sleep(0.01)
            assert all("T" in state for state in states), "Could not confirm the owned helper was suspended"
        started = time.monotonic()
        deadline = started + 3
        app.terminate()
        app.wait(timeout=max(0.01, deadline - time.monotonic()))
        def remaining_helpers():
            return [pid for pid, identity in owned_helpers.items() if process_identity(pid) == identity]
        while remaining_helpers() and time.monotonic() < deadline:
            time.sleep(0.05)
        assert not remaining_helpers(), "A media helper survived Halo shutdown"
        elapsed = time.monotonic() - started
        assert elapsed <= 3, f"Halo/helper shutdown exceeded the 3-second bound: {elapsed:.2f}s"
        label = "SIGSTOP-stalled" if stall_helper else "running"
        print(f"PASS: SIGTERM shuts down Halo and its {label} media helper in {elapsed:.2f}s")
    finally:
        # Only touch children discovered under this Popen PID, and retain their
        # original start time/command so a recycled PID cannot target another app.
        for pid, identity in owned_helpers.items():
            if process_identity(pid) == identity:
                try: os.kill(pid, signal.SIGCONT)
                except ProcessLookupError: pass
        if app.poll() is None: stop(app)
        for pid, identity in owned_helpers.items():
            if process_identity(pid) == identity:
                try: os.kill(pid, signal.SIGKILL)
                except ProcessLookupError: pass
        app.stdout.close()
        app.stderr.close()

# Include the installed copy as well as dist; never launch a competing Halo.
existing = subprocess.run(["pgrep", "-x", "Halo"], capture_output=True, text=True, timeout=5)
if existing.returncode == 1:
    lifecycle_check()
    lifecycle_check(stall_helper=True)
else:
    print("SKIP: lifecycle check (Halo is already running or process enumeration unavailable)")
print("All local integration checks passed.")

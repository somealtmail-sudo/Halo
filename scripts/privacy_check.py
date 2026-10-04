#!/usr/bin/env python3
"""Fail packaging on unexpected payloads, local paths, or common credentials.

This is a release regression gate, not a complete secret detector or security audit.
Only categories and relative filenames are reported, never matched values.
"""
import argparse
import pathlib
import re

FRAMEWORK = "Contents/Frameworks/MediaRemoteAdapter.framework/"
FILES = {
    "Contents/Info.plist", "Contents/_CodeSignature/CodeResources",
    "Contents/MacOS/Halo", "Contents/MacOS/MediaRemoteAdapterTestClient",
    "Contents/Resources/Halo.icns", "Contents/Resources/mediaremote-adapter.pl",
    "Contents/Resources/MediaRemoteAdapter-LICENSE.txt",
    FRAMEWORK + "Versions/A/MediaRemoteAdapter",
    FRAMEWORK + "Versions/A/Resources/Info.plist",
    FRAMEWORK + "Versions/A/_CodeSignature/CodeResources",
}
LINKS = {
    FRAMEWORK + "Versions/Current": "A",
    FRAMEWORK + "MediaRemoteAdapter": "Versions/Current/MediaRemoteAdapter",
    FRAMEWORK + "Resources": "Versions/Current/Resources",
}
PATTERNS = {
    "local home/build path": rb"/(?:Users|home)/[^/\x00\s]+/|/private/var/folders/|[A-Za-z]:\\Users\\",
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----",
    "GitHub credential": rb"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b",
    "AWS access key": rb"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b",
    "API credential": rb"\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{32,}\b",
    "Slack credential": rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b",
}


def audit_bundle(app):
    app = pathlib.Path(app)
    if not app.is_dir() or app.is_symlink():
        raise ValueError("Expected a real app bundle directory")
    seen = set()
    issues = []
    for path in app.rglob("*"):
        relative = path.relative_to(app).as_posix()
        if path.is_symlink():
            seen.add(relative)
            if relative not in LINKS or str(path.readlink()) != LINKS[relative] or not path.exists():
                issues.append(f"unexpected symlink: {relative}")
        elif path.is_file():
            seen.add(relative)
            if relative not in FILES:
                issues.append(f"unexpected file: {relative}")
            data = path.read_bytes()
            for category, pattern in PATTERNS.items():
                if re.search(pattern, data):
                    issues.append(f"{category}: {relative}")
        elif not path.is_dir():
            issues.append(f"unexpected filesystem entry: {relative}")
    for missing in (FILES | LINKS.keys()) - seen:
        issues.append(f"missing release payload: {missing}")
    if issues:
        raise ValueError("Bundle privacy check failed:\n" + "\n".join(sorted(issues)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    args = parser.parse_args()
    audit_bundle(args.app)
    print("PASS: bundle allowlist, symlinks, local paths, and credential patterns")

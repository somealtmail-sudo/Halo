# Releasing Halo

Halo 1.2.0 (build 3) targets Apple silicon and macOS 14.2 or later. The default build is a **private ad hoc beta**, signed locally and not notarized. The current development machine has no Developer ID Application identity. A downloadable ad hoc build can be blocked by Gatekeeper; these scripts do not change system security settings.

## Local beta

From the project root:

```sh
swift test
bash scripts/build.sh
python3 scripts/integration_test.py
python3 scripts/release.py
```

`release.py` packages the existing `dist/Halo.app`; it does not compile or install anything. It verifies the app's bundle identifier, version, minimum OS, strict nested signature, required portable resources, and arm64 architecture of the main executable, media framework, and helper. It rejects build-machine library dependencies and unsupported or mixed signing types. Build on Apple silicon. Mixed or Intel architectures are rejected rather than mislabeled.

Outputs in `dist/`:

- `Halo-1.2.0-macOS-arm64.zip`, containing `Halo.app`.
- `Halo-1.2.0-macOS-arm64.dmg`, containing the app, an Applications shortcut, and a short installation README.
- `SHA256SUMS.txt`, covering both final archives.

Quit a running Halo, drag the app to Applications, then launch it. The app runs in the menu bar. Login startup is an explicit Settings toggle. Installation and startup registration are separate from packaging.

## Developer ID release

Only use an existing Developer ID Application identity and an existing `notarytool` keychain profile. Never put certificates, passwords, API keys, or keychain profile credentials in this repository.

```sh
export HALO_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export HALO_NOTARY_PROFILE='your-existing-keychain-profile'
bash scripts/build.sh
python3 scripts/release.py
```

A real signing identity enables secure timestamps and the hardened runtime for the framework, helper, and app. An explicit `HALO_NOTARY_PROFILE` submits a temporary app ZIP, staples and validates the app ticket, then creates the final archives. It separately signs, submits, staples, and validates the DMG. Notarization is skipped when no profile is supplied. An ad hoc app cannot be notarized. Developer ID signing alone does not make a build notarized.

The Developer ID and notarization path requires validation on a machine with those credentials; it has not been exercised on this development Mac. The media adapter loads into the system Perl child process, so test media playback after changing signing modes.

## Validation before sharing

Run the automated checks above, then verify the installed app on macOS: first launch and Settings, music playback and media reconnect, hover opening/closing, timer completion while hidden, sleep/wake, login startup, and clean Quit without an orphan media adapter. Test a downloaded notarized release on another Mac and confirm Gatekeeper acceptance. Live GUI and fresh-machine checks are not established by signature verification or unit tests.

The bundle is built in a temporary staging directory and published only after signing verification. If publication fails after moving the old bundle, it restores the old bundle. Previous app bundles are retained under `.build/previous-apps/` so a process still running an earlier build keeps its executable inode. They can be removed after all earlier Halo processes have quit. Failed staging directories are cleaned automatically.

Builds use vendored adapter source and no downloaded build dependencies. Record the source commit, macOS version, `xcodebuild -version`, and `swift --version` with release notes. Archives are not byte-for-byte reproducible: toolchain output, signing timestamps, and archive metadata may differ. `SHA256SUMS.txt` identifies the exact artifacts shared in that release; regenerate it whenever either archive changes.

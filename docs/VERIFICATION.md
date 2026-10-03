# Verification

Environment: macOS 27.0.1 (26A434), Apple Silicon, Swift 6.4. Local verification performed October 2–3, 2026.

## Passed

- Debug and optimized release builds compile. The only release-build warning comes from upstream’s test helper using a variable-length-array extension; Halo’s Swift code builds without warnings.
- Twenty-three unit/regression tests: eight media/timer cases, seven pointer/geometry cases, four sizing cases, and four media stability cases. Coverage includes immediate entry, 180 ms exit, re-entry cancellation, manual-close suppression, pin/drag release, offset-screen alignment, transparent-corner click-through, camera minimums, malformed dimensions, oversized stream recovery, and non-finite playback timing.
- Ad-hoc app and nested-code signature verification (`codesign --verify --deep --strict`).
- Upstream media adapter compatibility test on the actual macOS session (exit 0).
- **Live Spotify UI:** automatic title/artist/artwork detection, progress, and pausing Spotify from Halo. Spotify was left paused after the test. Timeline rounding was corrected to match the player’s displayed duration.
- **Independent local integration player:** real silent AVAudioEngine output was detected with no Now Playing metadata. The same fixture with MPNowPlayingInfoCenter metadata was discovered by the system adapter. Toggle play/pause, seek to 90 seconds, next and previous all reached the fixture and produced verified state updates.
- **Native UI:** settings and island screenshots inspected; compact expansion, pinning, tabs, focus preset/start/pause/reset, and file-picker addition exercised. The paused timer remained unchanged across subsequent observations.
- **Shelf:** added this project’s README as a useful shortcut; original file remained in place. Fixed file-picker activation/retention after the first UI attempt exposed a focus issue.
- **Lifecycle:** standard Command-Q successfully quit the app. A final automated SIGTERM check verified that both Halo and its child media helper exit. Reconnect callbacks carry generation tokens so a previous helper cannot overwrite a newer connection.
- **Installation:** shell syntax validation and ten isolated fixture scenarios passed, covering first install, upgrade, invalid/missing source, staged-copy failure, foreign/symlink destination refusal, swap failure, and final verification failure with rollback.
- **Independent final reviews:** fixed stale direct-fallback controls, repeated paused-timeline regression, hidden shelf feedback, collapse after file-picker dismissal, timer updates during menu tracking, stale login status, and installation rollback.
- **1.1 redesign cross-review:** the two implementing agents reviewed each other's controller and interface changes. Fixed Settings safe-area clipping, neutral window background, transparent-corner click handling, minimum-height error layout, effective sizing labels, and non-finite Settings values.
- **Physical layout diagnostic:** on the built-in 1800 × 1169-point screen, the camera cutout is 220 × 38. Both window and visible island report a 0-point top gap; hosting content ends at screen y=1169 with zero safe-area inset. Top- and bottom-center hit checks pass.
- **1.1 media regression:** reran the local silent integration fixture against the rebuilt app; output-IO detection, metadata, play/pause, 90-second seek, next/previous, and clean app/helper shutdown all passed.
- **1.1 live UI:** inspected blank idle, expanded media, native Settings, and all three tabs at the minimum 380 × 200-point open size. Sliders changed rendered dimensions and Reset restored 420 × 240. Removed dense slider tick marks and duplicate preview text found during inspection. Screenshots are in `docs/screenshots`.
- **1.1 delivery:** installed version 1.1.0 in `~/Applications/Halo.app`, retaining the previous app as a backup. Installed nested-code signature verification passed and the installed app launched into its blank idle state. Updated `dist/Halo-macOS-arm64.zip` passed archive integrity verification.
- **1.2 Astra reviews:** three GPT-6 Astra agents at medium reasoning reviewed media stability, background scheduling, and release packaging, including cross-review of shutdown. Fixed a live-test-discovered AppKit deferred-termination/main-dispatch reentrancy hang before final packaging.
- **1.2 integration:** output-IO detection, metadata, play/pause, 90-second seek, next/previous all passed. Normal app/helper shutdown took 0.03 seconds; SIGSTOP-stalled helper shutdown took 1.11 seconds, within the three-second assertion. No owned helpers survived.
- **1.2 packaging:** versioned ZIP and DMG checksums passed. The extracted ZIP app passed strict nested signature verification, and `hdiutil verify` validated the DMG. The installed 1.2.0 app launches with one helper; launching a second normal copy exits successfully without creating another pair.

## Background sample

`scripts/profile.py` sampled app and helper cumulative CPU time and RSS over 30 seconds on this Mac, with no active audio source and the idle notch closed:

| Build | CPU, percent of one core | Peak combined RSS |
|---|---:|---:|
| 1.1.0 baseline | 4.826% | 88.22 MiB |
| 1.2.0, settled idle | 0.699% | 101.50 MiB |

An initial 1.2 sample that overlapped duplicate-launch/UI checks measured 1.631% CPU. The settled sample excluded those actions. Memory was not reduced in these samples; RSS includes shared pages and varies with system state. These short samples establish neither long-term battery use nor a resource guarantee. Playback animation, expanded controls, and other workloads can use more CPU. CoreAudio fallback scans remain at two-second intervals; visible notch pointer fallback remains at 120 ms to preserve responsive hover.

## Remaining manual coverage

- The final 1.2 UI automation check was unavailable because the computer-use service failed to start. The app itself launched and passed process/media tests; the interface screenshots above were inspected during 1.1. New sleep/wake scheduling and hidden timer completion still need hands-on runtime coverage.
- Physical pointer hover latency and subjective animation feel need hands-on validation. The automation's app-local clicks do not reliably change the physical `NSEvent.mouseLocation`; its idle-header click is not evidence of real hover success or failure. Geometry diagnostics and pure hover transition tests pass. The opt-in `--hover-diagnostics` flag provides a bounded 15-second local pointer trace for investigation.
- Apple Music and individual browser integrations use the shared system protocol but were not each exercised live. `scripts/browser-fixture.html` is provided to validate a browser locally without visiting a third-party site.
- The opt-in Music/Spotify Automation fallback, login registration, multiple physical displays, fullscreen apps, and physical charging/low-battery changes were not exercised end to end.
- File-picker addition was verified; cross-app drag-in/drag-out and Finder reveal still need hands-on coverage.
- This is a locally signed build. Developer ID signing, notarization, Intel builds and older macOS versions were not tested.

The synthetic integration fixture is development-only and absent from the app bundle. Its output is not presented as real user playback. Audio indicator bars are decorative, not a measured waveform.

## Repeatable commands

```sh
swift test
bash scripts/build.sh
python3 scripts/integration_test.py
```

Integration tests launch a silent player for a few seconds, temporarily publish its known metadata, and terminate it in `finally` blocks. The fixture also has a 45-second lifetime cap in case its runner is interrupted. Run them while other players are paused.

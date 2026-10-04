# Release privacy audit — 1.3.0

Performed October 4, 2026 on the current source, bundled executable/helper, documentation images, and extracted ZIP/DMG contents.

## Finding and fix

The prior locally built executable retained source and object paths in debug symbols, exposing the build machine's home-directory name. Bundling now strips debug symbols from all three Mach-O executables before signing and removes local extended attributes. This fix applies to newly built artifacts; it does not rewrite older release downloads or Git history.

`scripts/privacy_check.py` runs at bundle creation and again during packaging. It enforces an explicit file/symlink allowlist and rejects home/build paths and common private-key/API-token patterns without printing matching values. Six regression tests cover a clean bundle, embedded paths, an unexpected preference file, an escaping symlink, a synthetic token, and a missing resource. Pattern scanning is defense in depth, not proof that every possible secret format is detectable.

## Reviewed

- Tracked source, scripts, documentation, and assets: no real credentials or local account paths found by the scan and manual review. Synthetic privacy-test inputs deliberately exercise rejected data.
- Screenshot pixels show preview/Settings/idle content. ImageIO metadata inspection found dimensions and color information, with no author, device-serial, or GPS tags.
- App and adapter data flow: local Now Playing IPC, CoreAudio, optional Apple Events, and a local camera preview. No upload, telemetry, analytics, update-fetching, or network-client implementation was found in the runtime source. This is source review, not exhaustive packet capture or an OS-level isolation guarantee.
- Preferences and shelf file paths stay in the user's local preferences. No preferences, media samples, artwork caches, screenshots, logs, credentials, or Git metadata are included in the download payload.
- Opt-in diagnostics can print application/display details locally; they are not enabled during normal use or uploaded by Halo.
- Extracted ZIP and mounted read-only DMG: payload checks and strict nested signature verification passed. No home paths or credential-pattern matches were found. ZIP extra fields contained timestamps only, with no AppleDouble/resource-fork entries. The DMG contains Halo.app, the Applications link, and the installation README.

## Remaining visible identifiers and scope

The stable `dev.kevin.halo` identifier is retained to preserve upgrades, preferences, and permission continuity. Required upstream license attribution remains. Git author metadata remains in the repository's history; source-history anonymization was not performed. The repository was private during the 1.3.0 audit and became public for the 1.3.1 release. These artifacts are not an anonymous distribution of the project's authorship.

## Validation

All 34 Swift tests and six privacy-gate tests passed, along with the optimized release build, media integration, real waveform capture/cleanup, archive checksums, ZIP integrity, and DMG verification. Normal/stalled helper shutdown completed in 0.03/1.11 seconds. The waveform fixture observed 100 changing frames and cleared history after capture stopped. The release remains an ad-hoc-signed, non-notarized Apple-silicon beta.

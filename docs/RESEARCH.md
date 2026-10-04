# Research and implementation decisions

User-requested GPT-6.1 Sol agents researched media integration and competitor features, then reviewed media reliability and installation. For the 1.1 redesign, separate agents implemented hover/window geometry and the minimal interface/settings, then cross-reviewed one another. Their reviews resolved settings safe-area offsets, transparent-corner click capture, and minimum-height media error overflow. Builds and live verification were performed centrally.

For 1.2, GPT-6 Astra agents at medium reasoning completed the final media, background scheduling, and release audits after the user's model change. Cross-review and live tests found and resolved a deferred-termination run-loop hang; normal and deliberately stalled helper shutdown were then verified. The new app icon is a procedural sphere of widely spaced silver rings; the notch remains logo-free.

## Product references

- [Alcove](https://tryalcove.com/): restrained live activities and fluid transitions informed the focus on motion and quiet presence.
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch) and its [release notes](https://github.com/TheBoredTeam/boring.notch/releases): music, hover interaction, file shelf, screen behavior and artwork reliability informed the core scope.
- **Primary reference for 1.1: [DynamicLake](https://www.dynamiclake.com/).** Its [DynaMusic](https://www.dynamiclake.com/blog/dynamusic-music-control-in-dynamic-island-style) and [hover-preview description](https://www.dynamiclake.com/blog/the-sneak-peek-a-new-way) informed compact activity wings, immediate access to media details, and return to a quiet closed state. Its [timer](https://www.dynamiclake.com/timer) and [file shelf](https://www.dynamiclake.com/dynaclip) informed keeping these existing functions directly accessible. Exact animation timings below are Halo engineering choices.

Halo’s UI and source were written for this project; competitor app code/assets were not copied. The media adapter is the separately attributed dependency below.

## Media architecture

[MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter) documents restrictions on direct MediaRemote access since macOS 15.4, the system-Perl workaround, newline-delimited JSON, commands and microsecond seek units. Halo uses full snapshots, a bounded line parser, event-driven updates, per-connection generation tokens, and an explicit reconnect action. Fatal helper failures do not enter an automatic respawn loop.

[Apple CoreAudio process objects](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertyprocessobjectlist) and [output IO activity](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunningoutput) provide app-level fallback. The API describes active output IO, not audible sound or a track identity. This fallback does not capture sound. The separate opt-in live waveform captures system audio locally with macOS permission and immediately reduces it to a bounded amplitude history; it never saves or transmits recordings.

The installed Music and Spotify scripting dictionaries expose title, artist, album, position and transport. Opt-in Automation is a secondary fallback and uses bounded Apple-event timeouts. Spotify durations are milliseconds; Music durations are seconds. The app includes the [Apple Events usage description](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription) and entitlement.

## Motion and layout

- Measure each screen’s safe area and [auxiliary top areas](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea) instead of assuming a notch size.
- Disable the hosting view’s safe-area offsets and anchor both drawing and pointer geometry at the physical screen top. Idle dimensions match the physical camera cutout (220 × 38 points on the test Mac); active controls add side space.
- Default expanded size: 420 × 240 points. Both open dimensions and optional custom closed dimensions are adjustable. Content sits below the camera exclusion row, with hardware/content minimum sizes enforced.
- Expansion uses a 0.25-second spring, damping fraction 0.9, anchored at top center.
- Hover entry has no intentional delay; exit uses 180 ms with an 8-point retention margin. Global/local mouse events are backed by a passive 120 ms check for camera/menu-bar areas. Pointer exit during pinning, a file drop, or a held gesture does not collapse the island.
- Reduced motion uses a 100 ms ease-out transition and a static playback indicator.
- Only the visible island accepts pointer events; the surrounding transparent panel passes through to other apps.
- Preview content is labeled and does not send playback commands.

Weather, notification interception, calendar access, lyrics, queues and lock-screen integration were deferred to keep this build useful without unnecessary permissions or unsupported promises.

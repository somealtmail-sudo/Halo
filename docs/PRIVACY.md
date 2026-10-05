# Privacy

Halo runs locally. It has no account, analytics, advertising, or crash-upload service.

- The bundled helper reads macOS Now Playing metadata and sends playback commands locally.
- CoreAudio reports which applications have active output streams. The optional live waveform additionally captures system audio with macOS permission, immediately reducing it to a fixed 120 ms amplitude history. No raw audio is retained, saved, transmitted, or sent to speech recognition. The microphone is not accessed. Capture stops when idle, hidden, asleep, or Reduce motion is enabled.
- Optional Apple Music/Spotify Automation fallback requires macOS consent and is off by default.
- The Mirror tab uses the camera only with macOS permission and while the tab is visible. It displays a local mirrored preview with no recording output; video is never saved or transmitted. Capture stops when the notch closes, is hidden, changes tabs, or the display sleeps. It does not access the microphone.
- The file shelf stores file paths in local preferences. Files stay where they are; Halo does not upload them.
- Notes text is stored in local preferences and is never uploaded or synced. Clear removes the saved note. Release bundles do not include notes or other user preferences.
- Battery state, display geometry, and pointer position are used locally for the interface.
- Optional diagnostic flags print local information to the terminal. Pointer tracing stops after 15 seconds. Diagnostics are not uploaded.
- Launch at login is optional and uses macOS Service Management.

GitHub hosts source and release downloads. Halo does not poll GitHub or automatically download updates. Install a newer release manually after quitting the running app.

Release bundles contain only the executable, media helper/framework, icon, required property lists, signatures, and third-party license. They do not include developer preferences, shelf paths, screenshots, logs, source history, or credentials. Debug symbols containing build-machine paths are stripped before signing; an automated bundle allowlist and path/credential-pattern check run during both building and packaging. ZIP archives omit local extended attributes and resource forks.

The existing `dev.kevin.halo` application identifier and third-party license attribution remain visible. The identifier is retained for update, preference, and permission continuity. GitHub source history separately contains commit-author metadata; artifact sanitization does not anonymize that history. Diagnostics are opt-in and may identify locally running media applications or displays, so review diagnostic output before sharing it.

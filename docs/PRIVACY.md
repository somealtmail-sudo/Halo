# Privacy

Halo runs locally. It has no account, analytics, advertising, or crash-upload service.

- The bundled helper reads macOS Now Playing metadata and sends playback commands locally.
- CoreAudio reports which applications have active output streams. Halo does not record audio.
- Optional Apple Music/Spotify Automation fallback requires macOS consent and is off by default.
- The file shelf stores file paths in local preferences. Files stay where they are; Halo does not upload them.
- Battery state, display geometry, and pointer position are used locally for the interface.
- Optional diagnostic flags print local information to the terminal. Pointer tracing stops after 15 seconds. Diagnostics are not uploaded.
- Launch at login is optional and uses macOS Service Management.

GitHub hosts source and release downloads. Halo does not poll GitHub or automatically download updates. Install a newer release manually after quitting the running app.

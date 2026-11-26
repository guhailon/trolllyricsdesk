# Engine Fix
Original version and signing configuration retained. Three Swift files changed.
- MediaRemote: rate-aware position, duration clamp, 2-second request timeout, late callback rejection, 3-second maximum cache age.
- Coordinator: latest state independent of published state, consistent stable song key, cancellation generation, cache-first search, reset on missing music, paused seek synchronization.
- LRC: multiple timestamps, offset (positive advances lyrics), stable sorting.
Validation: Swift frontend syntax parse of three changed files; standalone LRC regression tests passed on Linux. No Xcode build, IPA signing or iOS device test. Existing snapshot clock still assumes normal playback speed; lock-screen no-music lifecycle not changed.
Run parser tests: swiftc Lyrics/LyricLine.swift Lyrics/LyricParser.swift EngineTests/main.swift -o /tmp/engine-tests && /tmp/engine-tests

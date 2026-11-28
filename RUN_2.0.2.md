# 2.0.2 Build 32 — first compatibility patch
Baseline: cf784282710b8a5a6ef7c3796974c42011877760.

Implemented: HUD exit-status validation, PID executable-path check (best effort, not atomic), stale plist load prevention; positive-evidence HUD UI gate and unknown environment fallback; authorized Apple Music playing-only fallback, explicit bundle-ID classification when metadata exists; monotonic playback extrapolation, optional enhanced-LRC word timing model, generation guard and reduced idle polling/writes; activation type allowlist; diagnostic permission button and build/uptime log; CI regression step.

Not implemented/verified: HUD heartbeat or full restart supervisor, QQ/NetEase independent live data access, transparent LC overlay, word highlighting in renderers, server-signed activation or revocation, full crash symbolication workflow (existing dSYM upload retained). Existing activation endpoint and entitlements unchanged. No lock-screen lyrics restored. No private ABI changes. Apple Music fallback requires user authorization and may not be available in LC. Bundle metadata key is experimental. Existing wall-clock cross-process snapshot remains. HUD PID path check reduces but cannot eliminate PID reuse race. Unknown install environments now intentionally fail closed, including possible misclassified TrollStore installs.

Validation: Linux swiftc parser over Swift sources; standalone Swift regression executable passed (LRC, enhanced LRC, legacy JSON, platform mapping, pause and duration clamp). No Xcode/iOS SDK, Objective-C++ compilation, signing or device tests performed. Existing historical check scripts retained, not claimed passing for new version.

Device gates: verify genuine TrollStore HUD enable/disable/reinstall, stale PID and failed launchctl; LC permission diagnostics and Apple Music fallback, QQ/NetEase nil handling; pause/seek/fast switch and offsets; activation upgrade/reinstall; PiP fixed text; collect crash .ips and matching dSYM UUID. Do not release as stable until gates pass.

Changed files:
- .github/workflows/build.yml
- App/ActivationKeychain.swift
- App/PlaybackDashboardView.swift
- App/SettingsView.swift
- App/TrollLyricsDeskApp.swift
- Compatibility/RuntimeEnvironment.swift
- Diagnostics/DiagnosticsView.swift
- EngineTests/main.swift
- HUD/TLDHUDDaemonMain.mm
- HUD/TLDHUDHelper.mm
- HUD/TLDHUDVersion.h
- Lyrics/LyricLine.swift
- Lyrics/LyricParser.swift
- Lyrics/LyricStore.swift
- MusicProviders/MediaRemoteAdapter.swift
- MusicProviders/MusicTrack.swift
- Overlay/TLDSAppDelegate.m
- PlaybackEngine/PlaybackCoordinator.swift
- PlaybackEngine/PlaybackState.swift
- TrollLyricsDesk.xcodeproj/project.pbxproj
- TrollLyricsDesk/Info.plist
- TrollLyricsWidget/Info.plist

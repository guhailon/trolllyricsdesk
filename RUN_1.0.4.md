# TrollLyricsDesk 1.0.4 — run log

1.0.3 cycle is in RUN_1.0.3.md (1.0.3 built + verified 2026-11-25 16:35, sent to Lee,
download link to 2026-11-27 16:37 Taipei; device test still pending).
1.0.4 = 1.0.3 + v0.5 floating lyrics HUD (Lee 2026-11-25 20:57 approved push+build,
bump to 1.0.4): same executable, two run modes (plain App / -hud standalone HUD
process, BackBoard-hosted window); main App publishes 4 lyric lines per line
change via TLLyricsIPC (shared plist + Darwin notification); ContentView gains
start/stop/preview buttons. Version bump CFBundleShortVersionString 1.0.4,
build 5, both targets; IPA/artifact renamed TrollLyricsDesk-1.0.4; check script
renamed check_1.0.4.py.

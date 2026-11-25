# TrollLyricsDesk 1.0.1 — run log

1.0.0 cycle is in RUN_1.0.0.md (first IPA built + verified 2026-11-25).
1.0.1 = 1.0.0 + version bump (CFBundleShortVersionString 1.0.1, build 2, both targets;
IPA/artifact renamed TrollLyricsDesk-1.0.1) + About fixes from 80fbb0f
(Telegram tg:// with web fallback, log in its own About section, LogView
structured rows + top empty state, LyricLogger wired into the coordinator).

## run 45559858421 — head 24e65b6 — 2026-11-25 14:23 CST — SUCCESS
- 9 Build steps success (zsign route; version bump + .gitignore cleanup only, code same as 80fbb0f).
- Artifact: TrollLyricsDesk-1.0.1 (id 14997133341, zip 217,774 B), IPA 219,534 B, SHA256 224b7415e50abdbc5f015dc3c24ac4c8ddc3b237302a8ad4a5f7b63bca9ef353.
- Verified locally (~/workspace/trolllyricsdesk/hidden_files/artifact-45559858421/):
  - Bundle ID com.hailong.TrollLyricsDesk, version 1.0.1, build 2, MinimumOSVersion 16.0; widget com.hailong.TrollLyricsDesk.TrollLyricsWidget, 1.0.1, build 2.
  - App binary: Mach-O 64 arm64 thin (magic cffaedfe, subtype 0), LC_CODE_SIGNATURE present; entitlements strings present: group.com.hailong.TrollLyricsDesk, com.apple.mediaremote.now-playing-read-access, com.apple.mediaremote.full-now-playing-read-access.
  - Widget binary: Mach-O 64 arm64 thin, LC_CODE_SIGNATURE present; app group string present, MediaRemote keys absent (correct — widget entitlements are app-group only).
  - Note: thin arm64 is normal for an Xcode device archive (dual-arch applies to Theos dylibs, not Xcode apps).
- Deploy NOT approved — separate approval. No channel post (paused).

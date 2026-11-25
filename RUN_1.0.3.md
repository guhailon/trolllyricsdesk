# TrollLyricsDesk 1.0.3 — run log

1.0.2 cycle is in RUN_1.0.2.md (1.0.2 built + verified 2026-11-25 16:00, sent to Lee, not yet installed/tested).
1.0.3 = 1.0.2 + About version row shows short version only (Lee 2026-11-25 16:23:
drop the (build) number — AboutView.appVersion no longer reads CFBundleVersion).
Includes the 1.0.2 Telegram invite-link fix. Version bump CFBundleShortVersionString
1.0.3, build 4, both targets; IPA/artifact renamed TrollLyricsDesk-1.0.3; check
script renamed check_1.0.3.py.

## run 45577195461 — head 0d91dce — 2026-11-25 16:34 CST — SUCCESS
- Build completed in ~2 min (poll check 2: completed/success; not a pool cancel).
- Artifact: TrollLyricsDesk-1.0.3 (id 15004238782, zip 217,397 B), IPA 219,231 B, SHA256 f1f716e9193acf76ca9baa0e5babdc822b85a4a54d14d2879b5283f5d880a829.
- Verified locally (~/workspace/trolllyricsdesk/hidden_files/artifact-45577195461/):
  - Bundle ID com.hailong.TrollLyricsDesk, version 1.0.3, build 4, MinimumOSVersion 16.0; widget com.hailong.TrollLyricsDesk.TrollLyricsWidget, 1.0.3, build 4.
  - App binary: Mach-O 64 arm64 thin (magic cffaedfe, cputype 0x100000c, subtype 0), LC_CODE_SIGNATURE present; entitlements strings present: group.com.hailong.TrollLyricsDesk, com.apple.mediaremote.now-playing-read-access, com.apple.mediaremote.full-now-playing-read-access.
  - Widget binary: Mach-O 64 arm64 thin, LC_CODE_SIGNATURE present; app group string present, MediaRemote keys absent (correct — widget entitlements are app-group only).
  - Telegram fix in the binary: strings contain tg://join?invite=I-I8aw7HUAw1NGY9 and https://t.me/+I-I8aw7HUAw1NGY9; zero occurrences of resolve?domain=seadragonjb.
- Deploy NOT approved — separate approval. No channel post (paused).

# TrollLyricsDesk 1.0.2 — run log

1.0.1 cycle is in RUN_1.0.1.md (1.0.1 built + verified 2026-11-25 14:23, installed by Lee 15:49).
1.0.2 = 1.0.1 + Telegram row fix (Lee 2026-11-25 15:52 approved): the channel
is a private channel with NO public username, so tg://resolve?domain=seadragonjb
/ t.me/seadragonjb cannot open it (Telegram said 「此用户似乎不存在」);
openTelegram() now goes via the channel invite link — tg://join?invite=I-I8aw7HUAw1NGY9
first, fallback https://t.me/+I-I8aw7HUAw1NGY9 (Bot API primary invite_link,
2026-11-25). Row label stays @seadragonjb. Version bump CFBundleShortVersionString
1.0.2, build 3, both targets; IPA/artifact renamed TrollLyricsDesk-1.0.2; check
script renamed check_1.0.2.py with updated Telegram markers.

## run 45572357419 — head 875a414 — 2026-11-25 16:00 CST — SUCCESS
- Build completed in ~2 min (poll check 2: completed/success; not a pool cancel).
- Artifact: TrollLyricsDesk-1.0.2 (id 15002971427, zip 217,742 B), IPA 219,550 B, SHA256 dfc688bfbb417c349f662568566b846c22dc8a66037d20f42f8e2a57ff8cc8c9.
- Verified locally (~/workspace/trolllyricsdesk/hidden_files/artifact-45572357419/):
  - Bundle ID com.hailong.TrollLyricsDesk, version 1.0.2, build 3, MinimumOSVersion 16.0; widget com.hailong.TrollLyricsDesk.TrollLyricsWidget, 1.0.2, build 3.
  - App binary: Mach-O 64 arm64 thin (magic cffaedfe, cputype 0x100000c, subtype 0), LC_CODE_SIGNATURE present; entitlements strings present: group.com.hailong.TrollLyricsDesk, com.apple.mediaremote.now-playing-read-access, com.apple.mediaremote.full-now-playing-read-access.
  - Widget binary: Mach-O 64 arm64 thin, LC_CODE_SIGNATURE present; app group string present, MediaRemote keys absent (correct — widget entitlements are app-group only).
  - Telegram fix in the binary: strings contain tg://join?invite=I-I8aw7HUAw1NGY9 and https://t.me/+I-I8aw7HUAw1NGY9; zero occurrences of resolve?domain=seadragonjb.
- Deploy NOT approved — separate approval. No channel post (paused).

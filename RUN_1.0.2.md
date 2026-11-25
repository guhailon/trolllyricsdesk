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

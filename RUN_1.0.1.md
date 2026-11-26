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

---

# 1.0.1（新线：纯 1.0.0 底子＋锁屏，build 14）

> 与上面旧线（云端 1.0.1／build 2）同名不同线：这条是 Lee 2026-11-26 09:28 定版的干净线——1.0.0 底子（build 13，commit 5b68754）只加锁屏（A 灵动岛＋B 锁屏小组件），不加 Engine V2、不加 1.0.6 播放改进、不加其他悬浮窗。分支 v1.0.1，worktree `~/workspace/trolllyricsdesk-1.0.1`。

## run 45737184426 — head 680c7cf — 2026-11-26 — FAILURE（代码错）

- Archive 步唯一 error（job.log 第 913 行）：`PlaybackEngine/PlaybackCoordinator.swift:26:6: error: stored properties cannot be marked potentially unavailable with '@available'`。
- 病根：`lastLiveState: LyricsLiveAttributes.ContentState?` 上标了 `@available(iOS 16.1, *)`——Swift 不允许给存储属性标 potentially unavailable；不带 @available 的原版（d461b62／e7e97df）同样编不过（MinOS 15.0 的类里存 16.1-only 类型）。两种写法都错，只是报错不同。
- 附带结论：1.0.4 build 17 的 Archive 失败基本可以坐实是同一个原因（同款代码在 e7e97df 里）；那条线已废，不再追究。

## run 45737671775 — head 6549b68 — 2026-11-26 01:45 CST — SUCCESS

- attempt 1 一次上机成功，无池子取消。
- 修法（6549b68，父 680c7cf，2 文件 +39/−13）：`lastLiveState` 改存普通 `Equatable` 键结构 `LiveLyricKey`（title／artist／previous／current／next／isPlaying／lyricColorHex 七字段，与 ContentState 一一对应），`publishLiveLyrics()` 里四处（两处清零、比较、赋值）都改成对键操作；去重语义不变（状态没变不推）。`lastLiveActivityID`（String?）未动。`state = newState` 仍在位（第 82 行）。`check_1.0.1.py` 同步更新：**106 PASS、FAILED: none、OPEN 17**。版本保持 1.0.1／build 14 不变。
- Artifact：id 15080170534，名「桌面歌词-1.0.1」，zip 1,585,844 B。
- IPA：**桌面歌词-1.0.1.ipa，1,587,434 B，SHA256 `77a01b668ec3a8b0dab0d96694c9959bea20deefbd79499124e665627a7a962a`**。存 `~/workspace/trolllyricsdesk/hidden_files/artifact-45737671775/`（artifact.zip＋IPA）。
- 验包（全过）：
  - App：1.0.1／build 14、显示名「桌面歌词」、包名 com.hailong.TrollLyricsDesk2、MinOS 15.0、`NSSupportsLiveActivities=true`
  - Widget：MinOS 15.0，扩展点 com.apple.widgetkit-extension；二进制含 `accessoryRectangular`＋`ActivityConfiguration` 符号（B 路在位）
  - 架构：Mach-O 64-bit arm64（两二进制均为 arm64）
  - 签名（zsign）：两二进制均含 LC_CODE_SIGNATURE（zsign 把签名嵌进二进制，IPA 里没有 _CodeSignature 目录——与已验过的 1.0.7 一致）
  - Overlay 串在位：TLDSFloatingLyric ×1、FBSystemShellInitialize ×2
  - 无 BackBoard（×0）、无 TLHUDApplication（×0）、无 `-hud`（×0）、无 dynamic_lookup（×0）
  - 无旧 tg://resolve（×0）；Telegram 邀请链接 t.me/+I-I8aw7HUAw1NGY9 在位（×1）
  - **otool 弱链接检查**：本机无 otool，用 Python Mach-O 解析器（`hidden_files/macho_inspect.py`）核实——App 与 Widget Extension 两二进制的 ActivityKit 均为 **LC_LOAD_WEAK_DYLIB**。注意：弱链接的 cmd 值是 0x80000018（带 LC_REQ_DYLD 位），只按 0x18 精确比会对不上，第一版解析器漏报过，已修正。
- 轮询备注：第一版轮询脚本读了 `gh_api.py run` 输出里的 HTTP `status`（200）当 run 状态，永远等不到 completed；是人工复查时发现 `status_field=completed`、`conclusion=success` 才确认成功。脚本已改成读 `status_field`，状态文件已补记 terminal。教训重申：轮询一律读 `status_field`／`conclusion`，不读 HTTP status——`gh_api.py run` 的输出里两个字段同名并存。
- 待真机验：灵动岛三态、锁屏横幅跟词、常亮显示（15 Pro）、iPhone 11 只有横幅＋小组件、锁屏小组件添加与延迟、滑掉横幅后开关同步、暂停提示、取色、浅色背景白色清不清晰、同曲进度跳转（独立修复，未做）。
- 此包未发给 Lee，等主聊发。

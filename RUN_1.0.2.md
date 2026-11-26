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

---

# 1.0.2（新线：1.0.1 build 14 底子＋五件，build 15）

> 与上面旧线（云端 1.0.2／build 3）同名不同线：这条是 1.0.1 build 14
> （555c666）只加五件——Telegram 行改 @Guhailon＋日志复制／清除、背景图任意换、
> 悬浮窗固定开关、自检脚本修、提示文字移入界面＋标题居中。分支 v1.0.1，
> worktree `~/workspace/trolllyricsdesk-1.0.1`，本地 HEAD 7e39edf。

## 推送（2026-11-26 11:59–12:01 CST）

远端 v1.0.1 从 555c666 起，gh_push.py 逐笔推（每笔推前先 check，均为
fast_forward_one_commit），五笔全上，远端终为 7e39edf：

- c35a053（Telegram 行改公开频道 @Guhailon＋日志页加复制／清除）
- e79218f（背景图任意更换）
- 177a25e（悬浮窗固定位置开关）
- ea3950d（自检脚本修：Overlay 红线改比 555c666..HEAD）
- 7e39edf（提示文字移到界面＋标题居中）

本地自检 `check_1.0.2.py`：**139 PASS、FAILED: none、OPEN 20**（推送前后一致）。

## run 45752565991 — head 7e39edf — 2026-11-26 12:05 CST — SUCCESS

- attempt 1 一次上机成功，无池子取消。轮询（读 `status_field`／`conclusion`）：
  poll 1–3 `in_progress`，poll 4 `completed`／`success`。
- 中间提交的 run（c35a053／e79218f／177a25e／ea3950d 各触发一个）不认，
  只认 head 7e39edf 的这一个；c35a053 的 run 45752393923 也是 success，
  其余在推完时仍在跑——与 1.0.2 的包无关。
- Artifact：id 15085948883，名「桌面歌词-1.0.2」，zip 1,592,377 B。
- IPA：**桌面歌词-1.0.2.ipa，1,594,006 B，SHA256 `40666f2c95004cc1791b612fc2bbf77a7eb2e53b678f50442b11e7a7a85cc74b`**。
  存 `~/workspace/trolllyricsdesk-1.0.1/hidden_files/artifact-45752565991/`
  （artifact.zip＋IPA＋unpacked/），另拷一份到
  `~/workspace/your_files/桌面歌词-1.0.2.ipa`（SHA 一致）。

## 验包（全过）

- App：1.0.2／build 15、显示名「桌面歌词」、包名 com.hailong.TrollLyricsDesk2、
  MinOS 15.0、`NSSupportsLiveActivities=true`
- Widget：1.0.2／build 15、MinOS 15.0，扩展点 com.apple.widgetkit-extension；
  二进制含 `accessoryRectangular`（×1）＋`ActivityConfiguration`（×3）；
  App 二进制也含 `ActivityConfiguration`（×6）
- 架构：Mach-O 64-bit arm64，两二进制均为 arm64（subtype 0）
- 签名（zsign）：两二进制均含 LC_CODE_SIGNATURE；IPA 里没有 _CodeSignature
  目录（zsign 把签名嵌进二进制，与已验过的 1.0.1 一致）
- 弱链接（本机无 otool，用 `hidden_files/macho_inspect.py` 核实，弱链接 cmd
  0x80000018 含 LC_REQ_DYLD 位）：App 与 Widget Extension 两二进制的
  ActivityKit 均为 **LC_LOAD_WEAK_DYLIB**
- Telegram 串：App 二进制含 `tg://resolve?domain=Guhailon`（×1）＋
  `https://t.me/Guhailon`（×1）；旧 invite 串全无——`tg://join?invite=`（×0）、
  `https://t.me/+I-I8aw7HUAw1NGY9`（×0），两二进制皆然
- 无 BackBoard（×0）、无 TLHUDApplication（×0）、无 `-hud`（×0）、
  无 dynamic_lookup（×0），两二进制皆然

## 待真机验（OPEN 20，自检原样）

1.0.2 新增五件（各件都要在真机上点一遍）：

- Telegram 行点开进频道：点开直接进 SeaDragon 越狱源公开频道；没装
  Telegram 时退回网页版；日志页复制能把整份日志贴到别处，清除要点确认后
  页面变空、文件删掉，再写日志时文件要重建
- 背景更换：设置页「背景设置」选图后，主界面／设置页／关于页立即换成这张图；
  开关关掉变纯黑；透明度滑杆拖动图跟着变透（默认 0.25 即图 75% 显示）；
  没选过图时是原来的紫／黑／蓝渐变；悬浮窗与小组件不受影响
- 悬浮窗固定位置：主界面悬浮歌词区打开「固定悬浮窗位置」后，悬浮窗拖不动、
  主界面的提示行变成“悬浮窗口 · 已固定 · 双击隐藏”，双击隐藏仍可用；
  关掉开关又能拖；重启 App 后悬浮窗还在上次存好的位置
- 提示文字移入界面＋标题居中：悬浮窗里只剩歌词，没有任何提示小字；
  主界面歌曲卡片和开关之间有一行提示，开锁时变“悬浮窗口 · 已固定 · 双击隐藏”，
  关锁时变“悬浮窗口 · 长按拖动 · 双击隐藏”；「桌面歌词」标题横向居中，
  齿轮仍在右上角原位

1.0.1 结转（未变）：灵动岛三态、锁屏横幅跟词、常亮显示（15 Pro）、iPhone 11
只有横幅＋小组件、锁屏小组件添加与延迟、滑掉横幅后开关同步、暂停提示、取色、
浅色背景白色清不清晰、同曲进度跳转（独立修复，未做）、Activity 节流、
8 小时到期重开、横幅与展开态两套布局（已知出入，非编译错）。

- Deploy NOT approved — separate approval. No channel post (paused).

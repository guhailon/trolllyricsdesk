# TrollLyricsDesk 1.0.6 — run log（已推、已编，构建成功）

基线 517bd4a（1.0.5）。皇上 2026-11-25 23:51 定混合整合方案、23:57 更正
最低系统 15.0：以 1.0.5 为基线，保留 v0.5 TLHUDApplication + BackBoard
HUD 架构，不引第二套宿主；只并皇上本地版（hidden_files/local-overlay-1.0.3）
的 0.25 秒检测 + 启动立即检测 + 换歌取消旧搜词 + 歌词缓存即播即显 +
保活可选开关（默认关）+ AppIconV2 + 显示名「桌面歌词」；保留原 Bundle ID；
最低系统 15.0；不并 Overlay 入口、.tbd 存根、扩展权限。

## 本地整合（v1.0.6 分支，2026-11-25 晚）

- PlaybackCoordinator：0.25 秒轮询（播放中）+ 空闲节能（没歌连续 4 次
  或暂停/停止时降到 1.0 秒档，恢复播放立刻回 0.25 秒；节能是 1.0.6 自加的，
  本地版固定 0.25 秒、没有节能写法）；换歌取消旧搜词（searchTask +
  checkCancellation）；publishImmediately + syncLyrics（不再写死透明度
  0.65/字体 22）；HUD 桥接钩子保留，换歌分支也调一次。
- LyricStore：加歌词本地缓存（cachedLyrics/cacheLyrics，App Group）。
- MediaRemoteAdapter：缓存保鲜 2.0 秒 → 0.3 秒。
- 新文件 App/BackgroundKeepAlive.swift（本地版静音音频引擎 + 补 stop()）；
  ContentView「歌词悬浮窗」区加开关（@AppStorage hudKeepAliveEnabled，
  默认关）；Info.plist 加 UIBackgroundModes audio。
- 图标换 AppIconV2（9 张，Contents.json 原样；1024 图是新图 660KB）。
- 显示名改「桌面歌词」；版本 1.0.6 build 7（两 Info.plist、build.yml、
  README/BUILD_NOTES、check 脚本改名 check_1.0.6.py）。
- 最低系统 15.0：两 Info.plist + pbxproj 6 处 IPHONEOS_DEPLOYMENT_TARGET
  全改 15.0；全树只查到 2 处 16+ API，都用 #available 包起来了：
  SettingsView 的 PhotosPicker 抽成 @available(iOS 16, *) 独立子视图
  BackgroundPhotoPickerRow（iOS 15 上该行不显示），LogView 的 ShareLink
  用 if #available(iOS 16, *) 包起来。没有悄悄改回 16.0。
- HUD 透明度调整补上：LyricsHUDController 加卡片下方跟随小滑杆
  （0.4–1.0，默认 0.92，值存 App Group；KVO 跟卡片中心，捏合跟底边，
  贴底时翻到卡片上方）；LyricsHUDView.swift 一字不动。

## 权限

1.0.6 的 entitlements 和 1.0.5 一字不改。本地版扩的权限（frontboard /
runningboard / QuartzCore / iokit / storage / mach 白名单等）一律不要，
理由逐项见 BUILD_NOTES.md 1.0.6 节权限差异表。

## 编译风险（摘要，详见 BUILD_NOTES.md 1.0.6 节）

- -undefined dynamic_lookup 已在 1.0.6 构建中上机验证通过（见下「构建记录」）。
- AVFoundation 链接是第一次（保活用，pbxproj + Makefile 都加了）。
- KVO 跟滑杆没真机验过（不触发也只会滑杆不动，不崩）。
- SettingsView 为 15.0 适配动了结构（选图行抽子视图），7 项设置都在。
- 第一次把部署目标降到 15，Xcode 26.6 + iOS 15 组合待构建验证。
- 逐字同步未实现（两边都没有 LyricWord.swift / LyricSyncEngine.swift），
  记 OPEN，不现编假实现。

## 构建记录（2026-11-26 00:20 台北，成功）

- 皇上 2026-11-26 00:12 批推＋编。远端新分支 v1.0.6 建在 517bd4a，
  gh_push.py 快进一笔推上 2f75e89（27 blobs/12 trees），main 未动。
- run 45651994856（head 2f75e89，分支 v1.0.6）：约 00:15 入队，4 分钟
  上机，00:20 完成，结论 success，job Build 11 步全部 success。
  **Archive（链接）过了——`-undefined dynamic_lookup` 修法第一次
  在真机上得到验证**（1.0.4 池子取消、1.0.5 七次池子取消＋重跑接口
  500，之前一次没上过机）。副产物 run 45651896868（head 517bd4a，
  建 ref 顺带触发）未管。
- artifact id 15040858066，名 TrollLyricsDesk-1.0.6，1,528,797 B；
  IPA TrollLyricsDesk-1.0.6.ipa，1,530,822 B，
  SHA256 8a0c66021cb02e96918e46b766c586d1cdad8a35babf9d4ace673ce2c9257e67，
  存 hidden_files/artifact-45651994856/。
- 验包全过（奴才复核）：App 1.0.6/build 7、Bundle ID
  com.hailong.TrollLyricsDesk、显示名「桌面歌词」、最低系统 15.0
  （App + Widget）、UIBackgroundModes audio 在位、Widget 1.0.6/build 7、
  App/Widget 二进制 arm64 thin + LC_CODE_SIGNATURE（zsign）、entitlements
  HUD 键（backboard.client、accessibility-window-hosting、App Group）在位、
  binary 含 -hud 串和 TLHUDApplication 串、无旧 tg://resolve、Telegram
  邀请链接 t.me/+I-I8aw7HUAw1NGY9 在位。无 _CodeSignature 目录是 zsign
  形态（签名嵌在 Mach-O 里），跟 1.0.3 一致，不是问题。
- 下载链接已发皇上（48 小时，到期 2026-11-28 00:55 台北）＋一键
  TrollStore 安装链接。等皇上真机测：悬浮歌词（拖动/缩放/透明度/
  触摸穿透/关闭）、0.25 秒跟随、保活开关、Telegram 行、版本显示。

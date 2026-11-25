# TrollLyricsDesk 1.0.6 — run log（本地整合，未推、未编）

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

- -undefined dynamic_lookup 仍未上机验证（1.0.5 七次池子取消，一次没上机）。
- AVFoundation 链接是第一次（保活用，pbxproj + Makefile 都加了）。
- KVO 跟滑杆没真机验过（不触发也只会滑杆不动，不崩）。
- SettingsView 为 15.0 适配动了结构（选图行抽子视图），7 项设置都在。
- 第一次把部署目标降到 15，Xcode 26.6 + iOS 15 组合待构建验证。
- 逐字同步未实现（两边都没有 LyricWord.swift / LyricSyncEngine.swift），
  记 OPEN，不现编假实现。

## 待皇上确认后再推 + 编

推 + 编等皇上确认。构建成功后的收尾：监视 run → 下载 artifact 验包
（1.0.6/build 7、Bundle ID、arm64、zsign、entitlements HUD 键、binary
含 TL_ 串和 -hud 串、无旧 tg://resolve、Telegram 邀请链接在位、
显示名桌面歌词、最低系统 15.0）→ 发下载链接 + 一键 TrollStore 安装链接。

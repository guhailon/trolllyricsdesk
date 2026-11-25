# TrollLyricsDesk 1.0.0 — 构建记录

日期：2026-11-25（01:42 批建，01:52 加 4 项新功能，02:00 批加跟随代码 +
Lee 的新结构，02:04 定 LyricsSearchView 两处 isPlaying 各一个值，
02:15 皇上发新结构重组，02:20 定 savePlayback 歌名+歌手双匹配，
02:21 定开始检测先申请媒体资料授权）
状态：本地建好 + 验过（check_1.0.0.py 见“验证结果”）。**没推、没部署。**
macOS 编译和真机测试都还没做。

## 新结构（Lee 02:15 定的树，原样）

```
TrollLyricsDesk/
├── App/
│   ├── TrollLyricsDeskApp.swift
│   ├── ContentView.swift
│   └── PlaybackDashboardView.swift
├── PlaybackEngine/
│   ├── PlaybackState.swift
│   ├── PlaybackAdapter.swift
│   ├── PlaybackCoordinator.swift
│   └── LyricMatcher.swift
├── MusicProviders/
│   ├── AppleMusicAdapter.swift
│   ├── NetEaseAdapter.swift
│   ├── QQMusicAdapter.swift
│   └── ExternalTrackInput.swift
├── Lyrics/
│   ├── LRCLibClient.swift
│   ├── LyricParser.swift
│   ├── LyricStore.swift
│   └── LocalLRCImporter.swift
└── TrollLyricsWidget/
    ├── TrollLyricsWidget.swift
    └── WidgetView.swift
```

另外：MusicTrack.swift 在 MusicProviders/（Lee 说继续沿用）；
LyricsSearchView.swift 在 App/（树里没单列，但 PlaybackDashboardView
链到它，必须留）；LyricSnapshot 仍在 LyricStore.swift 里（树里没有
LyricSnapshot.swift，不另拆文件）；SettingsView.swift 是 Lee 原文件（02:37 发的，已按原样换到 App/）。

## Lee 发的代码（原样，一字未改）

- Lyrics/LyricLine.swift
- Lyrics/LyricParser.swift
- Lyrics/LyricStore.swift（groupID = group.com.hailong.TrollLyricsDesk；
  currentElapsed 已是 Lee 02:19 定的公式，不用改）
- App/TrollLyricsDeskApp.swift（删了启动 NowPlayingFollower 的 init，
  其余不动；跟随引擎换成 PlaybackCoordinator，见下）
- App/ContentView.swift（演示歌词 + 透明度/字体大小；加了两条
  NavigationLink：到 LyricsSearchView、到 PlaybackDashboardView，
  都是 Lee 发的片段原样）
- TrollLyricsWidget/TrollLyricsWidget.swift（含 TrollLyricsProvider）
- TrollLyricsWidget/WidgetView.swift
- TrollLyricsWidget/TrollLyricsWidgetBundle.swift（@main 入口，树里没单列但必须有）
- MusicProviders/MusicTrack.swift（统一数据模型；声明按 Lee 02:16 改成
  `struct MusicTrack: Codable, Identifiable, Equatable`）
- MusicProviders/AppleMusicAdapter.swift（系统播放器读正在放的歌；
  另附 Lee 发的 requestMusicPermission 函数原样）
- MusicProviders/NetEaseAdapter.swift（新版：不带协议，只 makeTrack 拼 MusicTrack）
- MusicProviders/QQMusicAdapter.swift（同上）
- MusicProviders/ExternalTrackInput.swift（外面传进来的歌，拼成 MusicTrack）
- PlaybackEngine/PlaybackState.swift（播放状态 + 歌名/歌手键）
- PlaybackEngine/PlaybackAdapter.swift（@MainActor 协议：platform + currentState）
- PlaybackEngine/PlaybackCoordinator.swift（每秒轮询适配器；savePlayback 的
  歌名检查按 Lee 02:20 改成歌名 + 歌手双匹配）
- PlaybackEngine/LyricMatcher.swift（从搜索结果里按歌名/歌手/时长打分挑最合的一份）
- App/PlaybackDashboardView.swift（播放状态面板；“开始检测音乐”按钮按
  Lee 02:21 改成先 requestMusicPermission，授权了才 coordinator.start()；
  onAppear 还是直接 coordinator.start()，Lee 没让改，等他定）
- Lyrics/LRCLibClient.swift（LRCLIB 搜索/取词，公开接口）
- Lyrics/LocalLRCImporter.swift（读本地 .lrc）
- App/LyricsSearchView.swift（搜索 + 导入界面；两处 isPlaying 按 Lee 02:04
  的纠正：selectLyrics 改 true，importLocalFile 保持 false；两处
  importTrack 改成 makeTrack，新适配器没有 importTrack）
- 挂接的 NavigationLink（ContentView 里加到 LyricsSearchView 的入口，Lee 发的片段原样）
- 新版 getTimeline（TrollLyricsWidget.swift 里替换，Lee 发的版本原样，按每句词预排时间线）
- qingtian.lrc（Lee 发的《晴天》LRC 测试样本：[ti:]/[ar:]/[al:] 要跳过，只取 3 句词）
- NSAppleMusicUsageDescription（Info.plist，Lee 发的文案原样：
  “用于读取用户授权的音乐资料和显示歌曲信息。”）

## 新加的文件（我们写的，不是 Lee 的）

- TrollLyricsDesk/LyricLogger.swift — 写 Documents/TrollLyricsDesk.log（200KB 截断）。
  跟随引擎换了之后暂时没有调用方（PlaybackCoordinator 还没接日志），按任务要求保留。

## 删掉的文件（Lee 的新文件/新结构 supersede 上一版）

- TrollLyricsDesk/NowPlayingFollower.swift — 删（02:15 重组）。**跟随机制
  后来又改回来了（Lee 02:30 定）**：新文件 `MusicProviders/MediaRemoteAdapter.swift`
  接替了它，同样走 MediaRemote 读任何 App 正在放的歌（QQ音乐/酷我等都能跟），
  只是现在挂在 `PlaybackAdapter` 接口下、由 `PlaybackCoordinator` 驱动。
  MediaRemote 的两项 entitlements 和 OTHER_LDFLAGS 链接参数跟随又用上了。
- MusicProviders/MusicPlatformAdapter.swift — 删。旧协议被 PlaybackAdapter 取代，
  新版 NetEase/QQ 适配器不再遵守它。
- 旧组 Shared/、LocalLyrics/、LyricsSearch/ — 空了之后删掉，文件按新树搬家。
- TrollLyricsDesk/LyricSearchService.swift — 删（上一轮）。它的 LRCLIB + 网易云/QQ 网络
  搜索代码由 LRCLibClient.swift + 适配器文件接替；网易云/QQ 网络搜索
  （music.163.com / c.y.qq.com）不再在工程里，查词只走 LRCLIB，
  网易云加密的问题也就不存在了。
- TrollLyricsDesk/ImportSearchView.swift — 删（上一轮）。由 Lee 的 LyricsSearchView.swift
  接替（已挂进 ContentView 和播放面板）。
- App/SettingsView.swift — Lee 原文件（02:37 发的，已按原样换上，7 项功能全在）。7 个 @AppStorage 键已按 Lee 02:39 的提醒迁到 App Group 共享区（其余代码没动）；小组件还是读快照（LyricSnapshot）里的透明度/字体——小组件读共享键还是快照，等 Lee 定。逐字卡拉OK 只是选项，逐字解析未实现（后续工作）。
- TrollLyricsDesk/Assets.xcassets — 占位图标（PIL 生成的紫蓝渐变 + 音符 + “歌词”），
  全套 9 张尺寸齐全，Lee 之后可以换。
- TrollLyricsDesk/Info.plist、TrollLyricsWidget/Info.plist
- TrollLyricsDesk/TrollLyricsDesk.entitlements（App Groups + 两个 mediaremote 读权限，
  现在是上一版跟随留下的）
- TrollLyricsWidget/TrollLyricsWidget.entitlements（App Groups）
- TrollLyricsDesk.xcodeproj/project.pbxproj（手写，App + Widget Extension 两个 Target，
  两个 Target 都启用 App Groups capability，Widget 经 Embed App Extensions 嵌进 App；
  App Target 的 link phase 加了 MediaPlayer.framework）
- TrollLyricsDesk.xcodeproj/xcshareddata/xcschemes/TrollLyricsDesk.xcscheme
- .github/workflows/build.yml（macOS：xcodebuild 不签名导出 → ldid 签名 → 打 IPA → 上传）
- sample.lrc（Lee 发的 LRC 样本，解析测试用）
- check_1.0.0.py（验证清单）
- README.md（本文件同目录）

## 接口实测（2026-11-25，写代码之前核过；02:04 这轮里网易云/QQ 网络搜索已不在工程里）

- LRCLIB /api/search：**通**。搜“江南”返回明文 JSON，第一条
  id 8342654《江南》- JJ Lin，带 syncedLyrics（[00:37.04] 起）和 plainLyrics。
  LRCLibClient 只调 LRCLIB（/api/search + /api/get），不用登录、不用凭证。
- 网易云 api/search/get/web（上一版实测）：**能通，但 result 已加密**。
  上一版的适配器按明文解析会失败 → 只记日志、暂无歌词。**这轮已不在工程里**：
  Lee 新发的 NetEaseAdapter 只拼 MusicTrack，不调任何网络接口，
  所以加密的问题不存在了；以后想加网易云在线搜索，得另定方案。
- QQ 音乐 client_search_cp（上一版实测）：**这边网络拉不到**（DNS/超时），
  没验到；同上，这轮已不在工程里。

## 警告：不要用 Textyl / 不要抄 AGPL 代码

Lyrication（thatmarcel/lyrication）是 AGPL-3.0 的开源项目，它的歌词接口
Textyl 是作者私有的，作者明说不要给别的项目用。我们只学思路（时间戳反推
进度、歌名清洗、按歌名+歌手判换歌），一行 AGPL 代码也没抄，查词只走
公开免费的 LRCLIB。这条警告以前写在 NowPlayingFollower.swift 的注释里，
那个文件删了，警告挪到这里。

## 验证结果

`python3 check_1.0.0.py`：**215 PASS，FAILED: none**（另有 12 项 OPEN，见输出）。
本地能验的都验了；不能验的如实列出：

- 未验证：macOS 编译（Linux 没 Xcode/swiftc）、真机安装/运行、
  Apple Music 媒体资料授权、小组件真机刷新。
- MediaPlayer.framework 的链接（pbxproj 里 App Target 的 link phase）
  是按 SDK 布局写的，macOS 链接那一步才是第一次实测。
- OTHER_LDFLAGS 里 MediaRemote 的链接参数跟随又用上了
 （`MediaRemoteAdapter` 链接它）。
- 待 Lee：推 + 编的批准（SettingsView 原文件 02:37 已发并换上，02:14“等它再推”的条件已满足）。App Group 已核对一致（两边 entitlements 都是 group.com.hailong.TrollLyricsDesk，pbxproj 里 App/Widget 的 CODE_SIGN_ENTITLEMENTS 各指各的 entitlements 文件，LyricStore 的 groupID 也一致）。

## 已知的行为缺口（不要当成已实现）

1. 跟随改回走 MediaRemote（Lee 02:30 定）：读任何 App 正在放的歌，
   QQ音乐/酷我/网易云/Apple Music 都能跟；沙盒能不能读到得真机试。
   `AppleMusicAdapter` 留在工程里但面板不再接它；媒体资料授权
   （NSAppleMusicUsageDescription）还留在 plist 里，面板不再问。
2. 小组件时间线按每句词预排 + App 改快照时立即刷新；系统节流，接近实时、不是每秒同步。
3. LyricParser 保留空歌词行（Lee 的解析器原样）。
4. 网易云/QQ 适配器只是数据模型（Lee 的文件）：拼 MusicTrack 用；查词只走 LRCLIB，
   不调网易云/QQ 的网络接口。

---

# v0.5 — 悬浮歌词 HUD（2026-11-25 晚，本地实现，未推、未编、未部署）

目标：歌词不只在小组件里，跟 TrollSpeed / XExternalHUD 一样，浮在主屏幕
和别的 App 之上的可拖动歌词卡片。同一可执行文件分流两个运行模式：
普通启动是主 App；`-hud` 参数启动是独立的 HUD 子进程，窗口经
BackBoard 托管浮在所有 App 之上；主 App 每秒轮询切词时把四行词写进
共享 plist + 发 Darwin 通知，HUD 进程读到就刷新卡片。

版本号：皇上 2026-11-25 20:57 批升 1.0.4（build 5）。

## 1.0.5（本地准备中，未推）

- 补丁 IPC 合入：sources/TLLyricsIPC.h/.mm 换成审计补丁（与皇上发的补丁逐字节一致）——App Group 容器 JSON + notify_register_dispatch/notify_post + stopObserving；publishLyrics 改回 BOOL。TLPrivate.h 的 TL_NOTIFY_LYRICS / TL_LYRICS_PATH 留着（TLHelper 的 prefs 小工具还在用它俩，暂无调用者）。
- 捏合缩放：LyricsHUDController 加 UIPinchGestureRecognizer（FloatingLyricsPanel 同款 0.65–1.8 夹值）；皇上的 LyricsHUDView.swift 一字不动。
- 链接问题已修（1.0.4 的教训）：pbxproj 缺 FRAMEWORK_SEARCH_PATHS，938d282 的 run 在 Archive 那步链接失败（ld: framework 'BackBoardServices' not found）。修法：App target Debug + Release 加 `$(SDKROOT)/System/Library/PrivateFrameworks`。皇上 2026-11-25 21:19 定并进 1.0.5 一起编。

## 新文件

皇上的文件（逐字原样，一字未改；见下两处例外，只改 TLLyricsIPC.mm）：

- HUD/LyricsHUDView.swift — 悬浮卡片 UI（毛玻璃、动漫背景、上句/当前/下句、
  拖动、关闭按钮、拖动不出界）
- HUD/LyricsHUDBridge.swift — Swift 发词接口（调 TLLyricsIPC.publishLyrics）
- HUD/FloatingLyricsController.swift — App 内预览：单例，show/hide/update
- HUD/FloatingLyricsPanel.swift — App 内预览的卡片（捏合缩放版）
- HUD/FloatingLyricsStyle.swift — App 内预览的卡片样式
- sources/TLLyricsIPC.h — 跨进程歌词 IPC 接口（发/读/监听）

我们写的宿主代码（原创，TL_ 前缀；机制照公开的上游做法，代码自己写）：

- sources/TLPrivate.h — 私有声明（GSInitialize、GSEventInitialize、
  BKSDisplayServicesStart、UIApplicationInitialize、UIApplicationInstantiateSingleton、
  _accessibilityInit、__completeAndRunAsPlugin、UIEventDispatcher/Fetcher、
  UIWindow _contextId/_initWithFrame:attached:、
  SBSAccessibilityWindowHostingController 注册）+ TL_ 常量
  （TL_NOTIFY_LYRICS / TL_NOTIFY_DISMISS / TL_LYRICS_PATH / TL_PID_PATH，
  全是 com.trolllyricsdesk.v05 命名空间，不复用上游的文件名和通知名）
  + PAC 剥离/签名小工具（ARM64 扫描兜底用）
- sources/TLHelper.h/.mm — 共享 plist 读写、Darwin 通知、HUD 生命周期
  （isHUDRunning 跑一次 -check 子进程看退出码；startHUD 以 -hud 重起自己；
  stopHUD 先发 dismiss 通知、0.6 秒后 -exit 兜底；绝不以 root 身份 spawn，
  root 进程拿不到 HID 触摸流）
- sources/TLHUDWindow.h/.mm — 全屏系统窗口：_initWithFrame:attached:NO
  脱离默认 Scene；_isSystemWindow YES、_isWindowServerHostingManaged NO、
  _usesWindowServerHitTesting NO、_ignoresHitTest NO；hitTest 只让卡片区域
  吃触摸，其余区域透传给下面的 App
- sources/TLHUDApplication.h/.mm — HUD 进程的 UIApplication 子类：init 里
  手工接事件分发器和 fetcher（调不到 _installEventRunLoopSources: 时用
  ARM64 扫描找内联掉的安装函数，找到就签上名直接调）；同文件里的
  TLHUDAppDelegate 建全屏窗口（windowLevel 10000010.0）、注册
  backboardd 托管、监听 dismiss（0.25 秒淡出后 exit(0)）、监听歌词
  （直接接 LyricsHUDController.update，不留 NSLog 占位）
- sources/TLAppDelegate.h/.mm — 普通模式 delegate：根视图取自
  TLAppRoot.makeRootViewController()
- sources/main.mm — 唯一程序入口：无参数走 UIApplicationMain +
  TLAppDelegate；-exit 杀 HUD；-check 退出码报 HUD 是否在跑（1 = 在跑）；
  -hud 手工 UIKit 启动（GSInitialize、BKSDisplayServicesStart、
  UIApplicationInitialize、UIApplicationInstantiateSingleton、
  _accessibilityInit、iOS 15+ 时 GSEventInitialize + GSEventPushRunLoopMode、
  __completeAndRunAsPlugin、监听 SBSpringBoardDidLaunchNotification、
  respring 时自杀、CFRunLoopRun）。不带 ImGui / HID 回调（我们没有
  ImGui，触摸走事件分发器）
- HUD/LyricsHUDController.swift — HUD 进程的歌词控制器：根视图是全屏透明
  容器，卡片是子视图（frame 默认 x 30、y 180、w 300、h 126，和
  FloatingLyricsController 同款）；update 转发给 view.updateLyrics；
  关闭按钮调 TLHelper.stopHUD
- App/TLAppRoot.swift — Swift 入口工厂：makeRootViewController() 包
  ContentView() 进 UIHostingController；keyWindowRootView() 取 key window
  的根视图（没有 key window 时退回第一个窗口），给 App 内预览用
- TrollLyricsDesk/TrollLyricsDesk-Bridging-Header.h — 桥接头（TLLyricsIPC.h +
  TLHelper.h），App target Debug/Release 都设了 SWIFT_OBJC_BRIDGING_HEADER
- Makefile — Theos 第二条构建路线（见下“Theos 实测”）

## 改动的文件

- App/TrollLyricsDeskApp.swift — 删（@main 没了，main.mm 是唯一入口；
  pbxproj 里的引用也清了）
- App/ContentView.swift — 只加一个“歌词悬浮窗”区（三个紫色圆角按钮，
  和“加载测试歌词”同款）：开启歌词悬浮窗（TLHelper.startHUD）、
  关闭悬浮窗（TLHelper.stopHUD）、预览悬浮歌词
  （FloatingLyricsController.shared.show + update 一组演示词）
- PlaybackEngine/PlaybackCoordinator.swift — 只加钩子：每秒 poll 时按快照
  + 当前进度算上一句/当前句/下一句，当前行下标变了才调
  LyricsHUDBridge.update。挑行算法和 Widget 一样（最后一句 time <=
  elapsed 的行是当前行，LyricStore.currentElapsed + lastIndex；换歌时
  lastHUDLyricIndex 清零）。没快照或没歌词时不调
- TrollLyricsDesk/TrollLyricsDesk.entitlements — 只加 v0.5 的键（现有
  App Groups + 两个 mediaremote 一字不动；Widget 的 entitlements 一字不动）：
  com.apple.backboard.client、com.apple.springboard.accessibility-window-hosting、
  com.apple.assistivetouch.daemon、com.apple.backboardd.launchapplications、
  com.apple.springboard.launchapplications、com.apple.private.security.no-sandbox、
  platform-application、get-task-allow、task_for_pid-allow、
  com.apple.private.security.task_for_pid-allow（以上 true），
  mach-lookup.global-name = [com.apple.accessibility.AXSpringBoardServer]、
  mach-register.global-name = [com.trolllyricsdesk.v05.gsEvents]、
  mach-register.local-name = [com.trolllyricsdesk.v05]（以上数组）
- TrollLyricsDesk.xcodeproj/project.pbxproj — 新组 HUD/、sources/；
  全部新文件进 App target（Sources phase 13 个、Frameworks phase 3 个弱链）；
  App target 弱链 BackBoardServices、GraphicsServices、SpringBoardServices
  （PBXBuildFile Weak 属性；MediaRemote 仍是 dlopen，不直接链）；
  TrollLyricsDeskApp.swift 的引用清掉；Widget target 一字不动
- check_1.0.5.py — 加第 13 节 v0.5 检查（文件都在、皇上的文件逐字节一致、
  宿主代码零上游名字、bridging header、entitlements、main.mm 四种模式、
  @main 已删）；第 1/2/5 节同步改（入口文件删了）；
  “PrivateFrameworks 不在 pbxproj”那项改成只查 MediaRemote 不直接链
  （弱链私有 Framework 后 PrivateFrameworks 字串必然在 pbxproj 里）

## 两处集成改动（皇上的文件，一字未改之外的例外，如实记下）

1. **sources/TLLyricsIPC.mm 的 observeLyrics 重写了。** 皇上发来的是接口
   草案：它把 block 字面量直接当 C 函数指针传给
   CFNotificationCenterAddObserver，且 observer 用 __bridge 不持有——
   生命周期和回调签名都有问题，编不过、跑起来也可能崩。改法照上游的
   做法：写一个 static C 回调函数 TL_LyricsNotifyCallback，observer 用
   __bridge_retained 传 block 副本（进程生命周期内持有是故意的），回调里
   读 plist、回主线程调 handler。公开接口（publishLyrics/readLyrics/
   observeLyrics）、TL_ 名字和路径一字不动；publishLyrics/readLyrics
   的逻辑保留原样。另有一行 import 改了：`#import "XEPrivate.h"` →
   `#import "TLPrivate.h"`，因为本工程的私有定义头就是 TLPrivate.h
   （XEPrivate.h 这个文件不存在）。check 脚本第 13c 节验这两处：
   publish/read 部分和皇上原版逐行一致、observeLyrics 是 static C 回调
   + __bridge_retained、没有 block 当函数指针的写法。
2. **ContentView 预览的兜底。** 任务原话是 `show(in:
   TLAppRoot.keyWindowRootView() ?? 兜底 view)`；实现里兜底放在了
   TLAppRoot.keyWindowRootView() 内部（key window 没有时退回该 scene 的
   第一个窗口），ContentView 里拿不到窗口时直接 return——往一个没上屏的
   假 view 里加面板会被单例卡住、再也点不出来。演示词和
   FloatingLyricsController.show() 里写死的同一组。

## 机制参考与致谢

- 机制参考 **TrollSpeed**（Lessica，MIT，Copyright (c) 2023 Lessica）：
  HUD 进程手工拉起 UIKit、事件分发器接线、BackBoard 托管窗口。
  LICENSE 在 hidden_files/upstream-trollspeed/LICENSE，版权声明保留。
- 机制参考 **XExternalHUD**（xauszulay）：同一个可执行文件分流普通启动
  与 -hud 模式、共享 plist + Darwin 通知跨进程同步、HUD 生命周期
  （start/stop/-exit/-check）。**它的代码没有复制**：XExternalHUD 没有
  LICENSE 文件、README 也没有许可证声明，视为保留所有权利；宿主层
  （TLHelper / TLHUDWindow / TLHUDApplication / TLAppDelegate / main.mm /
  TLPrivate.h）是我们按同样机制独立写的，命名、注释、结构都是自己的，
  代码里不出现 XEHUD / XExternalHUD / XEHelper / XEPrivate 字串
  （check 脚本第 13d 节逐文件验）。
- **Lyrication 是 AGPL，绝不碰**（见上文警告；本轮没碰）。

## Theos 实测（2026-11-25，沙盒里实际跑过）

`export THEOS=/home/hatch/theos && make package`，**未通过**：

```
> Making all for application TrollLyricsDesk…
==> Building Swift support tools…
sh: 1: swift: not found
Failed to build swift-support: command failed: SPM_THEOS_BUILD=1 swift build ...
make: *** [TrollLyricsDesk.all.application.variables] Error 2
```

卡在第一步：Theos 编 Swift 应用要先编它自己的 swift-support 工具，
要 `swift` 命令；这台 Linux 沙盒没有 Swift 工具链（没有 swift/swiftc，
/usr/bin 里也没有），所以连 .mm 都没轮到编。不是我们的代码问题，是
环境缺 Swift。以前分屏/抖音的 Linux 烟囱编法能跑，是因为那两个是
纯 ObjC/Logos，没有 Swift；这个工程 Swift 是主体，Theos 在 Linux 上
编不了。Makefile 的 glob 和签名参数因此**仍未验证**（只做了静态检查：
文件都在、路径对得上）。Theos 路线要验，得在有 Swift 工具链的 Mac 上
跑；Xcode 路线仍以 GitHub Actions 为准（推 + 编等皇上批）。
残留已清（.theos/ 删了，没进提交）。

## Xcode 实测

没跑过：推 + 编等皇上批，GitHub Actions 的 run 是第一次真编。
Linux 没有 Xcode/swiftc，Swift 语法没法本地编译验证（和 1.0.0–1.0.3 一样）。

## 验收表（皇上的第七节，一项一项对）

| 验收项 | 状态 |
|---|---|
| Theos 编译（成功生成 .tipa） | **未通过**：沙盒实测卡在 swift-support（`swift: not found`），环境缺 Swift 工具链；Makefile 本身未验证 |
| Xcode 编译（Release 构建成功） | **待验证**：等皇上批推 + 编，GitHub Actions 是第一次真编 |
| HUD 启动（主 App 启动独立 HUD 进程） | **待验证**：startHUD / -hud  spawn 逻辑在代码里，须真机跑 |
| 全局显示（主屏幕及其他 App 上可见） | **待真机验证**：窗口注册、TrollStore 授权是否真给，都没验过 |
| 拖动（可拖动） | **待真机验证**：卡片拖动手势在代码里，托管后拖动和触摸是否正常须真机 |
| 拖动缩放（触摸响应正常，位置和尺寸可调整） | **待真机验证**：同上；App 内预览的捏合缩放在 FloatingLyricsPanel 里，HUD 卡片（LyricsHUDView）只有拖动没有缩放 |
| 歌词同步（主 App 更新后 HUD 实时刷新） | **待验证**：publish → 共享 plist → Darwin 通知 → HUD 更新的链路在代码里，须真机跑 |
| 生命周期（关闭、重启、卸载后没有残留 HUD） | **待验证**：stopHUD 的 dismiss 通知 + -exit 兜底是这一项的机制，须真机确认 |
| iOS 16（iPhone 13 Pro 实机验证） | **待验证**：皇上的真机项，不自己标通过 |

“能编译”和“能跨 App 全局显示”是两个验收项，分开记：上面没有一项是
把没跑过的标成通过的。

## 验证结果

`python3 check_1.0.5.py`：**FAILED: none**（见输出；v0.5 检查在第 13 节）。
本地能验的都验了；不能验的如实列在验收表里。

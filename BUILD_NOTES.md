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

## 锁屏歌词（1.0.1 build 14，v1.0.1 分支，2026-11-26）

设计见 `hidden_files/lockscreen-design/PLAN.md`；皇上 2026-11-26 01:47 改令做、
01:55 点「两样都要」（A＋B），09:28 定「只要添加锁屏」——底子用皇上重发的 1.0.0
（build 13，commit 5b68754），只加锁屏，1.0.6 的东西一律不用，1.0.6 之前的东西都忘掉。
版本 1.0.1，build 13→14（两 Info.plist＋pbxproj MARKETING_VERSION 四处；
产物名 桌面歌词-1.0.1.ipa）。

移植自 lockscreen 线的三笔（0c3318b build 15 初版＋cf0f29e WidgetView 错修＋
d461b62 build 16 ChatGPT 审查修复），逐文件对照纯底子手工合，只取锁屏的 hunk：
- 0c3318b 是做在 2288444 之上的（2288444 里有 1.0.6 的播放改进），与纯底子有出入，
  所以不是 cherry-pick；锁屏区放在「音乐检测」区后面（底子 ContentView 里没有
  PLAN 说的「歌词悬浮窗」区，悬浮窗开关在 PlaybackDashboardView 主界面）。

新文件：
- `LiveActivity/LyricsLiveActivity.swift`（ActivityAttributes＋ActivityConfiguration：
  锁屏横幅＋灵动岛 expanded/compact/minimal，三行歌词子视图共用；整体 @available(iOS 16.1, *)）
- `PlaybackEngine/LyricsLiveActivityController.swift`（单例，start/stop/update，
  监听 Activity 结束同步开关状态；串行合并队列＋Activity id 校验；整体 @available(iOS 16.1, *)）

改的文件：
- `PlaybackEngine/PlaybackCoordinator.swift`：加 `lastLiveState`／`lastLiveActivityID`＋
  `publishLiveLyrics()`（完整状态比较去重 BUG-02／04；没开锁屏时清去重状态 BUG-01；
  前奏推 ♪ 标题＋第一句当 next BUG-03；staleDate＝下一行＋5 秒 BUG-05；
  歌词限长 120 字 clipped()），poll() 末尾与换歌分支各调一次；
  加 `isRunning`＋幂等 `ensureRunning()`（锁屏开关先 ensureRunning 再 start，
  不直接调 start()，它会先 stop() 取消搜词任务）。
  `state = newState` 在位（底子没有 1.0.6 的回归，1.0.7 的修法不用再并）。
  **与 d461b62 的一处出入**：`lastLiveState` 存属性时补了 `@available(iOS 16.1, *)`
  （d461b62 原文没带；MinOS 15.0 下存 16.1 才有的类型当属性，理论上编不过；
  这可能是 1.0.4 build 17 Archive 失败的原因之一，未取到日志无法证实——见 check 的 OPEN）。
- `App/ContentView.swift`：「锁屏歌词」区（开始／停止＋状态文字，绑 controller；
  iOS 16.1 以下显示提示行）＋锁屏小组件添加提示；开启按钮先 `ensureRunning()`。
- `TrollLyricsDesk/Info.plist`：加 `NSSupportsLiveActivities` = true。
- `TrollLyricsWidget/TrollLyricsWidget.swift`：supportedFamilies 加 `.accessoryRectangular`
  （用 `if #available(iOS 16.0, *)` 运行时判断包起来——PLAN 说 iOS 15 会忽略不认识的
  family，但没编过不敢断言，稳妥写法是运行时判断；见 OPEN）。
- `TrollLyricsWidget/WidgetView.swift`：加锁屏分支（歌名小字＋当前句＋下一句），
  主屏幕布局原样抽进 `mainScreenView`，行内容一字未动；getTimeline 不动。
  `context` 未定义错已修：锁屏分支用 `@Environment(\.widgetFamily)`（cf0f29e）。
- `TrollLyricsWidget/TrollLyricsWidgetBundle.swift`：注册 `LyricsLiveActivity()`
  （#available 16.1；没注册，控制器开了 Activity 锁屏也显示不出来——ChatGPT 问题 3）。
- `TrollLyricsDesk.xcodeproj/project.pbxproj`：两新文件进 App target Sources，
  `LyricsLiveActivity.swift` 另进 Widget Extension Sources（双 Target 编同一文件，
  Attributes 不拆文件）；LiveActivity 组进主组；ActivityKit 弱链接
  （App 两配置＋Widget 两配置的 OTHER_LDFLAGS 各加 `-weak_framework ActivityKit`，
  共 4 处；底子的 .tbd 直链不动，不加 dynamic_lookup）。
  MARKETING_VERSION 四处 1.0.0→1.0.1。

没动的：`Overlay/` 全部、两边 entitlements（零新增）、MinOS 15.0、
逐字同步（LyricWord.swift／LyricSyncEngine.swift 不存在，不许现编假实现）。
**明确未并的**：Engine V2（e7e97df 的全部内容：MediaRemoteAdapter／LyricMatcher／
LyricStore 改动、Tests/、ENGINE_V2.md、产物名 1.0.4）；1.0.6 的播放改进
（2288444：空闲节能 poll 分档、保活开关＋stop()、build 14）——底子自带的
0.25 秒轮询、换歌取消搜词、缓存即播即显是底子原有的，留着。

检查：`python3 check_1.0.1.py`（106 PASS，FAILED: none，OPEN 17；
含三项否定检查：无 Engine V2、无 1.0.6 播放改进、无 BackBoard/-hud/dynamic_lookup）。

## 1.0.2 build 15（v1.0.1 分支，2026-11-26，1.0.1 只加五件小改）

- `App/AboutView.swift`：Telegram 行标签 `@seadragonjb`→`@Guhailon`；
  `openTelegram()` 改 `tg://resolve?domain=Guhailon`，退回 `https://t.me/Guhailon`；
  旧邀请链接与“私密频道无公开用户名”注释一并删掉。作者／QQ 群／版本行不动。
- `TrollLyricsDesk/LyricLogger.swift`：加 `clear()`（`FileManager.removeItem` 删日志文件；
  删后 `read()` 返回空，`log()` 下次写时重建；maxBytes／trim 不动）。
- `App/LogView.swift`：工具栏加复制（`UIPasteboard.general.string = LyricLogger.read()`，
  按钮短暂变“已复制”，`DispatchQueue.main.asyncAfter` 1.5 秒恢复）与清除
  （`.alert` 确认框“确定要清除全部日志吗？”，确认调 `LyricLogger.clear()` 并 `entries = []`）；
  复制／清除／分享三个按钮日志为空时都禁用。分享原样保留。UIPasteboard 与 Alert 都是老 API，MinOS 15.0 没问题。
- `App/ContentView.swift`：新共用背景 `AppBackgroundView`（没新建文件，不动 pbxproj）——读 App Group 三个键
  `animeBackgroundEnabled`／`backgroundOpacity`／`selectedBackgroundData`（`@AppStorage`，与 SettingsView 同一组声明）：
  开关关→纯黑；开且选过图→`UIImage(data:)` 全屏 scaledToFill，不透明度 = 1 − backgroundOpacity；
  开但没选图→原来的紫／黑／蓝渐变（同样套这个不透明度）。用到四处：PlaybackDashboardView（根视图，主界面）、
  SettingsHubView、ContentView、AboutView（各替掉写死渐变）；选图后立即生效。悬浮窗与小组件不动。
- `App/PlaybackDashboardView.swift`：悬浮歌词区「显示悬浮歌词窗」开关下方加
  「固定悬浮窗位置」开关（`@AppStorage("floatingLyric.positionLocked", App Group)`，默认 false，
  与 enabled／textColorHex 同一组声明）。
- `Overlay/FloatingLyricViewController.swift`：新键 `floatingLyric.positionLocked`（Bool，未设置时
  `UserDefaults.bool` 返回 false，与默认一致）；`handlePan` 开头 `guard !positionLocked else { return }`，
  锁住时拖动不生效；位置保存（`savePosition`）与启动恢复（`restorePosition`）一字未动——位置本来就会记住，开关只锁拖动。
- `Overlay/FloatingLyricViewController.swift`（第五件）：提示文字移出悬浮窗——`hintLabel` 整个删掉
  （声明、卡片底部小字、约束、`refresh()` 换文案行、`apply()` 里 `hintLabel.alpha` 全删）；歌词 stack 改锚卡片底部
  （上下各留 12pt，UILabel 在整行高度内垂直居中）。悬浮窗从此只显示歌词；位置锁 guard、savePosition/restore 一字未动。
- `App/PlaybackDashboardView.swift`（第五件）：歌曲卡片和「显示悬浮歌词窗」开关之间加居中提示行
  （`positionLocked ? "悬浮窗口 · 已固定 · 双击隐藏" : "悬浮窗口 · 长按拖动 · 双击隐藏"`，20pt 半粗体、白 85%）；
  「桌面歌词」标题横向居中（`ZStack(alignment: .topTrailing)`，标题 `frame(maxWidth: .infinity, alignment: .center)`，
  齿轮 Menu 仍固定右上角原位，顶部 80 的 padding 不动）。
- 版本 1.0.2，build 14→15（两 Info.plist＋pbxproj MARKETING_VERSION 四处；
  产物名桌面歌词-1.0.2.ipa）。其余与 1.0.1 一字未动。

检查：`python3 check_1.0.2.py`（139 PASS，FAILED: none，OPEN 20；
新增 §6.6 十项：Telegram 三项、LyricLogger 两项、LogView 五项；新增 §6.7 八项：背景图任意更换；
新增 §6.8 六项：悬浮窗固定位置开关；新增 §6.9 七项：提示文字移到界面＋标题居中；
§6 红线收窄：Overlay/ 只许 FloatingLyricViewController.swift 一处改动）。

## 1.0.3 build 16（v1.0.1 分支，2026-11-26，1.0.2 只加授权激活）

- `Lyrics/LyricStore.swift`：新 `ActivationStore`（App 与 Widget 两个 target 共用，只放 Foundation 层面的键与读写）：
  接口地址 `https://guhailong-repo.pages.dev/api/verify`、键 `tld.activated`／`tld.activationType`、
  `isActivated`／`activationType`／`markActivated(type:)`。App 里没有任何码值。
- `App/ActivationView.swift`（新文件，pbxproj 四处注册：PBXBuildFile＋PBXFileReference＋App 组 children＋App Sources）：
  `ActivationGateView`（@AppStorage 读 App Group 标记，未激活显示 ActivationView，否则显示主界面）、
  `ActivationVerifier.verify(code:)`（码 trim＋大写后 POST /api/verify，`URLSession.shared.data(for:)`，iOS 15.0+；
  valid＋type 才返回类型，码不对抛 wrongCode，没网／非 200／解不出抛 needsNetwork）、
  `ActivationView`（输码框＋激活按钮，全屏，背景共用 AppBackgroundView；成功写标记＋`WidgetCenter.reloadAllTimelines()`；
  日志只记成功／码不正确／网络失败，绝不记码值）。
- `App/TrollLyricsDeskApp.swift`：`makeRootViewController` 改包 `ActivationGateView { PlaybackDashboardView() }`，
  environmentObject 照旧透传。
- `Overlay/FloatingLyricViewController.swift`：`applyVisibility` 加 `|| !ActivationStore.isActivated`，
  未激活悬浮窗隐藏；0.25s 定时刷新，激活后自动恢复。
- `TrollLyricsWidget/WidgetView.swift`：body 顶层先判激活，未激活显示「请先在 App 内激活」占位
  （主屏幕／锁屏两种 family 都走这里）；激活后走原有分支。
- 锁屏（LiveActivity／LyricsLiveActivityController／Widget 锁屏分支）一字未动；MinOS 15.0 不动；
  `data(for:)` 与 `.autocapitalization(.allCharacters)` 都是 iOS 15 老 API。
  检测引擎照常在启动时自动跟随（激活前也在跑，但主界面／悬浮窗／小组件三处都不显示歌词，激活后即时恢复，不用重启）。
- 版本 1.0.3，build 15→16（两 Info.plist＋pbxproj MARKETING_VERSION 四处；
  产物名桌面歌词-1.0.3.ipa）。

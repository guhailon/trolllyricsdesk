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

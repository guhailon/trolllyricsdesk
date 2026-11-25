# TrollLyricsDesk

透明动漫歌词桌面（TrollStore 版）：SwiftUI App + WidgetKit 桌面小组件，
把正在放的歌的歌词显示在主屏幕上。

- Product Name: TrollLyricsDesk
- Interface: SwiftUI / Language: Swift
- Deployment Target: iOS 16.0
- Bundle ID: `com.hailong.TrollLyricsDesk`
- Widget Extension: WidgetKit（`TrollLyricsWidget`）
- App Group: `group.com.hailong.TrollLyricsDesk`（App 和 Widget 共用，共享歌词状态）
- 版本：1.0.1

## 结构（Lee 02:15 定的新树，原样）

```
TrollLyricsDesk/
├── App/
│   ├── TrollLyricsDeskApp.swift    ← Lee 原样
│   ├── ContentView.swift           ← Lee 原样（加了两条 NavigationLink）
│   ├── PlaybackDashboardView.swift ← Lee 原样（播放状态面板）
│   ├── SettingsView.swift          ← Lee 原样（02:37 发的，已按原样换上）
│   └── LyricsSearchView.swift      ← Lee 原样（搜索 + 导入界面；树里没单列，
│                                     但 PlaybackDashboardView 链到它，必须留，放 App/）
├── PlaybackEngine/                 ← Lee 原样：PlaybackState / PlaybackAdapter /
│                                     PlaybackCoordinator / LyricMatcher
├── MusicProviders/                 ← Lee 原样：MusicTrack / AppleMusicAdapter /
│                                     NetEaseAdapter / QQMusicAdapter / ExternalTrackInput
├── Lyrics/                         ← Lee 原样：LRCLibClient / LyricParser /
│                                     LyricStore / LocalLRCImporter
├── TrollLyricsDesk/
│   ├── LyricLogger.swift           ← 写 Documents/TrollLyricsDesk.log
│   ├── Info.plist                  ← 加了 NSAppleMusicUsageDescription（Lee 发的文案原样）
│   ├── TrollLyricsDesk.entitlements
│   └── Assets.xcassets/            ← 占位图标（Lee 之后可以换）
└── TrollLyricsWidget/
    ├── TrollLyricsWidget.swift     ← Lee 原样（getTimeline 已换成他发的新版）
    ├── WidgetView.swift            ← Lee 原样
    └── TrollLyricsWidgetBundle.swift ← Lee 原样（@main 入口）
```

Lee 发的文件一字未改。`TrollLyricsWidgetBundle.swift` 不在 Lee 的树里
单列，但 Widget Extension 必须有 `@main` 入口，所以单独放了一个文件。
`TimelineProvider.swift` 不用另写——Lee 的 `TrollLyricsWidget.swift`
里已经包含了 `TrollLyricsProvider` 的实现。

这一轮改动（Lee 02:15–02:20 定）：
- MusicTrack 加了 Equatable（PlaybackState 要直接比相等）。
- NetEase/QQ 适配器换成新版：不带协议，只 `makeTrack` 拼 MusicTrack。
  `MusicPlatformAdapter.swift`（旧协议）删了，被 `PlaybackAdapter` 取代。
- `LyricsSearchView.makeTrack()` 里两处 `importTrack` 改成 `makeTrack`
  （新适配器没有 importTrack，不改编不过）。
- `LyricStore.currentElapsed` 的算法已是 Lee 定的公式
  （播放中：`elapsedWhenPaused + date.timeIntervalSince(startedAt)`；
  暂停：`elapsedWhenPaused`），不用改。
- `PlaybackCoordinator.savePlayback` 的歌名检查改成歌名 + 歌手双匹配
  （Lee 02:20 定，避免同名歌曲误更新）。
- `requestMusicPermission`（Lee 发的函数原样）放进
  `MusicProviders/AppleMusicAdapter.swift`，和 MediaPlayer 用法放一起。
- “开始检测音乐”按钮先申请媒体资料授权，授权了才开始检测
  （Lee 02:21 定）。

## 现在能做什么

- App：调透明度/字体大小，点“加载测试歌词”把演示词写进 App Group，
  小组件跟着刷新（Lee 的 ContentView 原样功能）。
- 统一音乐播放引擎（Lee 02:15 新结构）：PlaybackDashboardView 面板，
  PlaybackCoordinator 每秒问适配器正在放什么歌；换歌就 LRCLIB 搜词，
  LyricMatcher 按歌名/歌手/时长打分挑最合的一份上墙；状态变了就更新
  快照。AppleMusicAdapter 用系统播放器读 Apple Music 正在放的歌。
- 歌词搜索与导入（Lee 的 LyricsSearchView，已挂进 ContentView 和播放面板）：
  选平台（Apple Music / 网易云 / QQ音乐 / 手动输入），在线搜词
  （LRCLIB）点一首上墙，或导入本地 `.lrc`；找不到显示提示，绝不编词。
  选词后快照按播放中算（isPlaying: true，Lee 02:04 定）；导入本地
  LRC 后按未播放算（isPlaying: false）。
- 小组件：主屏幕显示当前歌名/歌手 + 当前这一句词；时间线按每句词的
  时间预先排好（Lee 发的新版 getTimeline），没词时显示“打开 App 加载歌词”。
- 没有内置歌、没有授权码。

## ⚠️ 跟随机制又变了，先说清楚（Lee 02:30：改回 MediaRemote 跟随）

**现在跟随走 MediaRemote，能读任何 App 正在放的歌。** 02:15 新结构
把上一版的 `NowPlayingFollower` 删了、改成只跟 Apple Music；Lee 02:30
定了改回来：新文件 `MusicProviders/MediaRemoteAdapter.swift`
（`PlaybackAdapter`，`MRMediaRemoteGetNowPlayingInfo` + 时间戳反推 +
歌名清洗），面板改接它，QQ音乐/酷我/网易云/Apple Music 正在放的歌
都能跟。`AppleMusicAdapter.swift` 还留在工程里（Lee 的文件），但面板
不再接它。MediaRemote 的两项 entitlements 和 OTHER_LDFLAGS 链接参数
跟随又用上了（02:26 留不留的问题不用再定，留着）。
沙盒 App 在 iOS 16.5 上能不能读到，只有真机说了算；读不到面板就显示
“没有检测到可读取的音乐”，不崩。

另外：**“开始检测音乐”按钮和面板打开（onAppear）现在都是直接开始检测，
都不先问授权**（Lee 02:26 定 onAppear 不用授权；Lee 02:30 定改回
MediaRemote，按钮的授权门也撤了——MediaRemote 不需要媒体资料授权）。

## 诚实话（限制，先说清楚）

1. **MediaRemote 跟随还没在真机上验证过。** 沙盒 App 在 iOS 16.5 上
   能不能读到任何 App 正在放的歌（QQ音乐/酷我/网易云/Apple Music），
   得真机试；读不到面板就显示“没有检测到可读取的音乐”。和歌词墙
   那个跟随同一路子、同一句实话。
2. **网易云/QQ 适配器现在只是数据模型。** Lee 新发的适配器只负责
   把歌名/歌手/专辑拼成统一的 MusicTrack，不调网易云/QQ 的网络接口；
   查词只走 LRCLIB。读不到那两个 App 的私有播放状态和内存里的实时
   歌词，不要声称能直接跟随它们。上一版的网易云/QQ 网络搜索代码
   已随 LyricSearchService.swift 一起删掉，网易云加密的问题也就不存在了。
3. **小组件不是每秒实时同步。** WidgetKit 的刷新由系统节流；
   时间线按每句词的时间预先排好，App 里改了快照会立即 `reloadAllTimelines`。
   小组件是“接近实时”，App 本身才是实时视图。
4. **没在 Mac 上编过。** 这台是 Linux，没有 Xcode/swiftc，
   Swift 语法没法本地编译验证；等推上去走 macOS Actions 编。
   构建流程见 `.github/workflows/build.yml`（不签名导出 → ldid 签名 → 打 IPA）。
   MediaPlayer.framework 的链接（pbxproj 里加进 App Target 的 link phase）
   也是第一次编才实测。
5. **SettingsView 是 Lee 原文件。** 02:37 发的，已按原样换到 App/；7 个 @AppStorage 键已按 Lee 02:39 的提醒迁到 App Group 共享区（`UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk")`），其余代码没动。⚠️ 小组件还是读快照（LyricSnapshot）里的透明度/字体，不是这几个共享键——小组件读哪边，等 Lee 定。逐字卡拉OK 只是设置里的一个选项，逐字解析还没实现，是后续工作。
6. **LyricsSearchView 已挂进 ContentView 和播放面板。** Lee 发的
   NavigationLink 都加进去了（ContentView 其余部分一字未动）。
7. **图标是占位。** 紫蓝渐变 + 音符 + “歌词”二字，Lee 之后可以换。
8. **LyricParser 会保留空歌词行**（Lee 的解析器原样：只有时间戳没词的行
   也会变成一条空文本的行），小组件上那一行就是空白。
9. **不要用 Textyl。** Lyrication 作者的私有歌词接口，作者明说不要给
   别的项目用；我们只用公开免费的 LRCLIB，AGPL 代码一行也没抄。

## 构建（macOS Actions）

推代码就自动跑 `.github/workflows/build.yml`：
`xcodebuild archive`（不签名）→ `ldid` 按 entitlements 签名 →
打 `TrollLyricsDesk-1.0.1.ipa` → 上传 Artifacts。

App 的 entitlements 含 App Groups + 两个 mediaremote 读权限
（`com.apple.mediaremote.now-playing-read-access` /
`com.apple.mediaremote.full-now-playing-read-access`，跟歌词墙
跟随模式同一份证据：LyricFever #94 里 Mx-Iris 对 mediaremoted 的逆向）。
这两项现在是上一版 MediaRemote 跟随留下的，PlaybackCoordinator 不用它们。

## 验证

```sh
python3 check_1.0.1.py
```

检查结构、包名/组名一致、Lee 文件原样标记、无内置歌、无授权码、
无 Textyl/AGPL 代码、LRC 样本解析、plist/entitlements/pbxproj 有效、
图标尺寸。未验证的项（macOS 编译、真机）会如实列出来。

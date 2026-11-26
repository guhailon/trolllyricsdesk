# TrollLyricsDesk

透明动漫歌词桌面（TrollStore 版）：SwiftUI App + WidgetKit 桌面小组件，
把正在放的歌的歌词显示在主屏幕上。

- Product Name: TrollLyricsDesk
- Interface: SwiftUI / Language: Swift
- Deployment Target: iOS 16.0
- Bundle ID: `com.hailong.TrollLyricsDesk`
- Widget Extension: WidgetKit（`TrollLyricsWidget`）
- App Group: `group.com.hailong.TrollLyricsDesk`（App 和 Widget 共用，共享歌词状态）
- 版本：1.0.3

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
打 `TrollLyricsDesk-1.0.3.ipa` → 上传 Artifacts。

App 的 entitlements 含 App Groups + 两个 mediaremote 读权限
（`com.apple.mediaremote.now-playing-read-access` /
`com.apple.mediaremote.full-now-playing-read-access`，跟歌词墙
跟随模式同一份证据：LyricFever #94 里 Mx-Iris 对 mediaremoted 的逆向）。
这两项现在是上一版 MediaRemote 跟随留下的，PlaybackCoordinator 不用它们。

## 验证

```sh
python3 check_1.0.3.py
```

检查结构、包名/组名一致、Lee 文件原样标记、无内置歌、无授权码、
无 Textyl/AGPL 代码、LRC 样本解析、plist/entitlements/pbxproj 有效、
图标尺寸。未验证的项（macOS 编译、真机）会如实列出来。

## 锁屏歌词（1.0.1 build 14，两样都要）

- **A 灵动岛 Live Activities（iOS 16.1+）**：设置页 ContentView「锁屏歌词」区，
  点「开启锁屏歌词」就在锁屏上常驻一张歌词横幅（15 Pro 还有灵动岛收起／展开／最小三态）。
  数据链路复用检测引擎：`PlaybackCoordinator.poll()` 末尾 `publishLiveLyrics()`，
  按 0.25 秒轮询算当前行，**完整状态变了才推**（一行 4–5 秒才切一次，远低于系统每秒一次的上限）；
  没词时同一首歌只推一次「♪ {歌名}」占位；`staleDate` 是下一行歌词的时间＋5 秒。
  限制（系统定的）：单个 Live Activity 最长 8 小时，到期横幅自动消失，要回 App 再点开关；
  更新频率、常亮显示都由系统定。
- **B 锁屏小组件（iOS 16.0+）**：`supportedFamilies` 加 `.accessoryRectangular`，
  复用 Widget 现成的逐行预排时间线，不写新链路；用户自己长按锁屏 → 自定 → 添加小组件；
  刷新节奏由系统定，不保证实时；外观由系统着色。
- 两条路子都是系统公开接口，**零新增 entitlements**，MinOS 保持 15.0；
  ActivityKit 弱链接（App＋Widget 各两配置的 `OTHER_LDFLAGS` 加 `-weak_framework ActivityKit`），
  iOS 15 的机器上 App 能正常启动，锁屏开关显示「需要 iOS 16.1 或以上」。
  取色器键 `floatingLyric.textColorHex` 复用，锁屏横幅颜色可能被系统压暗，真机不对就退回白色。
- 诚实话：**iPhone 11 没有常亮显示，锁屏黑了就什么都看不到**，歌词只在锁屏亮着时显示；
  只有 15 Pro 的常亮显示能让锁屏歌词一直亮着。锁屏歌词是逐句同步，不是逐字。
  LiveContainer 下（iOS 27.0.1）理论上能用，没真机验过。
- 底子是皇上重发的 1.0.0（build 13）纯底子，只加锁屏：Engine V2 与 1.0.6 的播放改进一律未并；
  Overlay 悬浮窗一个字没动；v0.5 BackBoard 代码一个字没动。

## 1.0.2 build 15：Telegram 行改公开频道＋日志页加清除／复制＋背景图任意更换＋悬浮窗固定位置＋提示文字移到界面＋标题居中

- **Telegram 频道行**：SeaDragon 越狱源已公开，用户名 @Guhailon（2026-11-26 皇上改的，t.me/Guhailon 已核实能打开）。
  关于页 Telegram 行标签 `@seadragonjb` 改成 `@Guhailon`；点开改走 `tg://resolve?domain=Guhailon`
  （公开用户名现在能 resolve），没装 Telegram 退回 `https://t.me/Guhailon`。
  旧邀请链接（`tg://join?invite=I-I8aw7HUAw1NGY9`／`https://t.me/+I-I8aw7HUAw1NGY9`）已从 AboutView 删掉——
  公开后旧链接目前还能用，但行里不再用它。
- **日志页**：工具栏分享旁边加两个按钮（日志为空时都禁用）：
  **复制**把整份日志原文（同分享的 `LyricLogger.read()`）写进剪贴板，按钮短暂变“已复制”约 1.5 秒后恢复；
  **清除**先弹确认框（“确定要清除全部日志吗？”＋取消），确认后 `LyricLogger.clear()` 删掉日志文件，
  页面刷新成空状态；删后 `read()` 返回空，`log()` 下次写时重建。分享按钮原样保留。
  `LyricLogger.clear()` 只删文件，不改 maxBytes／trim 逻辑。
- **背景图任意更换**：之前全工程只有 SettingsView 写 `animeBackgroundEnabled`／`backgroundOpacity`／
  `selectedBackgroundData` 三个键、没有任何界面读它们，选了图也换不了背景。
  新共用背景 `AppBackgroundView`（在 `App/ContentView.swift` 里，没新建文件）：开关关→纯黑；
  开且选过图→全屏显示这张图，不透明度 = 1 − backgroundOpacity（默认 0.25 即图 75% 显示，底下黑色）；
  开但没选图→原来的紫／黑／蓝渐变（同样套这个不透明度）。用到主界面（PlaybackDashboardView，根视图）、
  设置中心、设置页、关于页四处；选图后立即生效（@AppStorage 实时刷新）；悬浮窗与小组件不动。
- **悬浮窗固定位置**：主界面悬浮歌词区「显示悬浮歌词窗」开关下方加「固定悬浮窗位置」开关
  （App Group 键 `floatingLyric.positionLocked`，默认关）。打开后悬浮窗拖不动，
  主界面提示行变成“悬浮窗口 · 已固定 · 双击隐藏”（双击隐藏仍可用）；关掉又能拖。
  位置本来就会记住（拖完存相对坐标、启动时恢复），开关只锁拖动，保存／恢复代码一字未动。
- **提示文字移到界面＋标题居中**：悬浮窗卡片底部的提示小字整个删掉（悬浮窗只显示歌词），
  提示行移到主界面歌曲卡片和「显示悬浮歌词窗」开关之间，文案跟固定开关走
  （“悬浮窗口 · 长按拖动 · 双击隐藏”／“悬浮窗口 · 已固定 · 双击隐藏”）；歌词 stack 上下各留 12pt 居中。
  「桌面歌词」标题横向居中（ZStack 居中标题＋齿轮仍固定右上角原位，顶部 80 的 padding 不动）。
- 版本 1.0.2，build 14→15（两 Info.plist＋pbxproj MARKETING_VERSION 四处；产物名桌面歌词-1.0.2.ipa）。
  其余内容与 1.0.1 一字未动。

## 1.0.3 build 16：首次打开要激活码（服务器验证）

- **授权激活页**：整个 App 第一次打开就要码。启动时读 App Group 的激活标记（`tld.activated`），
  未激活就全屏显示激活页（输码框＋激活按钮），不进主界面；验过后把标记＋类型写进 App Group
  （`tld.activated=true`、`tld.activationType=master/code`），以后直接进主界面，不用重启。
- **服务器验证**：POST `https://guhailong-repo.pages.dev/api/verify`，body `{"code": "..."}`；
  码先 trim 再大写（服务端同样不分大小写）。回 `{"valid": true, "type": "master"|"code"}` 才放行；
  码不对提示「激活码不正确」；没网／服务端不通提示「需要联网激活」，绝不放行。
  码表只在服务端，App 源码与仓库里没有任何码值。
- **小组件**：未激活时显示「请先在 App 内激活」占位，不显示歌词；激活后刷新时间轴恢复正常。
- **悬浮窗**：未激活不显示悬浮歌词（激活后 0.25s 刷新时自动恢复，不用重启）。
- 锁屏代码（Live Activities＋锁屏小组件）一字未动。版本 1.0.3，build 15→16
  （两 Info.plist＋pbxproj MARKETING_VERSION 四处；产物名桌面歌词-1.0.3.ipa）。

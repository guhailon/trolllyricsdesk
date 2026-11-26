# TrollLyricsDesk newbase — RUN 记录（1.0.0 新底子＋五件＋激活＋锁屏＋Universal 兼容层）

底子：Lee 2026-11-26 20:07 发的 QQ 闪传 `桌面歌词-1.0.0 2.zip`（81.07 MB，SHA256 `26f4400d…`，原件 `~/workspace/user/files/桌面歌词-1.0.0-2.zip`）。
参考：Lee 2026-11-26 20:30 发的 `TrollLyricsDesk-1.0.4-Universal-source.zip`（924,383 B，SHA256 `f86b603b…`，已解开 `/tmp/tld104u`，只作 LiveContainer 兼容性参考，**不允许整包覆盖**）。
皇上 2026-11-26 20:36 定版：以新底子干净工程为主，选择性移植 Universal 的运行环境检测、启动兼容逻辑及必要的权限适配；保留新底子全部歌词同步修正、逐歌偏移、桌面悬浮歌词、锁屏歌词和激活验证；不要 TCP 桥、不要独立客户端、不要两个 IPA；包名保持 com.ycwl.Lyrics。

---

## 第一阶段：源码差异检查（2026-11-26 晚，合并前）

对照三棵树：新底子（`~/workspace/trolllyricsdesk-newbase`，分支 newbase，本地，未提交）／Universal（`/tmp/tld104u`）／咱们已验证的参考提交（`~/workspace/trolllyricsdesk-1.0.1`，v1.0.1 分支：锁屏 680c7cf＋6549b68、五件 c35a053／e79218f／177a25e／7e39edf、激活 0e1e014）。

### 新底子身份（已核实）
- 1.0.0／build 17，包名 **com.ycwl.Lyrics**，显示名桌面歌词，MinOS 15.0，App Group **group.com.hailong.TrollLyricsDesk**（entitlements 与 LyricStore.groupID 一致，与咱们的线相同——激活／锁屏移植不用换 group）。
- entitlements 已含全部私有权限（no-sandbox、platform-application、frontboard launchapplications、backboard client、QuartzCore、springboard 各键、RunningBoard、mach 白名单、IOSurface）：Universal 那边没有要补的权限键。
- 歌词同步修正（Universal 全缺，必须保留）：逐歌时间偏移（`timeOffset`／`offsetKeyPrefix`／`stableSongIdentity`）、noMusic 清悬浮窗（`noMusicKey`，poll 无播放器时清 state）、歌词塞 artist 字段识别（`artistCarriesLyric`／`LyricLocation`／`songIdentityParts`）、刷新节流（`isDisplayEquivalent`，只有可见内容变才写 state）、同歌实时同步（`syncLiveLyricsAndProgress`）、悬浮窗开关同步通知（`floatingEnabledChanged`）、锁屏／解锁后确认才重建悬浮窗（`needsRebuildOnUnlock`＋`isProtectedDataAvailable` 轮询）。
- 新底子已有但 Universal 旧的：TLDSSceneDelegate 用 `hasPrefix:@"TLDSFloatingLyric"` 匹配悬浮 scene、悬浮窗高度按歌词行数动态算、`floatingWindow` 赋值供锁屏解锁恢复用；Overlay 的 TLDSAppDelegate 含锁屏重建回调。**这两处保新底子，不用 Universal 的旧写法**（Universal 是等值匹配＋固定 118 高）。
- 新底子已有的五件碎片：SettingsView 已有 `animeBackgroundEnabled`／`backgroundOpacity`／`selectedBackgroundData` 三个键（第 129–155 行，用 `UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk")`，与 AppBackgroundView 读的键一致）；LogView 已有「清理日志」按钮＋`clearLogs()`＋`LyricLogger.clear()`（第 57 行，两边都有）。**五件第 2 件只差「复制」按钮**，第 3 件可直接用现有键。

### Universal 有而新底子缺的（可移植清单）
- **运行环境检测**（`Lyrics/LyricStore.swift`）：`isLiveContainer`——Info.plist 键 `TLDSLiveContainer` 为 true，或包路径／可执行路径／argv[0] 含 `livecontainer` 或 `/lcapps/`，或类 `LCAppDelegate` 存在；`defaults` 在宿主时改走 `.standard`（不用 App Group）。**只移植检测函数＋defaults 三元，不要动新底子的其他 LyricStore 逻辑。**
- **启动兼容**（`Overlay/TLDSAppDelegate.m`）：`TLDSInstallNativeWindowFix`（UIRootSceneWindow swizzle：背景透明＋windowLevel 10000）；`application:didFinishLaunching` 里 `if (!isHosted) { 装 native window fix；启动悬浮 Overlay }`——**宿主模式不装 fix、不启动悬浮窗**。`Overlay/TLDSSceneDelegate.m`：宿主时强制 `isMain = YES; isFloating = NO`。`App/TrollLyricsDeskApp.swift`：`@objc func isHosted()`（TLDSRuntime 已有，两边同名同结构，直接加方法）；`BackgroundKeepAlive` 宿主时不启动（新底子 TrollLyricsDeskApp.swift:100 现在无条件 start）。
- **宿主模式行为分支**（只在真正宿主时走，巨魔模式一字不动）：`PlaybackCoordinator.publishLiveLyrics()` 开头 `guard !isLiveContainer else { return }`；5 处 `WidgetCenter.reloadAllTimelines()` 加 `if !isLiveContainer`（ActivationView、ContentView、SettingsView、LyricsSearchView、PlaybackCoordinator 内 3 处）；Dashboard 宿主时显示「LiveContainer · 应用内歌词模式」＋0.25s TimelineView 应用内歌词（带暂停／开始按钮）；ContentView 锁屏区宿主时显示「LiveContainer 模式不支持锁屏歌词和小组件」。
- **激活**（`App/ActivationView.swift` 全新＋`Lyrics/LyricStore.swift` 内 `ActivationStore`）：接口 `https://guhailong-repo.pages.dev/api/verify`，键 `tld.activated`／`tld.activationType`，与咱们 0e1e014 同款。**移植以咱们的 0e1e014 为第一参考**，Universal 版做交叉核对。
- **锁屏**（`LiveActivity/LyricsLiveActivity.swift`＋`PlaybackEngine/LyricsLiveActivityController.swift` 全新＋`PlaybackCoordinator.publishLiveLyrics()`＋`LiveLyricKey`）：与咱们 680c7cf＋6549b68 同款。**移植以咱们的为准**，但 publishLiveLyrics 要带上 Universal 的宿主 guard。
- **五件**（与咱们 c35a053／e79218f／177a25e／7e39edf 同款，**以咱们的为准**）：Telegram @Guhailon（AboutView 现在还是旧的 @seadragonjb＋invite 链接，整段换）；日志复制按钮（只补复制，清理已在）；AppBackgroundView（ContentView 内新增共用视图，用到 SettingsHubView／ContentView／AboutView／PlaybackDashboardView）；悬浮窗固定位置（键 `floatingLyric.positionLocked`，Dashboard 加 Toggle，FloatingLyricViewController handlePan 开头 guard）；提示移入界面＋标题居中（FloatingLyricViewController 的 hintLabel 整个删，Dashboard 加居中提示行，标题 ZStack 居中）。
- **Widget**（`TrollLyricsWidget/WidgetView.swift`）：未激活占位「请先在 App 内激活」＋accessoryRectangular 锁屏分支（`family == .accessoryRectangular` 时 lockScreenView）。App Info.plist 加 `NSSupportsLiveActivities=true`（Universal 有，新底子缺）。

### 直接冲突的文件及处理方案
| 文件 | 冲突点 | 处理 |
|---|---|---|
| Lyrics/LyricStore.swift | 新底子同步修正（~200 行）vs Universal 的 isLiveContainer＋defaults 三元＋ActivationStore | 保新底子全文，只加 isLiveContainer、defaults 三元、ActivationStore 枚举 |
| PlaybackEngine/PlaybackCoordinator.swift | 新底子节流／同步／noMusic vs Universal 的 LiveLyricKey／publishLiveLyrics／widget guard | 保新底子全文，只加 LiveLyricKey／lastLiveState／lastLiveActivityID／isRunning／ensureRunning／publishLiveLyrics（含宿主 guard）及调用点 |
| Overlay/FloatingLyricViewController.swift | 新底子动态高度／多行显示 vs Universal 单行＋fittedFontSize＋固定位置＋hint 已删＋激活隐藏 | 保新底子显示逻辑，只合：positionLocked 键＋handlePan guard、删 hintLabel、激活时 `view.isHidden = !floatingEnabled \|\| !ActivationStore.isActivated` |
| Overlay/TLDSAppDelegate.m | 新底子锁屏重建回调 vs Universal 的 NativeWindowFix＋isHosted 分支 | 保新底子全文，只加 NativeWindowFix 函数及 didFinishLaunching 里的 isHosted 分支 |
| Overlay/TLDSSceneDelegate.m | 新底子 hasPrefix 匹配＋动态高度 vs Universal 等值匹配＋固定 118＋宿主强制 isMain | 保新底子全文，只加宿主强制 `isMain = YES; isFloating = NO` |
| App/ContentView.swift | 新底子同步修正相关 vs Universal 的 AppBackgroundView＋锁屏区＋宿主文案 | 保新底子，加 AppBackgroundView  struct＋四处引用、锁屏区（含宿主文案）、widget guard |
| App/PlaybackDashboardView.swift | 新底子 vs Universal 的位置锁 Toggle＋标题居中＋提示行＋宿主应用内歌词 | 按五件＋兼容层逐段合 |
| App/SettingsView.swift、App/LyricsSearchView.swift | 小幅差异＋widget guard | 只合 widget guard（LyricsSearchView 的平台 Picker 不属于本次范围，不并） |
| App/AboutView.swift | 旧 @seadragonjb＋invite 链接 vs @Guhailon | 整段换成五件版 |
| App/LogView.swift | 新底子已有清理 vs Universal 的复制＋清除工具栏 | 只补复制按钮＋copiedFeedback，不动现有清理 |
| TrollLyricsWidget/WidgetView.swift | 新底子主屏幕视图 vs Universal 的激活占位＋锁屏分支 | 按 Universal 的 Group 分支结构合（未激活→锁屏 family→主屏幕） |
| .github/workflows/build.yml | 只有产物名／workflow 名／版本号文字不同，结构相同 | **保新底子的**（workflow「Build」，产物 `桌面歌词-1.0.0.ipa`），不并 Universal 的 |
| TrollLyricsDesk/Info.plist、TrollLyricsWidget/Info.plist | 包名／版本／build 不同 | 保新底子（com.ycwl.Lyrics、1.0.0），只加 App 的 NSSupportsLiveActivities；最终 build 升 18 |
| TrollLyricsDesk.xcodeproj/project.pbxproj | Universal 多了 LiveActivity／LyricsLiveActivityController／ActivationView 三个文件＋ActivityKit 弱链接 | 按咱们 680c7cf／0e1e014 的做法加文件进 App Sources（LyricsLiveActivity.swift 另进 Widget Sources）、ActivityKit 弱链接共 4 处（两 target 各 2 处：弱链接＋.tbd 直链不动） |

### Universal 里不采用的东西及原因
- **版本号／包名**（1.0.4／Desk2）：皇上令包名不动；版本保持 1.0.0。
- **Core/ 新引擎、额外 MusicProviders**：diff 证实两边 Core/ 与 MusicProviders/ 一字不差，没有要并的。
- **LIVE_CONTAINER.md 的独立构建路线**（Build LiveContainer workflow、scripts/build-livecontainer.sh、宿主签名 IPA）：与皇上「不要两个 IPA」冲突，且 scripts/ 在包里是空的；只用 UNIVERSAL.md 的运行时检测路线。
- **FloatingLyricViewController 的单行＋fittedFontSize 显示、SceneDelegate 固定 118 高、等值 scene 匹配**：相对新底子是回退，不并。
- **PlaybackCoordinator 的 `state = newState` 无条件赋值**：会破坏新底子的刷新节流，不并。
- **Universal 的 RUN_1.0.1／RUN_1.0.2／README（写 1.0.3／iOS 16.0）**：内容与本树不符，不并；MinOS 以 pbxproj 的 15.0 为准。

### 移植顺序（分支 newbase）
1. 干净底子（1.0.0／build 17 原样）2. 五件 3. 激活 4. 锁屏 5. Universal 兼容层。最终 head 保持 1.0.0、build 18。**不要 TCP 桥（无 38473、无 DualProcessBridge）、不要独立客户端、不要双 IPA。**

---

## 第二阶段：合并（待填）

## 第三阶段：编＋验（待填）

## 待真机验证的功能清单（待填）

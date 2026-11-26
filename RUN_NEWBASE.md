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

## 第二阶段：合并（2026-11-26 晚，已完成；分支 newbase，远端 guhailon/trolllyricsdesk）

远端 newbase 分支先用 git-data API POST 在已存在的 517bd4a（main 远端 HEAD，已核对
`gh_push.py check … main main` → already_in_sync）上建 ref（201），再逐笔 check＋推。
五笔提交（每笔父提交都是上一笔，全部 fast_forward_one_commit 推上）：

1. `5034a3f` — 1.0.0 build 17：干净底子（新底子原样，newbase 线起点）。
   81 个文件：旧 HUD／／sources／、TLAppRoot、旧 AppIcon、Makefile、RUN_1.0.4／1.0.5 删；
   新 Overlay／、AppIconV2、TrollLyricsDeskApp.swift、RUN_NEWBASE.md 加；
   check_1.0.5.py→check_1.0.3.py 记为改名（底子自带文件，原样）。hidden_files/ 未进。
2. `a1aff36` — 1.0.2：五件小改（5 个文件，＋124／−61）。
   - AboutView：Telegram 行 @seadragonjb→@Guhailon，openTelegram 改
     tg://resolve?domain=Guhailon，退回 https://t.me/Guhailon；旧邀请链接整段删；
     根渐变换 AppBackgroundView。
   - LogView：只补复制（copiedFeedback＋copyLog，UIPasteboard，1.5s 恢复）；
     新底子是自绘右上角菜单（不是参考线的 toolbar），复制以「复制日志」菜单项加在
     分享与清理之间；现有清理（clearLogs／确认框）一字未动。
   - ContentView：新增共用 AppBackgroundView（开关关→纯黑；有图 scaledToFill、
     不透明度 1−backgroundOpacity；无图→原渐变）；SettingsHubView／ContentView／
     AboutView／PlaybackDashboardView 四处根渐变替掉。SettingsView 三个键核实在位
     （129–155 行），直接用。
   - PlaybackDashboardView：positionLocked @AppStorage（App Group，默认 false）；
     「固定悬浮窗位置」Toggle 加在显示开关下、取色器上；提示行改跟锁走
     （悬浮窗口 · 已固定／长按拖动 · 双击隐藏，20pt 半粗体、白 85% 居中）；
     标题改 ZStack(alignment: .topTrailing)＋frame(maxWidth:.infinity, alignment:.center)
     居中，齿轮仍右上（新底子齿轮是自绘 GearMenu 子视图，不是参考线的系统 Menu，保留）。
   - FloatingLyricViewController：positionLockedKey＋positionLocked 读值、
     handlePan 开头 guard。**新底子本来就没有 hintLabel**（只有 currentLabel），
     所以第五件的「删 hintLabel」无事可删；stack 底部约束保持新底子的
     lessThanOrEqualTo −12（窗口高度动态算，参考线的 equalTo −12 会与动态高度冲突）。
3. `87e5032` — 1.0.3：首次打开要激活码（6 个文件，＋262／−3）。
   新文件 App/ActivationView.swift（参考 0e1e014 原文：ActivationGateView＋
   ActivationVerifier.verify，POST https://guhailong-repo.pages.dev/api/verify；
   valid==false→「激活码不正确」，没网／非 200／解不出→「需要联网激活」）；
   LyricStore 只加 ActivationStore（接口地址＋键 tld.activated／tld.activationType）；
   TrollLyricsDeskApp 根视图包 ActivationGateView；FloatingLyricViewController
   未激活悬浮窗隐藏；WidgetView 未激活占位「请先在 App 内激活」；
   pbxproj 加 ActivationView 进 App Sources（复用参考 ID）。
4. `e0c154a` — 1.0.1：锁屏歌词（9 个文件，＋712／−4）。
   新文件 LiveActivity/LyricsLiveActivity.swift、
   PlaybackEngine/LyricsLiveActivityController.swift（参考 0e1e014 原文）；
   PlaybackCoordinator 加 LiveLyricKey（普通 Equatable 键结构，存储属性绝无
   @available；6549b68 修法）、lastLiveState／lastLiveActivityID、isRunning／
   ensureRunning、publishLiveLyrics()（带 Universal 宿主 guard）及两处调用点
   （换歌分支＋poll 末尾）；ContentView 加锁屏区（含宿主文案
   「LiveContainer 模式不支持锁屏歌词和小组件」）；App Info.plist 加
   NSSupportsLiveActivities=true；Widget 加 accessoryRectangular＋锁屏分支＋
   Bundle 注册；pbxproj：两新文件进 App Sources、LyricsLiveActivity.swift 另进
   Widget Sources、ActivityKit 弱链接 4 处、.tbd 直链不动。
5. `3823f7f` — 1.0.0 build 18：Universal 兼容层（13 个文件，＋566／−15；含 check_newbase.py）。
   - LyricStore 加 isLiveContainer（plist 键 TLDSLiveContainer／路径含 livecontainer
     或 /lcapps/／类 LCAppDelegate）＋defaults 三元（宿主走 .standard）。
   - TrollLyricsDeskApp 加 `@objc func isHosted()`＋BackgroundKeepAlive 宿主时不启动。
   - TLDSAppDelegate 加 TLDSInstallNativeWindowFix 及 didFinishLaunching 里的
     `if (!isHosted)` 分支（宿主不装 fix、不启动悬浮窗）。**注意**：新底子已有
     UIRootSceneWindow 分类 hook（TLDSHook）做同一件事（背景透明＋level 10000），
     分类加载时即生效；Universal 的 swizzle 是按合并计划额外加的，两者效果相同，
     并存无害（swizzle 只在巨魔模式调用）。
   - TLDSSceneDelegate 加宿主强制 `isMain = YES; isFloating = NO`。
   - publishLiveLyrics 宿主 guard 已在第 4 笔带上。
   - WidgetCenter.reloadAllTimelines() 全部加 `if !isLiveContainer`：
     **实际 10 处调用点**（PlaybackCoordinator 4、LyricsSearchView 2、SettingsView 2、
     ContentView 1、ActivationView 1），差异报告写的「5 处」是文件数口径的笔误，
     以实际 10 处为准，全部已守卫。
   - Dashboard 宿主时显示「LiveContainer · 应用内歌词模式」＋0.25s TimelineView
     应用内歌词（暂停／开始＋歌词归零按钮）；巨魔模式走 else 分支（提示行＋开关＋取色器）。
   - 版本：build 17→18（两 Info.plist 的 CFBundleVersion），版本号保持 1.0.0，
     包名保持 com.ycwl.Lyrics，一字未动；Info.plist 里没有 TLDSLiveContainer 键。
   - 自检脚本 check_newbase.py（473 行）随本笔提交：108 PASS，FAILED: none，OPEN 6。
     红线 diff 锚点 5034a3f（干净底子提交）。

### App Group 核对结果
- 新底子 entitlements 与 LyricStore.groupID 均为 group.com.hailong.TrollLyricsDesk，
  与咱们的线一致；激活／锁屏／五件移植全程不用换 group。两份 entitlements 与底子
  提交 5034a3f 一字未动（check_newbase.py §9 核过）。
- SettingsView 三个背景键用字面量 "group.com.hailong.TrollLyricsDesk"，
  AppBackgroundView 用 LyricStore.groupID，值相同。

### build.yml 修正
- 无修正。保持新底子的 build.yml（一个 workflow「Build」，产物 `桌面歌词-1.0.0.ipa`），
  未并 Universal 的 workflow／产物名；check_newbase.py §9 核过（无 1.0.4／LiveContainer 字样）。

### Universal 里没采用的东西及实际结果
- 版本号／包名（1.0.4／Desk2）：未采用，终态 1.0.0／com.ycwl.Lyrics（IPA 已验）。
- Core/ 新引擎、额外 MusicProviders：diff 证实两边一字不差；终态 Core/、MusicProviders/
  与底子一字未动（check §9 git diff 为空）。
- LIVE_CONTAINER.md 独立构建路线（双 workflow、scripts/build-livecontainer.sh、
  宿主签名 IPA）：未采用；scripts/ 在 Universal 包里是空的，且与「不要两个 IPA」冲突。
  终态只有一个 workflow、一个 IPA（见第三阶段）。
- FloatingLyricViewController 单行＋fittedFontSize、SceneDelegate 固定 118 高、
  等值 scene 匹配：未采用（相对新底子是回退）；终态保新底子的动态高度＋hasPrefix 匹配。
- PlaybackCoordinator 的 `state = newState` 无条件赋值：未采用；终态保新底子的
  isDisplayEquivalent 节流（IPA 源码级已核，见 check §3）。
- Universal 的 RUN_1.0.1／RUN_1.0.2／README（写 1.0.3／iOS 16.0）：未采用；
  MinOS 以 pbxproj／Info.plist 的 15.0 为准（IPA 已验）。

## 第三阶段：编＋验（2026-11-26 晚）

### 编译日志
- 触发：推 3823f7f 到 newbase（五笔里前四笔也各触发一次 run，只跟头 run）。
- Run：**45823130516**，head 3823f7f，workflow Build，job Build，
  status_field=completed，**conclusion=success**（2026-11-26 12:48:41–12:49:32 UTC，约 51 秒）。
  9 个实步骤全部 success：Set up job／Checkout／Xcode version／Install zsign／
  Archive (unsigned)／Verify archive layout／Sign with zsign (TrollStore)／
  Package IPA／Upload artifact。无池子取消、无重跑。
- 产物：artifact「桌面歌词-1.0.0」id 15118433742（zip 1,653,245 B），内含
  `桌面歌词-1.0.0.ipa` **1,654,857 B，SHA256 21f2a43d8ba200464f7e4246c7192b017857513d1c200c5b3a6dad44c35fb3f1**，
  已拷到 `~/workspace/your_files/桌面歌词-1.0.0-newbase.ipa`。

### 验包（真 IPA 亲验，macho_inspect.py＋字符串扫描＋plistlib）
- 身份：版本 1.0.0／build 18（App 与 Widget 均为 18），包名 com.ycwl.Lyrics，
  显示名桌面歌词，MinOS 15.0；App Info.plist NSSupportsLiveActivities=true。
- 架构／签名：App 与 Widget 均为 Mach-O 64-bit arm64（subtype arm64），
  LC_CODE_SIGNATURE 均 present（zsign 签名步骤 success；本机无 codesign 可再核）。
- 同步修正串在位（App 二进制）：lyric.timeOffset| ✓、lyric.noMusic ✓、
  lyric.snapshot ✓；syncLiveLyricsAndProgress／isDisplayEquivalent／currentLyric
  等方法名在 Release 二进制里被 strip，无字符串——源码级已核（check §3），
  不作为二进制结论。
- 激活串在位：api/verify ✓、tld.activated ✓、tld.activationType ✓（App 二进制）。
- 五件在位：tg://resolve?domain=Guhailon ✓、t.me/Guhailon ✓、
  seadragonjb 0 命中、I-I8aw7HUAw1NGY9 0 命中、AppBackgroundView ✓、
  floatingLyric.positionLocked ✓、hintLabel 0 命中。
- 锁屏在位：NSSupportsLiveActivities ✓、accessoryRectangular（源码级，check §6）✓；
  两二进制 ActivityKit 均为 **LC_LOAD_WEAK_DYLIB**（macho_inspect.py，
  弱链接 load command 0x80000018 折算后为 LC_LOAD_WEAK_DYLIB）；
  .tbd 直链 4 条（FrontBoard／FrontBoardServices／RunningBoardServices／AppleAccount）
  强链接在位，未动。
- LC 检测在位：TLDSLiveContainer ✓（两二进制各 1 处）、
  「LiveContainer · 应用内歌词模式」✓、「LiveContainer 模式不支持锁屏歌词和小组件」✓；
  **二进制字面量扫描限制（已查明，非缺陷）**：livecontainer／/lcapps/／LCAppDelegate
  三个字面量在二进制字节扫描里是 0 命中——与「桌面歌词」「暂停歌词」「歌词归零」
  「lyric.cache|」同类，都是 ≤15 UTF-8 字节的行内字面量，Swift -O 编译把它们以内联
  small-string immediates 形式写进代码段，不进 __cstring（逐项核对：__cstring 里
  在位的全是 ＞15 字节或 static-let／ObjC 字面量，如 lyric.timeOffset| 16 字节、
  TLDSLiveContainer 17 字节、tld.activated 是 static-let；缺失的全是 ≤15 字节的行内
  字面量，无一例外）。代码编译无误、plist-key 分支（17 字节）在位、宿主 UI 文案在位，
  因此检测逻辑本身不判死刑；**宿主模式是否真生效，只能真机验**（见待验清单 LC 项）。
- 不在位：38473 0、DualProcessBridge 0、BackBoard 0、dynamic_lookup 0、
  TLHUDApplication 0（App＋Widget 两二进制）。
- 码值扫描：TLD-XXXX-XXXX-XXXX 格式在两二进制里 **0 命中**（只计数，未打印任何值）。
- 自检：`python3 check_newbase.py` 提交后重跑——**108 PASS，FAILED: none，OPEN 6**。

## 待真机验证的功能清单（只能真机验，逐项写清怎么验）

1. **同步修正（底子自带，合并未动）**：放一首 LRCLIB 歌词时间轴有偏差的歌，
   在设置页逐歌偏移里调（如 +1.0s），切走再切回同一首歌，看歌词是否仍按调好的偏移显示
   （不再串到别的歌）；播到一半切到别的 App 再回来，看悬浮窗是否不留旧歌词；
   字段型播放器（歌词塞 artist 字段）放歌时，看主界面／悬浮窗／小组件三处歌词是否
   都在上面大字位置、不来回翻转；同一首歌内拖进度条，看歌词是否跟上（2s 阈值外才校准）。
2. **逐歌偏移**：同上第 1 项；再调另一首歌的偏移，看第一首歌的偏移是否不受影响。
3. **悬浮窗**：开 App 即自动跟随；悬浮窗拖动、双击隐藏（主界面开关同步关掉）、
   再从主界面开关打开；锁屏再解锁后悬浮窗是否恢复（needsRebuildOnUnlock 轮询）；
   固定开关打开后拖不动、提示行变「悬浮窗口 · 已固定 · 双击隐藏」，关掉又能拖；
   重启 App 后悬浮窗是否在上次存好的位置。
4. **锁屏**：设置页「锁屏歌词」点开启，锁屏看横幅是否出现并逐句跟随；灵动岛
   （15 Pro）展开／收起／最小三态；暂停时标题行是否标「已暂停」；锁屏上滑掉横幅后
   回设置页开关是否同步灭掉；锁屏小组件需手动长按锁屏→自定→添加小组件→选
   「Troll Lyrics」长方形，看当前句／下一句是否显示。iPhone 11 没有常亮显示，
   关屏不显示是硬件限制；横幅最长约 8 小时，到期要回 App 再点开启。
5. **激活**：全新安装首次打开是否全屏弹激活页；输错码报「激活码不正确」；
   断网（开飞行模式）报「需要联网激活」；输对码后不用重启直接进主界面；
   未激活时悬浮窗隐藏、小组件显示「请先在 App 内激活」占位。
   （激活码由皇上掌握，码值不在任何记录里。）
6. **五件**：点关于页 Telegram 行，进 @Guhailon 公开频道（没装 Telegram 时退回网页版）；
   日志页右上角菜单点「复制日志」，到别处粘贴看整份日志是否在，再点「清理日志」
   确认后页面是否变空；设置页「背景设置」选图后主界面／设置页／关于页是否立即换图，
   开关关掉是否变纯黑，透明度滑杆拖动图是否跟着变透，没选图时是否原渐变；
   标题「桌面歌词」是否横向居中、齿轮仍在右上角；提示行是否在歌曲卡片与开关之间、
   跟固定开关变文案。
7. **LC 兼容**：同一 IPA 导入 LiveContainer（iOS 27 手机）能否启动、不闪退；
   主界面是否显示「LiveContainer · 应用内歌词模式」，应用内歌词是否 0.25s 刷新、
   「暂停歌词／开始歌词」「歌词归零」是否可用；设置页锁屏区是否显示
   「LiveContainer 模式不支持锁屏歌词和小组件」；**重点验证 isLiveContainer 三路检测
   是否真生效**（路径／类名分支在二进制里是 small-string immediates，字节扫描看不到，
   只能以宿主模式实际出现为准）。同一 IPA 装回越狱机 TrollStore 后，悬浮窗／锁屏／
   保活是否一切照旧（巨魔模式不受宿主分支影响）。
8. **iOS 15**：MinOS 15.0 的机器上启动是否正常（ActivityKit 是弱链接，iOS 15 上
   不应因缺 ActivityKit 闪退）；锁屏歌词区在 iOS 15 上应显示「锁屏歌词需要 iOS 16.1 或以上」。


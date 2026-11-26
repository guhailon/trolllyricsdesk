# TrollLyricsDesk 1.0.5 — RUN 记录（Universal 签名环境兼容修复版：诊断优先＋三档模式）

底子：newbase 分支 HEAD **6857d3c**（1.0.0/build 18 已合并版）。
皇上 2026-11-26 21:13 下令＋21:15 追加范围：LiveContainer 本体经**第三方签名工具安装**、
桌面歌词经 LiveContainer 导入运行；激活成功、Shell 注册、悬浮场景创建都有成功日志，
但实际没有悬浮歌词。宿主本身权限就受限——「创建成功」日志不能当成功用。

## 原则（铁律）
- **不得将私有权限声明或窗口创建日志视为实际功能成功**：悬浮窗创建后延迟复核
  （窗口真在层级里、Context ID 有效、binder 真收录场景），结论记成
  「已确认可见／未确认可见＋原因」，不只记「创建成功」。
- 诊断优先：先把真相打出来，缺什么权限由日志说了算；**零新增 entitlements／权限键**
  （两份 entitlements 与 6857d3c 一字未动，自检 §11 已核）。
- 保留新底子歌词同步修正与逐歌偏移（一字不动，自检红线锚已核）；
  单 IPA、包名 com.ycwl.Lyrics 不变、激活 POST /api/verify 不变；
  不加独立客户端、不加 TCP 桥、不修 Telegram 行点、不修锁屏歌词不见；
  PiP 只研究、不实现（皇上自己弄）。

---

## 一、7 项各改了哪些文件

| # | 项 | 文件 |
|---|---|---|
| 1 | MediaRemote 诊断 | `Core/MediaRemoteBridge.swift`（dlopen 成败＋dlerror，dlsym 逐符号只记一次）、`MusicProviders/MediaRemoteAdapter.swift`（注册 `MRMediaRemoteRegisterForNowPlayingNotifications`，回调触发记第一次＋每 50 次，GetNowPlayingInfo 回调记第一次＋info nil／非 nil 切换） |
| 2 | 强制悬浮测试文字 | `Lyrics/LyricStore.swift`（新增 `testTextKey`／`isTestTextEnabled`／`testText()`）、`Overlay/FloatingLyricViewController.swift`（refresh() 最前分支）、`App/SettingsView.swift`（诊断区开关＋运行模式行）、`App/PlaybackDashboardView.swift`（宿主应用内歌词区显示测试文字，注明非悬浮窗） |
| 3 | 场景／托管检查 | `Overlay/TLDSAppDelegate.m`（createFloatingScene 时记 Context ID／settings.foreground／binder）、`Overlay/TLDSSceneDelegate.m`（悬浮窗创建时记 windowLevel／alpha／backgroundColor／isHidden／windowScene／frame） |
| 4 | 宿主实际权限检查 | `Overlay/TLDSAppDelegate.m`（`verifyFloatingVisibility` 延迟复核＋逐项结论＋`downgradeToCompatModeWithReasons`） |
| 5 | 重复启动／重复初始化排查 | `Overlay/TLDSAppDelegate.m`（启动／Overlay／scene 计数＋Shell／NativeWindowFix 一次性守卫）、`Overlay/TLDSSceneDelegate.m`（主／悬浮场景连接计数）、`Overlay/FloatingLyricViewController.swift`（控制器初始化计数）、`App/TrollLyricsDeskApp.swift`（`start()` 重复记跳过）、`PlaybackEngine/PlaybackCoordinator.swift`（检测引擎启动计数） |
| 6 | 后台挂起及恢复日志 | `Overlay/TLDSAppDelegate.m`（进入后台／失去前台／回到前台／终止四回调）、`Overlay/TLDSSceneDelegate.m`（场景前台／后台四回调） |
| 7 | 保留同步修正与逐歌偏移 | 未碰：`Lyrics/LyricStore.swift` 的 timeOffset／noMusic／isDisplayEquivalent／syncLiveLyricsAndProgress 等只增新段、零删行（自检 §11：`git diff 6857d3c..HEAD -- Lyrics/LyricStore.swift` 无删行；红线锚 9 个符号仍在位） |

版本：`MARKETING_VERSION` 4 处 1.0.0→**1.0.5**、两 Info.plist 版本 **1.0.5**／build **19**、
workflow 产物 `桌面歌词-1.0.5.ipa`。

## 二、三档运行模式（新增范围）

### 判定逻辑
分两步，缺一不可：
1. **第一步信号**（旧 `isLiveContainer`，路径／类名／plist）：只是「可能是宿主」，
   不当结论。
2. **第二步能力探测**（只读＋轻量，失败不 crash、不卡启动）：悬浮窗创建后
   2 秒复核（场景未连上时 3 秒后再跑一次；Shell 回调一直不来时 6 秒兜底复核一次）。
   关键项全过才算增强宿主；任一关键项失败即普通签名兼容。

| 档 | 条件 | 行为 |
|---|---|---|
| 巨魔原生 `trollstore` | 非 LiveContainer | 悬浮窗照现在走，行为一字不动；不复核 |
| 增强宿主 `enhanced-host` | LiveContainer ＋复核关键项全过 | 首选 PiP 实验，应用内备选（原生 HUD 在此模式视为权限受限，不信任） |
| 普通签名兼容 `compat` | LiveContainer ＋复核任一关键项失败 | 不建悬浮窗：摘掉场景、隐藏窗口、不再重建／恢复；只走应用内歌词 |

复核关键项（逐项打日志，通过／失败＋原因）：
- 场景对象非空；binder 的 `scenes` 含本场景（SpringBoard 真接受了）；
- 悬浮窗口非空；`isHidden=NO`；`windowLevel` 实际值（期望 10000）；
- `windowScene` 非空；`rootView.view.window` 非空（视图真挂上）；
- Context ID：有效（非 0）算通过，**读不到只记警告、不进判定**
  （不同 iOS 版本未必暴露这个键，读不到 ≠ 没托管）；
- 观察项（不进判定）：窗口在不在 `UIApplication.windows` 里。

判定结果写进 `LyricStore.defaults`（`tlds.runMode`／`tlds.runModeReason`），
设置页「诊断（1.0.5）」区显示中文模式名，日志里每次写判定都记一行。
巨魔模式行为一字不动：`BackgroundKeepAlive`、锁屏推送、Widget 刷新等宿主 guard
仍按 `isLiveContainer` 走（它们管的是 Live Activity／小组件，不是悬浮窗）。

### 日志样例（日志页里长这样，`[时间] ` 前缀是 LyricLogger 自带的）
```
[时间] 诊断1.0.5 启动：App 启动第 1 次
[时间] 运行模式：待探测（LiveContainer 信号已出，尝试创建悬浮窗，等 2 秒后托管复核定档）
[时间] 诊断1.0.5 MediaRemote：dlopen 成功（/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote）
[时间] 诊断1.0.5 MediaRemote：dlsym MRMediaRemoteGetNowPlayingInfo 成功
[时间] 诊断1.0.5 MediaRemote：回调注册已调用（等回调触发才算通道通）
[时间] 系统 Shell 注册成功
[时间] 诊断1.0.5 场景：createScene 返回 非空，Context ID=12345，settings.foreground=YES（创建成功≠可见，等复核）
[时间] 诊断1.0.5 场景：悬浮窗口已创建（第 1 次，标识 TLDSFloatingLyric）：windowLevel=10000，alpha=1.00，backgroundColor=已设置，isHidden=NO，windowScene=非空，frame={{x, y}, {w, h}}（创建成功≠可见，等复核）
[时间] 诊断1.0.5 托管复核：场景对象 通过（floatingScene 非空）
[时间] 诊断1.0.5 托管复核：binder 收录场景 通过（scenes 含本场景）
[时间] 诊断1.0.5 托管复核：悬浮窗口 通过（floatingWindow 非空）
[时间] 诊断1.0.5 托管复核：窗口 isHidden=NO（通过），windowLevel=10000（期望 10000），alpha=1.00，backgroundColor=已设置
[时间] 诊断1.0.5 托管复核：windowScene 通过（非空），rootView 已挂到 window 通过（view.window 非空），frame={{x, y}, {w, h}}
[时间] 诊断1.0.5 托管复核：Context ID=12345（通过（有效））
[时间] 运行模式：增强宿主模式（LiveContainer，悬浮窗复核通过，首选 PiP 实验，应用内备选）
[时间] 诊断1.0.5 显示引擎：PiP 画中画歌词（实验）（增强宿主模式首选），应用内歌词备选；透明全域悬浮在此模式为权限受限，不信任原生 HUD
[时间] 诊断1.0.5 托管复核结论：已确认可见
```
未通过时则是：
```
[时间] 诊断1.0.5 托管复核：binder 收录场景 失败（scenes 不含本场景，SpringBoard 没接受／binder 丢了场景）
[时间] 诊断1.0.5 托管复核结论：未确认可见（原因：binder 未收录场景；悬浮窗口为空）
[时间] 运行模式：普通签名兼容模式（LiveContainer 经第三方签名、权限受限，悬浮窗未确认可见，不建悬浮窗，走应用内歌词）
```

### 「创建成功≠可见」在诊断里怎么区分
- 「系统 Shell 注册成功」「全局悬浮歌词场景已创建」「悬浮歌词场景窗口已显示」
  仍保留（旧日志），但每行创建日志都补了「（创建成功≠可见，等复核）」，
  且**不定模式**——模式只由 2 秒后复核的逐项结果定。
- 复核结论只有两行：「已确认可见」或「未确认可见（原因：…）」，
  以复核结论为准，创建日志不算数。

## 三、诊断日志怎么看（日志页哪几行对应哪项）
- 第 1 项 MediaRemote：`诊断1.0.5 MediaRemote：dlopen 成功／失败：…`、
  `dlsym <符号名> 成功／失败：…`（四个符号各一行，只记第一次）、
  `回调注册已调用／回调注册失败：…`、`NowPlaying 通知回调已触发（第 N 次…）`、
  `GetNowPlayingInfo 回调已触发（第 N 次），info=nil（无播放器／读不到）` 或
  `info 有内容（歌名=…）`。回调只在第一次和 nil／非 nil 切换时记，不刷屏。
- 第 2 项强制测试：`诊断1.0.5 强制测试：开关已打开／已关闭`（设置页拨开关时）、
  `开关已开，悬浮窗正在显示测试文字` 或
  `开关已开，但悬浮窗被隐藏（浮窗开关关／未激活，先开「显示悬浮歌词窗」并确认已激活）`。
- 第 3 项场景：`诊断1.0.5 场景：createScene 返回…`、`诊断1.0.5 场景：悬浮窗口已创建（第 N 次…）`。
- 第 4 项复核：`诊断1.0.5 托管复核：…`（逐项）＋`托管复核结论：已确认可见／未确认可见（原因：…）`。
- 第 5 项重复：`诊断1.0.5 启动：App 启动第 N 次`／`startFloatingOverlay 调用第 N 次`／
  `createFloatingScene 调用第 N 次`／`悬浮窗控制器初始化第 N 次`／`检测引擎启动第 N 次`／
  `主界面场景已连接：…（第 N 次）`；重复时另有 `…已初始化，跳过（不建第二个窗）`／
  `…已启动，跳过`。正常启动时各项计数都应为 1。
- 第 6 项后台：`诊断1.0.5 后台：App 进入后台…`／`场景进入后台…`／`App 回到前台…` 等，
  与悬浮窗消失的时间点对照，就能看出是不是被挂起弄没的。
- 模式：`运行模式：巨魔原生模式／待探测／增强宿主模式／普通签名兼容模式`＋
  `诊断1.0.5 运行模式：写入 <mode>（<原因>）`。

## 四、PiP 画中画歌词实验引擎（皇上 21:26 定：只研究作废，按树实现）

- 代码核查：改动前全树 grep `AVPictureInPicture`／`PictureInPicture` **0 命中**
  （TrollLyricsDesk 这边没有 PiP 相关串；DYYY 那边按任务说明也没有）。
- 实现位置（皇上的树）：`Renderer/PiPLyricsRenderer.swift`（引擎＋delegate 回调判定）、
  `Renderer/PiPFrameRenderer.swift`（文字 → 视频段：AVAssetWriter＋H.264，
  960×540 黑底白字居中，每段 4 秒、2fps）、`Renderer/LyricsRenderer.swift`
  （统一渲染协议＋Hub）、`Compatibility/RuntimeEnvironment.swift`（模式 → 引擎映射）。
- 步骤分两段，都已实现、都是实验：
  ① **固定测试文字先行**（`startTestText()`）：生成「悬浮测试 · 桌面歌词 1.0.5」视频段，
  循环播，调 `startPictureInPicture()`，确认 PiP 能不能在桌面和其他 App 上方出现；
  ② **再接实时歌词**（`startLiveLyrics()`）：每 0.5 秒读快照当前行，行一变就生成新视频段、
  排进 AVQueuePlayer（队列只留最近两段，旧段文件清掉）。歌词本身仍走新底子同步引擎。
  两段在设置页「诊断（1.0.5）」区和诊断页里都有按钮，全程标「实验」，不得报成已实现。
- 真能显示的唯一证据是 delegate 回调
  `pictureInPictureControllerDidStartPictureInPicture`；`canStartPictureInPicture` 为真、
  调了 start，都不算成功；失败走 `failedToStartPictureInPictureWithError`，错误记进日志。
- 限制（不回避）：透明背景受限（视频帧是黑底，不是透明悬浮窗）、拖动与大小由系统控制、
  锁屏不保证、后台行为未验证、每行歌词都要现编码一段视频；**PiP 能显示也不代表能自动
  拿到别的播放器的歌，跨应用识别要单独解决**（MediaRemote 诊断第 1 项）。
  PiP 启动要在前台由用户点按钮触发，后台回调里调不可靠，所以增强宿主模式
  不自动开 PiP，只自动选引擎（见下节）。
- 「逐字歌词」说明：第 7 点说的「保留逐字歌词」——新底子里没有逐字同步实现
  （LyricWord.swift、LyricSyncEngine.swift 不存在，设置里的「逐字卡拉OK」只是选项文字）。
  「保留」= 不删现有选项／文案，**没有现编逐字实现**（自检 §12 核过：两文件不存在，
  全树无 LyricSyncEngine）。播放进度修正就是新底子已有的 syncLiveLyricsAndProgress，保留不动。

## 五、提交链
- `2c64cad` — 1.0.5 build 19：诊断实现（15 个文件，＋647／−35）。
- `a5ae262` — 自检 check_1.0.5.py（锚点 6857d3c，146 PASS）＋RUN_1.0.5.md。
  头 run **45828687961 success**（11 步全过，见下节）——诊断版代码能编。
- `（第三笔）` — PiP 实验引擎＋皇上树新结构（11 个新文件＋接线改动）。
- `（第四笔）` — 自检升级（187 PASS）＋本 RUN 文件更新。

## 六、编译日志
- 诊断版头 run：**45828687961**，head a5ae262，workflow Build，job Build，
  status_field=completed，**conclusion=success**（排队约 6 分钟，跑约 1 分钟），
  11 个步骤全部 success，无池子取消、无重跑。
- PiP 版头 run：（推第四笔后填：run 号／结论／产物大小／SHA256。）

## 七、自检
`python3 check_1.0.5.py`（锚点 6857d3c）：**187 PASS，FAILED: none，OPEN 11**。
红线：LyricStore diff 零删行；9 个同步锚符号在位；两份 entitlements 与 6857d3c 一字未动；
全树无 38473／DualProcessBridge／dynamic_lookup／OverlayEngine／LyricsSyncEngine；
BackBoard 只在权限对照表里提一次名字（标签，不是实现）。

## 八、新结构与 ChatGPT 树的出入（以皇上的树为准）
| 位置 | ChatGPT 建议的树 | 皇上的树（实际建的） | 备注 |
|---|---|---|---|
| Compatibility 第三档 | OverlayMode.swift | **EntitlementDiagnostics.swift** | 皇上的为准；模式判定不在这里，在 RuntimeEnvironment |
| Renderer | NativeLyricsHUD.swift／InAppLyricsHUD.swift／OverlayEngine.swift | **LyricsRenderer.swift（统一渲染协议＋Hub）／NativeHUDRenderer.swift／PiPFrameRenderer.swift／InAppLyricsRenderer.swift** | 没有 OverlayEngine.swift——切换逻辑放 RuntimeEnvironment／LyricsRenderer 层 |
| Core | LyricsSyncEngine.swift／MediaRemoteAdapter.swift／LyricsTestMode.swift 三个新文件 | **保留新底子歌词引擎（不新建）** | MediaRemote 修复与强制测试歌词分别进 Diagnostics／Core 现有位置，按 7 项做 |
| Diagnostics | （ChatGPT 树没单列） | **MediaRemoteDiagnostics.swift／OverlayDiagnostics.swift／DiagnosticsView.swift** | 皇上的树有，照建 |

新文件进 pbxproj 的 App Sources（11 个，自检 §12 核过）；没动 .tbd 直链与 ActivityKit 弱链接。

## 九、三档模式 → 显示引擎（阈值与判定，补 ChatGPT 没给的缺口）
对话没有给代码级 if／enum、阈值、检测函数签名、返回值或切换优先级，
也没有逐文件规格和 PiP 搭建代码——以下是我自己补的设计（RUN 里写明，不冒充对话原文）：
- 模式判定（ObjC 侧，TLDSAppDelegate 托管复核）：关键项全过 → 增强宿主；
  任一关键项失败 → 普通签名兼容；非 LC → 巨魔原生。阈值：复核在创建后 2 秒跑，
  场景未连上时 3 秒后再跑一次，Shell 回调不来时 6 秒兜底；关键项 = 场景非空、
  binder 收录场景、窗口非空、isHidden=NO、windowScene 非空、视图已挂 window；
  Context ID 读不到只记警告、不进判定。
- 引擎映射（`RuntimeEnvironment.preferredEngine(forRunMode:)`，纯映射）：
  trollstore → 原生 HUD；enhanced-host → PiP 实验（首选），应用内备选；
  compat／probing → 应用内。增强宿主不信任原生 HUD 的原因：
  1.0.4 的教训是创建日志成功≠真显示，复核过的 FBScene 也可能在 LC 里被系统静默不合成；
  只信任 PiP 的 delegate 回调（真显示出来才算）。
- PiP 搭建（公开做法）：`AVPictureInPictureController.isPictureInPictureSupported()`
  先查系统支持 → `PiPFrameRenderer` 把文字画成 960×540／H.264／4 秒视频段 →
  `AVQueuePlayer`＋`AVPlayerLayer`（挂在一个不进窗口的宿主 view 上，实验性质）
  → `AVPictureInPictureController(playerLayer:)`＋delegate → 用户前台点按钮调
  `startPictureInPicture()`；实时歌词每 0.5 秒读快照行、行变则生成新段排队。
- 引擎选择日志（三处定档点都记）：「诊断1.0.5 显示引擎：原生 HUD 悬浮歌词…」／
  「PiP 画中画歌词（实验）…应用内歌词备选…」／「应用内歌词…唯一档…」。
- 权限对照（`EntitlementDiagnostics`）：声明列是 entitlements 文件的静态镜像
  （与 6857d3c 一字未动，自检核过）；实测列来自真实调用。LC 宿主是普通开发者签名，
  客人继承不到私有权限——IPA 自己声明了也不代表在 LC 里能用。

## 十、待真机验证清单（逐项写怎么验）
1. **启动就看模式（最重要）**：装 1.0.5 进 LiveContainer，打开 App，等 5 秒，
   进关于页 → 日志，抄回「运行模式：…」那一行和「托管复核结论：…」那一行。
   - 若是「增强宿主模式／已确认可见」→ 复核过了，但原生悬浮窗仍不信任（创建成功≠可见），
     首选是 PiP——去第 8 项试 PiP；原生悬浮窗就算出来了也不算数。
   - 若是「普通签名兼容模式／未确认可见（原因：…）」→ 抄回括号里的原因，
     那就是病根（binder 没收录／窗口为空／isHidden 等）；悬浮窗不出现是**预期**的，
     应用内歌词应正常。
   - 若连「待探测」都没有 → 启动时就崩了（第一嫌疑：LC 里首次调 FBSystemShellInitialize），
     报给协调员，不要反复重装。
2. **强制测试文字**：设置页 → 诊断（1.0.5）→ 打开「强制悬浮测试文字（测试用）」。
   - 巨魔／增强宿主：悬浮窗应立即显示「悬浮测试 · 桌面歌词 1.0.5 · HH:mm:ss」，
     秒数每 0.25 秒变（证明窗口活着）；关掉开关后应立刻回到正常歌词，
     不能残留测试文字。
   - 普通签名兼容（LC）：主界面应用内歌词区显示同一行测试文字＋「（应用内显示，非悬浮窗）」，
     这不是悬浮窗——不要当成悬浮窗好了。
   - 若开关开了、日志有「开关已开，但悬浮窗被隐藏」，先开主界面「显示悬浮歌词窗」、
     确认已激活，再看。
3. **MediaRemote**：放一首歌（任意 App），看日志：
   `dlopen 成功`＋四个 `dlsym … 成功`＋`回调注册已调用`＋
   `GetNowPlayingInfo 回调已触发，info 有内容（歌名=…）`。
   - 若 `dlopen 失败`／某符号 `失败`，抄回冒号后的原因。
   - 若回调一直没触发、info 一直 nil，说明 LC 客人里读不到 NowPlaying——
     应用内歌词仍可用搜索／导入，但「自动跟随」在 LC 里就是读不到，要报回来。
4. **重复启动**：正常启动一次，日志里 `App 启动第 1 次`／`startFloatingOverlay 调用第 1 次`／
   `createFloatingScene 调用第 1 次`／`悬浮窗控制器初始化第 1 次`／`检测引擎启动第 1 次`，
   各项都应为 1；若有大于 1 的，抄回那几行。
5. **后台**：App 切后台再回来，看日志里 `进入后台` 与 `回到前台` 的时间点，
   对照悬浮窗是什么时候消失的；若悬浮窗在「进入后台」那一刻没的，就是被挂起弄没的。
6. **巨魔模式回归**：同一 IPA 装回越狱机 TrollStore，悬浮窗／锁屏／保活／激活一切照旧；
   日志里应是「巨魔原生模式」，不应出现复核行（巨魔不复核）。
7. **不验的**：Telegram 行点没反应、锁屏歌词不见——1.0.5 不修这两项，不要顺手报它们修没修好。
8. **PiP 实验第一段（固定测试文字）**：在 LiveContainer 里打开 App → 设置页 → 诊断（1.0.5）
   → 点「开始 PiP 测试（固定文字，实验）」，然后按 Home 回桌面、再打开别的 App（如 Safari）：
   - 若桌面／别的 App 上方出现一个小窗，里面是「悬浮测试 · 桌面歌词 1.0.5」白字黑底
     → 第一段成了，抄回日志里「PiP 已显示（实验）」那一行。
   - 若没出现，抄回日志里 PiP 那几行（「启动失败：…」或「暂不能启动…」），
     尤其是有没有 `failedToStartPictureInPictureWithError` 的错误原因。
   - 小窗是黑底不是透明、大小拖动由系统定——都是已知的实验限制，不是 bug。
   - 关掉：点小窗的关闭按钮，或回设置页点「停止 PiP」。
9. **PiP 实验第二段（实时歌词）**：第一段成了之后再试——放一首歌（先确认主界面应用内歌词
   在跟），设置页点「接入实时歌词到 PiP（实验）」，看 PiP 小窗里的行是否跟着歌词走。
   行一切换要等新视频段现编码（约半秒到一秒），不是逐字跳——逐字同步本来就没实现，
   不要按逐字标准验。若行不动，先看主界面歌词动不动：主界面不动就是识别／同步的问题，
   不是 PiP 的问题。
10. **诊断页**：设置页 → 诊断（1.0.5）→「查看诊断详情」，看模式／MediaRemote／PiP 状态／
    权限对照四区显示是否与日志一致；点「刷新快照」应记一行能力快照进日志。

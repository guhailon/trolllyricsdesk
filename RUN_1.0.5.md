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
  不加独立客户端、不加 TCP 桥、不修 Telegram 行点；
  **锁屏歌词已取消（见下节），不再是功能点。**
  PiP 只研究、不实现（皇上自己弄）。

---

## 零、锁屏歌词已取消（皇上 2026-11-26 21:46 令）
- 原因：锁屏歌词（Live Activity）从 1.0.1 起就没在真机上证实过能用——
  皇上 2026-11-26 10:44 说「1.0.1 没用，试过了」，14:14 又问锁屏歌词为什么显示后不见；
  皇上现在发话，没用就取消。
- 拿掉的范围（单独一笔提交，可 revert）：删 `LiveActivity/LyricsLiveActivity.swift`、
  `PlaybackEngine/LyricsLiveActivityController.swift`；PlaybackCoordinator 删
  LiveLyricKey／lastLiveState／lastLiveActivityID／isRunning／ensureRunning／
  publishLiveLyrics() 及两处调用点（同步修正一字未动）；ContentView 删锁屏区；
  App Info.plist 删 NSSupportsLiveActivities；Widget 删 accessoryRectangular 锁屏分支＋
  Bundle 注册；pbxproj 删两文件条目＋ActivityKit 弱链接 4 处
  （.tbd 直链是悬浮窗的，没动）；新写的三档／渲染器／诊断代码里以锁屏为功能点的描述
  一并拿掉（PiP「锁屏不保证」是 ChatGPT 设计的原句，保留原意；悬浮窗解锁后重建
  `needsRebuildOnUnlock` 是浮窗逻辑，不动）。
- 恢复路径：代码在 git 历史 newbase **e0c154a** 里，以后想加回来可从那恢复。
  build 18 那个已发皇上的包不动（里面有锁屏，皇上正在测，不重编）。
- 验包里锁屏项改成「不在位」验证（见第十一节）。

## 附一、ChatGPT 审查两 bug 修复（皇上 22:00 令，1.0.5 范围内，不另开版本）
来源：皇上 21:57、21:59 发的两个 ChatGPT 链接（同一「源码审查优化」对话），
是对新底子源码（6857d3c）的静态审查，不是 1.0.5 设计；其中两处已核实的具体 bug
划进 1.0.5 现有的 MediaRemote／激活范围一起修。
**不做的**：「1.0.1-newbase」20 项四阶段计划不跟（版本号不对，皇上定的是 1.0.5；
还写「不删除现有功能」，跟皇上 21:46 取消锁屏的令直接冲突）。
**后续候选（只记，不动手）**：LRC 多时间标签解析、保活状态机、权限最小化、
激活升级服务端签名。

### 1. 暂停后播放时间还在涨（MediaRemoteAdapter.swift，P0）
- 病根：旧公式 `position = max(0, Date().timeIntervalSince(timestamp) + elapsed)`
  没把播放速率 rate 纳入——播放器暂停后时间戳不刷新，算出来的播放时间还在继续涨
  （30 秒处暂停，5 秒后算成 35 秒）。
- 修法（ChatGPT 给的公式，核对后采用；变量名与现有代码完全一致，不用改写）：
  `elapsed`／`timestamp`／`rate`／`duration` 四个名在现有代码里就是这么叫的；
  `rate` 取自 `kMRMediaRemoteNowPlayingInfoPlaybackRate`（缺失默认 0）；
  暂停时 rate=0，`estimated` 停在 `elapsed` 不再涨；duration 为 0 或缺失时不 clamp。
  ```swift
  let delta = timestamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0
  let estimated = max(0, elapsed + delta * rate)
  let position: TimeInterval = duration.map { $0 > 0 ? min(estimated, $0) : estimated } ?? estimated
  ```
- 防卡死（fetching 一直 true、后续检测停掉）：
  **请求超时 2.0 秒**——超过 2 秒没回回调，fetching 自动复位，下一次 poll 重新发请求，
  超时记一行诊断日志（第 1 次＋每 10 次，不刷屏）；
  **请求编号**——每次发请求 requestID+1，回调里 `guard id == self.requestID`，
  旧请求的迟到回调直接丢弃，不覆盖新缓存、不清新请求的 fetching；
  **缓存硬过期 3.0 秒**——快照超过 3 秒没被新回调替换就再也不采用（currentState 返回 nil，
  显示「没有检测到」，不拿旧快照冒充当前播放）；保鲜 0.3 秒（cacheLifetime）不动，
  正常流程回调几毫秒就到，硬过期只是兜底。
- 数值来源：超时 2 秒＋缓存龄 3 秒与 ChatGPT「1.0.1 Engine Fix」ZIP 里核实的值一致
  （那包的 MediaRemoteAdapter 也是 2 秒超时＋requestID＋3 秒缓存龄；
  ZIP 在 `~/workspace/user/files/TrollLyricsDesk-EngineFix.zip`，
  923,187 B，SHA256 f59ae5d1…，已由浏览器对 6857d3c diff 核实）。
  Engine Fix 那包还改了 PlaybackCoordinator.swift（换歌／暂停／异步搜词）
  和 LyricParser.swift（多时间标签＋[offset:]），**不在本次范围**，
  只记在上面后续候选里，不动手。

### 2. LiveContainer 下激活存储不一致（高）
- 病根：LyricStore.swift 在 LC 环境下用 UserDefaults.standard，
  但 ActivationView.swift 的激活门（ActivationGateView）直接读 App Group——
  激活状态写入（ActivationStore.markActivated 走 LyricStore.defaults）和读取的位置不一致，
  激活成功却仍停留在激活界面。
- 修法：全工程存储入口统一走 LyricStore.defaults（巨魔 App Group／宿主 .standard，
  巨魔模式下行为不变）。grep 全工程列出的绕过点，逐一改掉：
  ActivationView.swift（激活门，正主）×1、ContentView.swift（背景×3＋悬浮窗透明度×1）、
  PlaybackDashboardView.swift（悬浮开关×3＋syncFloatingEnabled 直接读×1）、
  SettingsView.swift ×7（原来还是硬编码 `"group.com.hailong.TrollLyricsDesk"` 字符串，
  连 LyricStore.groupID 都没用）、FloatingLyricViewController.swift（`prefs` 改成计算属性）、
  TLDSAppDelegate.m ×3（`[[NSUserDefaults alloc] initWithSuiteName:…]` 读 floatingLyric.enabled，
  改走新增的 ObjC 入口 `[TLDSRuntime sharedDefaults]`——TLDSRuntime 已有 @objc 桥，
  sharedDefaults 就是 `LyricStore.defaults ?? .standard`）。
  改完后全树 `UserDefaults(suiteName:` 只剩 LyricStore.swift:58 本尊（defaults 定义），
  ObjC 侧 `initWithSuiteName` 零处；Widget 里本来就没有直接存储调用。
- 真机验：LC 里激活成功后应直接进主界面，不再停留激活页；巨魔模式行为不变。

## 附二、Engine Fix 并入（皇上 22:03 令，以包的 diff 为准）
来源包：`~/workspace/user/files/TrollLyricsDesk-EngineFix.zip`，923,187 B，
SHA256 f59ae5d1…（已验）；解开实测 82 个文件。与 6857d3c 全树对 diff：
**只改三个文件**（其余一字不动），加 ENGINE_FIX.md 和 EngineTests/main.swift。
包只过了 Swift 语法检查和 Linux 下的 LRC 测试，**没编过 Xcode、没签过包、没上过真机**——
真正的验证就是接下来的云端构建和协调员的验包；编不过就修，不把没编过的代码报成已实现。
本机无 swiftc，EngineTests 的 LRC 回归测试这里没法复跑（包自称 Linux 下通过，未复核）。

### 1. MediaRemoteAdapter.swift——用包的版本，我的只留诊断钩子
- 包的版本 vs 我上一条已提交的版本（fad1e84）：**包的更完整**，采用包的——
  requestID 是 UUID（我的是 Int）、超时是 Task.sleep 2 秒看门狗（我的是 poll 时检查）、
  缓存上限叫 maxCacheAge=3（我的是 cacheHardExpiry=3.0）、
  位置公式多了 **isFinite 有限值守卫**（`estimated.isFinite ? max(0, estimated) : 0`，
  duration 也验 isFinite；防 MediaRemote 返回 NaN/inf 污染进度）。
  rate 公式、2 秒超时、编号防旧回调、3 秒缓存龄、0.3 秒去重缓存，两边数值一致。
- 我的版本只留了一个诊断钩子：包的看门狗超时不记日志，1.0.5 诊断层在看门狗里补记
  `MediaRemoteDiagnostics.recordFetchTimeout()`（第 1 次＋每 10 次）。
- **冲突处理**：包基于底子，没有 1.0.5 的第 1 项诊断——整文件拷过来时自检立刻报 3 处 FAIL
  （注册通知 typealias、recordRegistration／recordNotificationFire／recordInfoCallback、
  四符号引用）。已把诊断层从 1.0.5 诊断版原样补回包的版本上
  （Register typealias＋registerForNowPlayingNotifications＋回调里的 recordInfoCallback），
  自检恢复 207 PASS。最终 adapter 与包的 diff 只剩这三处诊断补回。

### 2. PlaybackCoordinator.swift——按包的 hunks 逐个并，锁屏一律不带回
并入：latestState 与 state 分离；searchGeneration（UUID）取消守卫（stop／无音乐／换歌时轮换）；
换歌键改稳定标识 trackKey(track)（原 `newState.trackKey` 是 platform|title|artist 原拼接，
字段型播放器互换 title/artist 时会误判成不停换歌；稳定标识只用固定部分，交换后仍是同一个串）；
缓存优先搜词（本地有缓存就不联网搜）；没音乐时重置状态＋取消搜词；
暂停时拖动进度同步（|Δposition| > 0.1 时 syncPlaybackState）；
快照归属改稳定标识比对；loadLyrics 带 generation 守卫（入口／取回后／出错时）；
syncLyrics 进度基准改用 current 推算，不再回头调 adapter.currentState()。
**锁屏**：包的 coordinator 还带着锁屏代码（publishLiveLyrics 调用点＋LiveLyricKey／
lastLiveState／publishLiveLyrics 定义）——并的时候只取上面第 2 条的改动，
换歌分支里的 `publishLiveLyrics()` 调用点**跳过没并**，定义更没动；
并完 grep 确认 publishLiveLyrics／LiveLyricKey／lastLiveState 全树零处（只剩 WidgetBundle 里
一句说明移除的注释）。验包里锁屏仍须不在位（见第十一节）。

### 3. LyricParser.swift——整文件采用包的重写版
一行多个时间标签（每标签各出一行，文本取最后一个标签之后）；标准 [offset:...] 标签
（毫秒，正数提前：`time - offset/1000`，下限 0）；稳定排序（时间相同按原文顺序）。
**与逐歌偏移的叠加核对**：[offset:] 只改解析出的 LyricLine.time（解析层）；
逐歌 timeOffset 是另一层——`LyricStore.currentLyric` 在 lookup 时做
`currentElapsed(...) + timeOffset(snapshot)`，不改解析出的时间。
两层独立、可叠加、不重复计算；解析文件里没有 timeOffset／LyricStore 引用（自检已核）。
**一个真实交互**：以前给带 [offset:] 的歌手调过的逐歌偏移可能要重调——
旧解析忽略 [offset:]，手调值可能一直在替它补；现在 [offset:] 在解析层生效了，
那份手调再叠上去会 double-count。待真机验（自检 OPEN 有一项）。

### ENGINE_FIX.md／EngineTests 怎么放
- `ENGINE_FIX.md`（包的说明原文，一字未动）放仓库根目录；`EngineTests/main.swift`
  放 `EngineTests/` 目录。**两个都不进 pbxproj、不进任何编译目标**（只留文件），
  自检核「EngineTests 不在 pbxproj 里」。main.swift 是独立 LRC 回归测试
  （多标签＋[offset:500] 正数提前＋[offset:-1000] 负数延后＋非法行过滤），
  按包里的说明跑：`swiftc Lyrics/LyricLine.swift Lyrics/LyricParser.swift EngineTests/main.swift -o /tmp/engine-tests && /tmp/engine-tests`。

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

版本：`MARKETING_VERSION` 4 处 1.0.0→**1.0.5**、两 Info.plist 版本 **1.0.5**／build **20**
（build 19→20 见 §十二，模式翻转修复版）、
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
巨魔模式行为一字不动：`BackgroundKeepAlive`、Widget 刷新等宿主 guard
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
- `c6821f1` — PiP 实验引擎＋皇上树新结构（11 个新文件＋接线改动）。
- `29a26c6` — 自检升级（187 PASS）＋RUN 更新（三档→引擎／树出入／PiP 两段待验）。
  头 run 45830330430 只排到队、没跑完就被锁屏移除的新提交取代（见下），结论作废。
- `b10a2ba`（第五笔） — **1.0.5 移除锁屏（皇上 2026-11-26 21:46 令，真机从未证实可用；可从 newbase e0c154a 恢复）**。
  注：皇上原令是「先做这笔，在功能提交之前」，但这条令到时四笔功能提交已经推上去了，
  退不回去——移除仍是单独一笔、可 revert 的提交，只是顺序上落在功能提交之后。
- `ae74495`（第六笔） — 锁屏移除修正：LyricStore 注释还原（红线零删行）＋自检允许清单补 ContentView／Widget 四文件。
  头 run 45833177574（b10a2ba）在排队，未出结论就被后续提交取代。
- `839efb8`（第七笔） — 修 PiP 编译错（run 45833421434 Archive 败）：ActionAtItemEnd 用 .advance；
  height * 0.6 改 CGFloat(height) * 0.6。头 run 45834568842 success（见下节）。
- `fad1e84`（第八笔） — ChatGPT 审查两 bug 修复（皇上 22:00 令）：暂停进度 rate 公式＋
  请求超时 2 秒／编号／缓存硬过期 3 秒；全工程存储统一走 LyricStore.defaults。
- `c2b3ced`（第九笔） — Engine Fix 并入（皇上 22:03 令）：adapter 用包版＋诊断钩子、
  coordinator 按包 hunks 并（锁屏跳过）、LyricParser 整文件采用、ENGINE_FIX.md＋EngineTests 带入。
- `ea69cdd`（第十笔） — 自检升级（§13 按包改写＋§14 并入检查＋OPEN 更新）＋本 RUN 文件更新。

## 六、编译日志
- 诊断版头 run：**45828687961**，head a5ae262，workflow Build，job Build，
  status_field=completed，**conclusion=success**（排队约 6 分钟，跑约 1 分钟），
  11 个步骤全部 success，无池子取消、无重跑。
- PiP 版头 run 45830330430（head 29a26c6）：job Build 结论 cancelled、steps 0/0——
  **池子取消**，不是代码失败（run 级 conclusion=failure 是池子取消的老样子）。
  同批 45830270998（c6821f1）也是池子取消。按皇上 02:32 的定默默重跑，不报。
- 移除锁屏后头 run 45833421434（head ae74495）：**真失败**——11 步全跑完，
  败在「Archive (unsigned)」，日志两个编译错都在我写的 PiP 代码里：
  `AVPlayer.ActionAtItemEnd` 没有 `advanceToNextItem`（应为 `.advance`）；
  `height * 0.6` 里 height 是 Int、不能直接当 CGFloat 用（改 `CGFloat(height) * 0.6`）。
- PiP 编译修复版头 run：**45834568842**，head 839efb8，status_field=completed，
  **conclusion=success**，job Build success，11 个步骤全部 success——
  PiP 编译错修好了（产物未下载，最终 IPA 以并入后的新头 run 为准）。
- Engine Fix 并入后头 run：**45836245886**，head ea69cdd，第一次尝试
  status_field=completed、**conclusion=failure**——job Build 结论 cancelled、steps 0/0，
  **池子取消**，不是代码失败（晚间免费池拥堵老样子）；按 02:32 的定
  rerun-failed-jobs API 默默重跑（→201），第二次尝试 status_field=completed、
  **conclusion=success**，9 个步骤全部 success。同批中间 run
  45836176584（fad1e84）、45836223403（c2b3ced）也 success。
  产物：artifact 15128140319（名「桌面歌词-1.0.5」，1,657,346 B，
  SHA256 b320a785…）；IPA 桌面歌词-1.0.5-newbase.ipa，1,659,575 B，
  SHA256 af9e9e93…，已拷 ~/workspace/your_files/。真 IPA 验包见 §十一。

## 七、自检
`python3 check_1.0.5.py`（锚点 6857d3c）：**207 PASS，FAILED: none，OPEN 16**。
红线：LyricStore diff 零删行；9 个同步锚符号在位；两份 entitlements 与 6857d3c 一字未动；
全树无 38473／DualProcessBridge／dynamic_lookup／OverlayEngine／LyricsSyncEngine；
BackBoard 只在权限对照表里提一次名字（标签，不是实现）；
锁屏不在位：两锁屏文件不在、NSSupportsLiveActivities 不在、accessoryRectangular 不在、
ActivityKit 弱链接 0 处；
两 bug 修复在位：rate 公式＋超时 2 秒／编号／硬过期 3 秒＋过期缓存不用；
存储统一：Swift 侧除 LyricStore.swift 外无直接 UserDefaults(suiteName:)，ObjC 侧三处走 sharedDefaults；
Engine Fix 并入在位：adapter 包版＋诊断钩子、coordinator 代次／稳定键／缓存优先、
parser 多标签＋[offset:]＋稳定排序、ENGINE_FIX.md＋EngineTests 带入且不进 target。

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
     首选是 PiP——去第 13 项试 PiP；原生悬浮窗就算出来了也不算数。
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
6. **巨魔模式回归**：同一 IPA 装回越狱机 TrollStore，悬浮窗／保活／激活一切照旧；
   日志里应是「巨魔原生模式」，不应出现复核行（巨魔不复核）。
   **build 19 真机已证实这条不成立（见 §十二）——build 20 修了，重测以 build 20 为准。**
7. **不验的**：Telegram 行点没反应——1.0.5 不修这一项，不要顺手报它修没修好。
   锁屏歌词已取消（见零节），不用验。
8. **暂停进度修正**：在 30 秒处暂停，5 秒后看进度——应停在 30 秒附近，不涨到 35 秒；
   歌词行也不应跟着错误进度走。
9. **LC 激活存储统一**：LiveContainer 里激活成功后应直接进主界面，不再停留激活页；
   巨魔模式下行为不变。
10. **Engine Fix 快切歌**：快切两三首歌，歌词是否跟当前歌走（旧任务的歌词不写进新歌）。
11. **Engine Fix [offset:] 叠加**：找一首 LRC 带 [offset:] 的歌，看歌词时间对不对；
    以前给这首歌调过的逐歌偏移可能要重调（旧解析忽略 [offset:]，手调值可能一直在替它补）。
12. **Engine Fix 多时间标签**：一行多个时间标签的歌词（如副歌重复行），各时间点都应出现。
13. **PiP 实验第一段（固定测试文字）**：在 LiveContainer 里打开 App → 设置页 → 诊断（1.0.5）
   → 点「开始 PiP 测试（固定文字，实验）」，然后按 Home 回桌面、再打开别的 App（如 Safari）：
   - 若桌面／别的 App 上方出现一个小窗，里面是「悬浮测试 · 桌面歌词 1.0.5」白字黑底
     → 第一段成了，抄回日志里「PiP 已显示（实验）」那一行。
   - 若没出现，抄回日志里 PiP 那几行（「启动失败：…」或「暂不能启动…」），
     尤其是有没有 `failedToStartPictureInPictureWithError` 的错误原因。
   - 小窗是黑底不是透明、大小拖动由系统定——都是已知的实验限制，不是 bug。
   - 关掉：点小窗的关闭按钮，或回设置页点「停止 PiP」。
14. **PiP 实验第二段（实时歌词）**：第一段成了之后再试——放一首歌（先确认主界面应用内歌词
   在跟），设置页点「接入实时歌词到 PiP（实验）」，看 PiP 小窗里的行是否跟着歌词走。
   行一切换要等新视频段现编码（约半秒到一秒），不是逐字跳——逐字同步本来就没实现，
   不要按逐字标准验。若行不动，先看主界面歌词动不动：主界面不动就是识别／同步的问题，
   不是 PiP 的问题。
15. **诊断页**：设置页 → 诊断（1.0.5）→「查看诊断详情」，看模式／MediaRemote／PiP 状态／
    权限对照四区显示是否与日志一致；点「刷新快照」应记一行能力快照进日志。

## 十一、真 IPA 验包（头 run 45836245886，收尾亲验 2026-11-26）
- 产物：artifact 15128140319（1,657,346 B）→ IPA 1,659,575 B，
  SHA256 af9e9e935b2a290c54d985eb752e217027b1af7c744ac6e52f23408d2c097e48，
  已拷 `~/workspace/your_files/桌面歌词-1.0.5-newbase.ipa`（SHA 与 artifact 解出一致）。
- 包名 com.ycwl.Lyrics、版本 1.0.5／build 19、MinOS 15.0、thin arm64、
  两二进制 LC_CODE_SIGNATURE 在位、无 _CodeSignature 目录（zsign）；
  ActivityKit 两二进制均 NOT LINKED；NSSupportsLiveActivities 不在。
- 在位：同步修正（timeOffset／noMusic／needsRebuildOnUnlock；
  isDisplayEquivalent／syncLiveLyricsAndProgress 是私有方法名，Release 符号 strip，
  coordinator 本体另有 searchGeneration／requestID 等字串旁证）、
  激活（api/verify、tld.activated）、五件（tg://resolve?domain=Guhailon、
  https://t.me/Guhailon、「已固定」；「@Guhailon」9 字节短字串是 small-string，
  字节扫不到，链接串在位为准）、LC 检测（TLDSLiveContainer；
  livecontainer／/lcapps/／LCAppDelegate 同款 small-string 限制，build 18 已记）、
  三档（nativeHUD／pip／inApp、trollstore／enhanced-host）、
  三渲染器（NativeHUDRenderer／PiPLyricsRenderer／InAppLyricsRenderer／PiPFrameRenderer）、
  PiP 实验标记（「PiP 画中画歌词（实验）」「PiP 实验：未开始」）、
  诊断（dlopen／dlsym、「诊断1.0.5 MediaRemote」「诊断1.0.5 强制测试」、
  场景＋托管复核逐项日志串全在位，见验包日志）、
  Engine Fix（requestID、maxCacheAge、searchGeneration、rate／elapsed 键、
  `[offset:]` 正则字串）。
- 不在位：38473、DualProcessBridge、dynamic_lookup、NSSupportsLiveActivities、
  accessoryRectangular、LyricsLiveActivity／LiveLyricKey／publishLiveLyrics／
  LiveActivitySectionView、ActivityKit 全 0 命中；码值扫描 0 命中。
  BackBoard 字节命中 1 处，仅是 EntitlementDiagnostics 权限对照表的显示标签
  （「BackBoard 客户端（com.apple.backboard.client）」，注「未单独测」），
  无框架直链、无 API 调用——标签不是实现（§七已写明）。
- 已知缺口（不重编）：`OverlayDiagnostics.logSummary()` 全树无调用者，
  被整模块优化裁掉，字串「诊断1.0.5 悬浮窗复核摘要：」不在包里；
  日志页少这一行冗余摘要，等价内容已有 ObjC 侧「托管复核结论」行＋
  诊断页摘要行（summaryLines 三行在位）覆盖。§二样例「windowScene 通过」
  是意译，源码原文是格式串「windowScene %@，rootView 已挂到 window %@」，
  两段都在位。
- 验包记录：`hidden_files/ipa_verify_1.0.5.log`（本机留存，不进 git）。

## 十二、build 20 修复：模式翻转＋检测引擎重复启动（皇上 2026-11-26 22:50 令，修＋重编）

### 病根（皇上真机日志，`hidden_files/device-log-1.0.5-20261126-2247.txt`）
越狱 iPhone 11，TrollStore 装的 build 19，两次启动同一模式：
启动写 `trollstore`／「巨魔原生模式」，2 秒后托管复核跑了，逐项全过，
把模式改成 `enhanced-host`／「增强宿主模式」，首选变 PiP 实验，
原生悬浮窗反被标「权限受限、不信任」。§十第 6 项的标准是巨魔机日志应是
「巨魔原生模式」、不应出现复核行——build 19 两条都不成立。

代码核实（`Overlay/TLDSAppDelegate.m`）：
- 巨魔分支（约 122 行）只调 `setRunMode:@"trollstore"`，**从不置 `modeDecided = YES`**；
  `modeDecided` 全文件只在两处被置 YES——复核通过处（约 427 行）和降级处（约 446 行）。
- `createFloatingScene`（约 318–325 行）建完场景后**无条件** 2 秒 dispatch_after
  排 `verifyFloatingVisibility`，只看 `!self.modeDecided`。
- 所以巨魔机上复核必跑、必过、必改模式。注释写「巨魔模式不走这里」，代码没拦住。

### 修法（三道守卫，提交 `8aa0bdc`）
1. 巨魔分支定档时就把 `modeDecided = YES` 置上——2 秒复核的 `!modeDecided` 守卫直接拦住。
2. `createFloatingScene` 里 2 秒复核的排期改成只在宿主分支排
   （`if ([[TLDSRuntime shared] isHosted])` 包住 dispatch_after）——
   巨魔机上连排期都没有，日志里不应出现复核行。
3. `verifyFloatingVisibility` 入口再加一道模式守卫：模式已是 `trollstore`
   就直接返回，不写日志、不改模式（读 `[[TLDSRuntime shared] runModeString]`）。
   6 秒兜底复核在宿主分支里，同样只看 `!modeDecided`，巨魔机不受影响。
修完巨魔机日志应是：启动「巨魔原生模式」后**无任何复核行**，模式不再翻。

### 检测引擎一次启动跑了 5 次（同份日志，第二次启动 14:46:36–42）
`PlaybackCoordinator.start()` 计数到第 5 次，其余计数全是 1。
调用点：`App/ContentView.swift:198`（「开始检测音乐」按钮）、
`App/TrollLyricsDeskApp.swift:134`（TLDSRuntime.start 里自动跟随，
本身已有 `started` 守卫，只调一次）、`Overlay/TLDSAppDelegate.m:112`
（runtime start）。皇上没回是不是他连点了按钮——**不等他回**：
`start()` 已做成幂等：`timer != nil`（已在跑）就直接返回，记一行
「检测引擎已在运行，跳过（不重复记数）」，不重复记数、不重复建检测任务；
停过（timer 已清）再调才算一次新启动。按钮连点、前台回来自动重调都拦在这一处。

### 不动的
锁屏继续拿掉（没带回来）；三档模式、三渲染器、诊断、强制测试文字、
PiP 实验、Engine Fix、激活、包名 com.ycwl.Lyrics 全不动；零新增 entitlements。
版本只动 build：两 Info.plist build 19→20，MARKETING_VERSION 仍 1.0.5，
workflow 产物名仍是 `桌面歌词-1.0.5.ipa`。自检升级到 **211 PASS，FAILED: none，
OPEN 16**（§15 四项新检查全过）。

### 头 run 与验包（待填）
- 头 run：（待云端构建后填）
- 验包：（待真 IPA 验包后填）

### 新待验项（build 20，巨魔机重测）
1. **模式恒巨魔原生**：越狱机装 build 20，打开 App，等 5 秒，进关于页 → 日志——
   应只有启动那一行「运行模式：巨魔原生模式」，**全文不应出现任何「托管复核」
   「复核」行**；「运行模式：写入」应只有 trollstore 那一行，不应出现 enhanced-host。
2. **检测引擎计数恒 1**：同一次启动内「检测引擎启动第 N 次」应恒为 1——
   连点几次「开始检测音乐」也只记 1 次有效启动（多点只记跳过行，不建新任务）；
   切后台再回来也不应再涨。
3. LC 那边等皇上另测：LC 里应仍是「待探测」→ 复核定档（增强宿主／普通签名兼容），
   巨魔修复不改宿主分支行为。

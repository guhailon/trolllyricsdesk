# RUN_1.0.6.md — TrollLyricsDesk 1.0.6（Build 20）LiveContainer 专项兼容修复版

## §一 版本与基线

- **版本：1.0.6，build 20**（MARKETING_VERSION 1.0.6、CURRENT_PROJECT_VERSION 20；两 Info.plist、pbxproj、build.yml 产物名 `桌面歌词-1.0.6.ipa`）。
- **基线：newbase 分支 HEAD 4f43991**（1.0.5 源码，build 19）。
- **分支：v1.0.6-lc**（从 4f43991 建，远端 ref 已建；旧 `v1.0.6` 分支是已废弃的旧线，绝不碰；newbase 仍停在窄修 d9375b2，备查，不动）。
- **包名 com.ycwl.Lyrics，MinOS 15.0 不变；锁屏不恢复；UI 不改；零新增 entitlements。**
- **diff 规模（vs 4f43991，工作区实测）**：25 个文件改动（+841/-186）＋ 1 个新文件 `Compatibility/EffectiveEntitlements.swift`（144 行）＋ 自检 `check_1.0.6.py`（1034 行）＋ 本 RUN。最大的一处是 `Overlay/TLDSAppDelegate.m`（+293/-65）。

## §二 并入 ChatGPT 1.0.6 ZIP（皇上 23:18 批准「并进 1.0.6」，选择性并入）

来源：`~/workspace/user/files/桌面歌词-1.0.6-ChatGPT-源码.zip`，972,203 B，SHA256 `ec12dd60fce59ea185a7e5a9e738b44872d9666c8f993e419e0ff58a794656c9`，94 个文件（93 个 4f43991 基线文件＋RUN_1.0.6.md）；差异 23 个文件，+146/-132 行；码值扫描干净；entitlements 零改动；包名不动；激活没动；锁屏没恢复；无 TCP 桥；版本已是 1.0.6/20。

并了哪几处（逐项核对过）：

1. **MediaRemoteAdapter.swift**——GetNowPlayingInfo 回调改 `@convention(block) (CFDictionary?) -> Void`；RegisterForNowPlayingNotifications 改只收 DispatchQueue（删掉 1.0.5 传的那个假回调——系统根本不调它）；调用改主队列；字典非空缺标题时记日志（第 1 次／每 50 次）。
   - **注意（P0 首要怀疑）**：23:24 坐实——iPhone 18 Pro Max／iOS 27.0.1／LiveContainer，QQ 音乐在播，GetNowPlayingInfo 回调只触发一次且 info=nil。1.0.5 的假回调在 LC 里可能就是 info=nil 的直接原因。并入时这处重点核对；真机验的第一项就是：放着 QQ 音乐，看回调里 info 有没有内容、歌名读不读得到。
   - 咱们 1.0.5 的 `recordNotificationFire` 回调路径在它这版里没了——并入时诊断层没丢：`recordNotificationFire` 函数仍在 `MediaRemoteDiagnostics.swift`（供记录），但 Adapter 已不再调它；轮询是主数据源，`notificationFireCount` 正常是 0，不是故障。
2. **PlaybackCoordinator.swift**——`start()` 改幂等（`guard timer == nil`，已有就记「检测引擎已运行，跳过重复启动」并返回）；poll 里加 `timer != nil` 守卫。不再用先 stop 再 start 的写法。
3. **TLDSAppDelegate.m**——非宿主分支改写 `native-candidate`（原因「未发现宿主信号；安装来源及权限未知」），包 @try/@catch，异常降级；复核通过分支里，非宿主时写 `native-candidate`、记「托管结构检查通过；安装来源未知；实际屏幕可见性未确认」后 return，**不再写 enhanced-host**；结论行「已确认可见」改「托管结构检查通过；实际屏幕可见性未确认」；可见性收紧（`windowVisible` 加 `alpha > 0`；`viewAttached` 改 `view.window == w`；Context ID 取值无 unsignedIntValue 方法时算 NO）；降级日志改「兼容模式（托管检查未通过，安装来源不由此推断，应用内歌词）」。其余只是 1.0.5→1.0.6 的日志前缀改名，照抄。
4. **RuntimeEnvironment.swift / RuntimeCapabilities.swift / EntitlementDiagnostics.swift / Diagnostics/*.swift / LyricStore.swift**——`native-candidate` 映射到原生 HUD；诊断页文案改诚实版（「原生候选：实际可见性未确认」「有效权限未测；IPA 声明不代表进程权限」——后一句在 1.0.6 里已被实测值取代，见 §三第 5 项）；MediaRemoteDiagnostics 每 50 次回调记一次、nil 时清 lastInfoTitle；LyricStore 的 LC 信号路径加 processName＋NSHomeDirectory()。
5. **SettingsView.swift / TrollLyricsDeskApp.swift / renderers / TLDSSceneDelegate.m / FloatingLyricViewController.swift**——只有日志前缀改名，无行为改动，直接照抄前缀。
6. **版本**——两 Info.plist 已是 1.0.6/20，pbxproj CURRENT_PROJECT_VERSION 1→20、MARKETING_VERSION 1.0.5→1.0.6，build.yml 产物名改 1.0.6，照抄。

## §三 按 10 项自做（不在 ZIP 里的＋ZIP 没做完的）

1. **第 1 项（重写 RuntimeEnvironment）**——`Compatibility/RuntimeEnvironment.swift`：`InstallEnvironment` 四档（trollstore／livecontainer／signature／unknown）＋`DisplayCapability` 三档（nativeHUD／pip／inApp）＋`detectInstallEnvironment()`（LC 信号→livecontainer；TrollStore 正面证据→trollstore；已证实被沙盒拦住→signature；否则 unknown）；`if (!isHosted) → trollstore` 那行已删；`preferredEngine` 里 `trollstore` 与 `native-candidate` 同走 nativeHUD（两档模式，首选引擎相同）。
   - 证据：日志开头的「trollstore」是确认的误判——完整版日志（14:44:49Z–15:04:48Z，三次启动）全是 iPhone 18 Pro Max／iOS 27.0.1 这台 LC 手机上的（皇上 23:20「关于本机」截图确认），不是 iPhone 11。以后不要再把这份日志当巨魔机日志来读。
2. **第 2 项（三项判定分离）**——`Lyrics/LyricStore.swift` 新增 `tlds.installEnvironment`／`tlds.installEnvironmentReason`／`tlds.displayCapability`／`tlds.displayCapabilityReason` 四键＋中文描述；`App/TrollLyricsDeskApp.swift`（TLDSRuntime）新增 `setInstallEnvironment`／`setDisplayCapability`／`detectInstallEnvironment()`／`installEnvironmentString()`／`environmentTag()`；`Diagnostics/DiagnosticsView.swift` 模式区追加「安装环境：…（理由）」「显示能力：…（理由）」两行；`Compatibility/RuntimeCapabilities.swift` 的 `nativeHUDProbePassed` 改读 displayCapability，`logSnapshot` 带环境标签。托管复核只定显示能力——delegate 的 native-candidate 分支写 `setDisplayCapability:@"nativeHUD"`，不改安装环境。
   - 注意：Info.plist 键 TLDSLiveContainer 在本工程里从来没设过值，所以 plist 这一路信号在单 IPA 里永远不命中——不是 bug，是设计；单 IPA 不能把它写死 true，否则巨魔机也会被判成宿主。
3. **第 3 项（检测引擎重复启动）**——`PlaybackCoordinator.swift`：`start()` 幂等（`guard timer == nil`，见 §二第 2 项）＋ poll 加 `timer != nil` 守卫；`App/TrollLyricsDeskApp.swift` 的 TLDSRuntime.start() 仍有 `started` 守卫（重复调用记「已启动，跳过」）。
   - 证据：完整版日志里检测引擎累计 12 次（14:46:36=2、14:46:37=3、14:46:41=4、14:46:42=5、14:47:33=6、14:47:34=7、14:47:35=8、14:47:35=9、14:47:44=10、11、12；第 8 次实际存在，ChatGPT 的图漏了 8，不是日志缺了 8；14:47:35 一秒两次，14:47:44 一秒三次，成簇出现，像前台回来触发的连锁重调）。23:23 重测那次只启动 1 次——12 次那次是 14:46–47 那段独有的（可能连点按钮），不要误读成每次启动都这样；修完同一启动内计数恒为 1。
4. **第 4 项（MediaRemote 诊断再分细，P0）**——`Diagnostics/MediaRemoteDiagnostics.swift`：新增 `recordRequest()`（发出调用即记）、`recordIsPlayingQuery()`、`recordIsPlaying(_:)`（isPlaying 探针结果，首次／变化时记行；isPlaying=YES＋info=nil 时另记一行 P0 明确结论）、`recordMissingTitle()`（字典非空缺标题，「解析失败」的证据）、`readStatus`（ok／P0 放着歌还读不到／可能没放歌／疑似 P0／超时／受限／解析失败／未测／等回调）、`summaryLine` 改带环境标签（`RuntimeCapabilities.environmentTag`：「安装环境=…，iOS …」）与调用／回调次数；`MusicProviders/MediaRemoteAdapter.swift`：info==nil 时触发 isPlaying 查询（5 秒节流），调用时记 `recordRequest()`，缺标题时记 `recordMissingTitle()`。
   - isPlaying 探针：`MRMediaRemoteGetNowPlayingApplicationIsPlaying`，符号已在 `Core/MediaRemoteSymbols.swift` 里声明（从未被调用过）；假定签名 `(dispatch_queue_t, completion(Boolean))`，completion 亦为 block（与 GetNowPlayingInfo 同族；1.0.5 的假回调教训——回调签名必须按 block 声明，否则系统根本不调它）；Boolean 用 UInt8 接（!= 0 为播放中）；符号缺失时回退，不伪造。**签名待真机验证。**
   - 证据：三次启动各只有一次「GetNowPlayingInfo 回调已触发（第 1 次），info=nil」——检测引擎重启 12 次后没有任何新的回调行；回调只在变化时触发，还是后续调用没回来，第 4 项把调用次数、回调次数、info 内容三者分开记。QQ 音乐那测（23:04）与重测（23:24）都是这台 LC 机上、放着歌还 nil——P0 坐实，不是没放歌。
   - `Diagnostics/DiagnosticsView.swift` MediaRemote 区追加「调用 N 次／回调 N 次／isPlaying 查询 N 次」一行。
5. **第 5 项（进程实际有效 entitlements）**——新文件 `Compatibility/EffectiveEntitlements.swift`（144 行）：SecTask 任务权限用 dlsym 拿（不链接 Security、不依赖头文件；符号不存在返回 nil）；沙盒外写探测（`/var/mobile/.tlds-entitlement-probe-<pid>`，O_WRONLY|O_CREAT|O_EXCL，成功即删；success／denied（EPERM／EACCES）／unknown 三档）；`trollStoreEvidence()`（任务权限 platform-application 与 no-sandbox 均为 true，或写探测成功）／`sandboxedProven`／`logReport()`；只探一次，结果全进程复用。`Compatibility/EntitlementDiagnostics.swift` 的平台应用／解除沙盒实测列改读 EffectiveEntitlements 实测值（优于 ChatGPT 的「有效权限未测」写法）。
   - **pbxproj 已补**：新文件进了 Compatibility 组＋App Sources（fileRef `5C02EAF8BF57F25B9D542084`，buildFile `03DCE81710CF9BD1E9EF9294`，新 ID 已验无碰撞）；没进 pbxproj 就编不进去，1.0.6 自检 §8 有一项专查这个。
   - LC 客人继承不到宿主没有的权限，这点写进判定和诊断页。
6. **第 6 项（悬浮窗可见性误判修正）**——`Overlay/TLDSAppDelegate.m`：复核入口守卫（`modeDecided || !shouldVerify` 即返）；可见性收紧（见 §二第 3 项）；Context ID 三态（未知／有效／无效），未知不进判定；结论行写清三段（托管结构检查：通过／Context ID：未知／实际屏幕可见性：未确认）；「已确认可见」活着的只剩三处注释（TLDSAppDelegate.h:88、TLDSAppDelegate.m:409、OverlayDiagnostics.swift:8，都是「不再用这句」的说明），日志行里没有。
   - **14:59:44 第二个悬浮窗（ChatGPT 没见过那段日志，没修；1.0.6 里修了）**：重建先销毁旧场景会话（openSessions 按旧标识找会话 → `requestSceneSessionDestruction` 公开 API，失败只记日志；binder 摘场景、窗口隐藏各记一行；重建前后 `logLiveFloatingScenesWithTag` 记活着的悬浮场景数与标识）。证据：14:59:44「锁屏恢复：完整重建悬浮场景」时 createFloatingScene 第 2 次，标识变成 TLDSFloatingLyric_1，控制器初始化第 2 次，App 自己报「悬浮窗控制器初始化了多次（可能建了两个窗）」；日志里没看到旧场景／窗口的销毁行。23:23 重测那次没有第二个悬浮窗——TLDSFloatingLyric_1 是解锁重建那一次独有的；重建先销毁的修法触发条件就是解锁重建那条路径。
7. **第 7 项（激活前后悬浮窗口状态检查）**——`App/ActivationView.swift`：onAppear 发「激活前」快照通知，`activate()` 成功后发「激活成功后」快照通知（经 `LyricStore.logFloatingWindowState(tag:)`）；`Lyrics/LyricStore.swift` 新增 `logFloatingWindowState(tag:)`（发 `TLDSLogFloatingWindowState` 通知，userInfo 带 tag）；`Overlay/TLDSAppDelegate.m` 接住后记窗口状态（窗口在不在、isHidden、windowScene、frame），「激活前」每进程只记一次。证据：真机日志里激活成功（code）在 14:45:36，激活前后各有一次「锁屏恢复：重新显示悬浮窗口」——把这条线查清楚、记清楚。
   - 注意：`LyricStore.logFloatingWindowState` 原是通知名的 static let，与新加的同名 static func 会重声明冲突——let 已改名 `logFloatingWindowStateNotification`，func 名不变。
8. **第 8 项（LC 后台运行及进程终止原因）**——`Overlay/TLDSAppDelegate.m`：启动时读上次退出状态记推断（`tlds.lastExitState`／`tlds.lastExitTime`：terminated-clean／background 未收 WillTerminate／foreground 未收 WillTerminate／首次启动）；后台处理写退出状态（DidEnterBackground 写 background；WillTerminate 写 terminated-clean）；新增 `applicationDidReceiveMemoryWarning`（疑似 jetsam）；前台／看门狗触发改走 `tlds_reactivateFromForegroundNotification`／`tlds_watchdogReactivate`。
   - 证据：14:45:39 有一次 App WillTerminate，随后 14:45:44 重新启动；15:03:01 第三次启动（全部计数归零），14:59:44 到 15:03:01 之间**没有 WillTerminate 行**（进程又死了一次，原因不明）；23:23 重测：上一个进程 15:07:57 主场景 WillResignActive → 15:07:59 DidEnterBackground → 15:08:06 App WillResignActive＋DidEnterBackground＋WillTerminate 同一秒——进程在后台只活了约 3 分钟就被终止。**后台保活弱是已证实的**，不是猜测。
   - 注意：LC 下 `BackgroundKeepAlive` 启动时就被跳过（`if !LyricStore.isLiveContainer`），所以 LC 里后台 3 分钟被终止是预期行为（无音频断言），不是保活 bug——第 8 项只记事实，不谎称是 bug。能查到的查，查不到的写「原因未知」，不编。
9. **第 9 项（PiP 独立验证）**——`Renderer/PiPLyricsRenderer.swift`：两段独立状态（固定文字段 `tlds.pipTestStage`／实时歌词段 `tlds.pipLiveStage`，各有未开始／进行中／已显示／失败＋原因），delegate 回调按 `testLooping` 分段写；原有 combined status 不动；`Diagnostics/DiagnosticsView.swift` PiP 区追加「固定文字段：…」「实时歌词段：…」两行。PiP 实现本身不动。
   - AVSampleBufferDisplayLayer 实时帧渲染：**只研究、不实现**——可行性／限制评估见 §八，等皇上定。
10. **第 10 项（保留）**——巨魔原生悬浮歌词、激活接口 POST /api/verify 不变、逐歌偏移、Engine Fix 全部修复（rate、超时、requestID、缓存、代次、缓存优先、多时间标签、[offset:]）。`Lyrics/LyricStore.swift` 的同步修正符号（timeOffset／offsetKeyPrefix／stableSongIdentity／artistCarriesLyric／songIdentityParts／noMusicKey）在 1.0.6 diff 的删行里一个都没动（自检 §11 专查）。

**前缀统一**：协调员改过的文件里残留的 `诊断1.0.5` 日志前缀已统一成 `诊断1.0.6`（TLDSAppDelegate.m 44 处、TrollLyricsDeskApp.swift 4 处、RuntimeCapabilities／RuntimeEnvironment／EntitlementDiagnostics 各 1–2 处；注释里的历史 1.0.5 引用除外）；PiP 测试文字与 SettingsView 测试文字说明里的「桌面歌词 1.0.5」已改 1.0.6（LyricStore.testText() 已改）。

## §四 1.0.6 自检（check_1.0.6.py，1034 行）

- **250 PASS，0 FAIL，28 OPEN**（2026-11-26，第 3 笔 d699df1 后重跑；原 242 PASS，Widget 修后 §15 加 8 项防回归）。
- 自检锚点：BASE = 4f43991；版本 1.0.6／build 20；红线 diff 只允许 §二§三的 26 个文件＋check＋RUN；LyricStore 同步修正符号删行 0；entitlements 与 4f43991 一字未动；锁屏不在位；无 38473／DualProcessBridge／dynamic_lookup；码值扫描 0；§15 专查 10 项逐项落点。
- 自检中修掉的 3 处都是自检脚本断言写错、代码本身没错（已修正后重跑全过）：①ObjC 侧 `[TLDSRuntime sharedDefaults]` 1.0.6 是七处不是三处（含退出状态读写）；②`if (!isHosted)` 只剩 RuntimeEnvironment.swift:38 的注释引用；③`TLDSFloatingLyric_1` 只剩 rebuild 注释里对 14:59:44 教训的说明。

## §五 编译日志

- 头 run **45850840777**（head e091bf0）：排队＋5 次池子取消（Build cancelled、0 steps）后终于上了机器，**Archive (unsigned) 真失败**（job 140058674420，11 steps：Checkout／Xcode／zsign 过，Archive 挂，后面全 skipped）。
- **病根（日志亲验，`hidden_files/job-45850840777.log`）**：`Lyrics/LyricStore.swift:404:9: error: cannot find 'InstallEnvironment' in scope`、`423:9: error: cannot find 'DisplayCapability' in scope`——错在 **Widget target**，不在 App target。Widget 只编 6 个 Swift 文件（TrollLyricsWidget／WidgetView／WidgetWidgetBundle／LyricLine／LyricParser／LyricStore），`InstallEnvironment`／`DisplayCapability` 在 `Compatibility/RuntimeEnvironment.swift` 里，只在 App target 的 Sources 里，Widget 看不到。1.0.5 能编过是因为 LyricStore 当时没引用这两个枚举；1.0.6 协调员加 `installEnvironmentDescription`／`displayCapabilityDescription` 时直接用了枚举，漏了 Widget 这一路。
- **修法（第 3 笔 d699df1）**：LyricStore.swift 两处改字符串 switch（显示名与枚举 displayName 一字不差）；自检 §15 加两项防回归——Widget 6 文件代码行不引用 App-only 类型、7 个显示名两边一致。自检重跑：**250 PASS，0 FAIL，28 OPEN**。
- 新头 run **45864188284**（head d699df1）：**completed／success，11 步全 success**（job 140078068668：Set up job／Checkout／Xcode version／Install zsign／Archive (unsigned)／Verify archive layout／Sign with zsign (TrollStore)／Package IPA／Upload artifact／Post Checkout／Complete job）。排队＋2 次池子取消（Build cancelled，steps 0；rerun-failed-jobs → 201 默默重跑），第三次尝试 success。
- 池子取消按皇上 2026-11-26 02:32 的定默默重跑（rerun-failed-jobs），不报；只报编成（验包后发包）或真失败。轮询读 `status_field`／`conclusion`。

## §六 验包（编成后下载真 IPA 亲验，不要只信 run 绿）

- **验包 PASS（68 项，`hidden_files/verify_1.0.6.py`，详见 `hidden_files/ipa_verify_1.0.6.log`）**。
- IPA：`~/workspace/your_files/桌面歌词-1.0.6-newbase.ipa`，**1,675,065 B，SHA256 `70e8b3299c91f1a568d747a55eb5a0a4785240df26de011a89ab3ffb08b0043c`**（artifact id 15142575825，名 桌面歌词-1.0.6，1,673,164 B；解出与拷本 SHA 一致；build 19 旧包未动）。
- 版本 1.0.6／build 20、包名 com.ycwl.Lyrics、MinOS 15.0；widget 1.0.6／build 20、com.ycwl.Lyrics.TrollLyricsWidget、MinOS 15.0。
- 锁屏不在位（NSSupportsLiveActivities／accessoryRectangular／LyricsLiveActivity／LiveLyricKey／publishLiveLyrics 全 0）；无 38473／DualProcessBridge／dynamic_lookup；ActivityKit 未链接；直链 FrontBoard／FrontBoardServices／RunningBoardServices／AppleAccount 在位；权限与 1.0.5 一致（app：application-groups、group.com.hailong.TrollLyricsDesk、platform-application、get-task-allow；widget：application-groups、group.com.hailong.TrollLyricsDesk），零新增。
- 同步修正、激活、五件、三档、三渲染器、PiP 实验标记（「悬浮测试 · 桌面歌词 1.0.6」）、诊断串（1.0.6 前缀）、Engine Fix 串全在位；第 6 项新结论「托管结构检查通过；实际屏幕可见性未确认」在位，「已确认可见」0 命中；第 4 项 P0 行「P0——放着歌还读不到」在位，isPlaying 探针符号在位；第 9 项 PiP 两段键在位；第 1 项 native-candidate 在位；LC 检测三字串 livecontainer（×3）／/lcapps/（×1）／LCAppDelegate（×1）字节扫描都在位（1.0.5 的 small-string 限制在 1.0.6 已不适用）；BackBoard 仅 1 处对照表标签；码值扫描 0 命中。
- 注意：ObjC @"..." 含中文的字面量以 UTF-16 进 __ustring，UTF-8 查不到；验包脚本已改双编码字节直查。

## §七 真机验证清单（分两条线写，不要把两台机的期望混在一起）

### A. 主线：LC 机 iPhone 18 Pro Max／iOS 27.0.1（LiveContainer）

1. **P0 第一项：放着 QQ 音乐，看回调里 info 有没有内容、歌名读不读得到。**签名修正（回调改 block、注册改只收队列）是首要怀疑。若放着歌仍 info=nil，诊断页应写「P0：放着歌还读不到（isPlaying=YES，info=nil）」，日志里应有对应的 P0 行；若读到了，readStatus 应是 ok，歌名正常显示。
2. **安装环境行：不应再出现 trollstore／模式翻转。**启动时安装环境应是 livecontainer（LC 信号命中）或 unknown（信号全漏时落 native-candidate），绝不是 trollstore；2 秒后不应出现复核改模式的行；结论行应是「托管结构检查通过；实际屏幕可见性未确认」，不是「已确认可见」。
3. **三项判定各自是什么（诊断页分行看）。**安装环境／显示能力／权限对照三行各自的结论与理由；托管复核只定显示能力，安装环境行在复核后不应变；Context ID 未知时结论行写清三段（托管结构检查：通过／Context ID：未知／实际屏幕可见性：未确认）。
4. **检测引擎计数恒为 1（同一次启动内）。**12 次重启那次是 14:46–47 那段独有的（可能连点按钮）；重测干净单次启动是对照；修完同一启动内「检测引擎启动第 N 次」应恒为 1，前台回来也不重起。
5. **解锁重建不应再建第二个悬浮窗。**14:59:44 那次建了 TLDSFloatingLyric_1、旧窗疑似还在；修完重建前应先销毁旧场景／旧窗口，诊断里记清当前有几个悬浮窗、各自什么标识；只建一个窗。
6. **后台终止原因：进程后台活多久、终止时记了什么。**23:23 重测：进程后台只活约 3 分钟就被终止；第 8 项只记事实——系统杀／宿主杀／自己退，查不到写「原因未知」，不编；LC 下保活本来就被跳过，后台 3 分钟被终止是预期行为。
7. **PiP 两段分开验（固定文字段先，实时歌词段后）。**两段各有各的诊断页状态行（未开始／进行中／已显示／失败＋原因）；PiP 能显示不代表能自动拿到别的播放器的歌。
8. **激活前后快照：激活成功不应丢窗。**激活前、激活成功后各记一次悬浮窗状态（窗口在不在、isHidden、windowScene、frame）；14:45:36 激活成功前后那两条「锁屏恢复」行要能对上快照。
9. **悬浮窗在后台／回前台时状态不明，不要下结论。**23:23 重测：主场景 15:22:51 进后台、15:23:19 回前台，悬浮场景没有对应的后台行——诊断里不要对这段下结论。

### B. 另一条：巨魔机 iPhone 11／TrollStore（巨魔原生回归）

1. 日志应是「巨魔原生模式」，**无复核行**（巨魔分支定档时 `modeDecided = YES`、`shouldVerify = NO`，复核不排）。
2. 检测引擎计数恒为 1。
3. 悬浮窗照常、激活照常、逐歌偏移照常。
4. 与 LC 机分开列期望，不要把两台机的结果混在一起判。

## §八 AVSampleBufferDisplayLayer 可行性／限制评估（后续候选，只研究、不实现）

- **背景**：ChatGPT 建议后续研究基于 AVSampleBufferDisplayLayer 的实时帧渲染，替代现在「每句歌词现编码一段 H.264 视频」的方式（可能有延迟、额外编码开销和队列积压）。
- **可行性（待验证，未证实）**：AVSampleBufferDisplayLayer 是 AVFoundation 的公开类，可直接把 CMSampleBuffer 帧送显，不经过 AVQueuePlayer／PiP 控制器；理论上延迟更低、无编码开销、无队列积压。1.0.6 的 PiP 仍走 AVPictureInPictureController＋AVQueuePlayer＋H.264 视频段（实验），这条路不动。
- **限制（写清，不回避）**：
  - AVSampleBufferDisplayLayer 本身不是 PiP——它只是一个显示层，要浮在桌面／其他 App 上方仍需一个宿主窗口（原生 HUD 的 FrontBoard 场景或 PiP 控制器），不能只靠这个层解决「浮到别处」的问题。
  - 帧从哪来仍需自己画（Core Graphics 画文字 → CVPixelBuffer → CMSampleBuffer），每行歌词仍要生成一帧，只是省了 H.264 编码一步，不是零成本。
  - 在 LC 宿主里能否拿到可合成到屏幕上的层、后台行为如何，均未验证；PiP 的透明背景受限、拖动由系统控制、锁屏不保证这些限制，换层不一定能绕过。
  - 与第 9 项无关：PiP 能显示不代表能自动拿到别的播放器的歌，跨应用音乐读取是 MediaRemote 的事（第 4 项），换渲染层不解决。
- **结论**：列为后续候选，等皇上定；1.0.6 里不实现、不改 PiP。

## §九 OPEN 项（只能真机／macOS 编的，如实列，不编通过）

- macOS 编译未做（Linux 没 Xcode/swiftc）；编成后以 GitHub Actions 头 run 为准。
- isPlaying 假定签名待真机验证（(dispatch_queue_t, completion(Boolean))，completion 为 block）；符号缺失时回退、不伪造；若 LC 机上 isPlaying 查不到，readStatus 应是「疑似 P0」而不是编一个结论。
- LC 信号在确认的 LC 机上是否命中（父进程名探测 `proc_pidpath(getppid())` 是否为 LiveContainer）；若 LC 信号全漏，安装环境落 signature／inApp，行为正确、标签待收敛。
- `os_proc_available_memory` 后台内存读数（第 8 项终止原因的辅助证据）；只记读数，不由此编终止原因。
- LC 里首次调用 FBSystemShellInitialize 的风险未验证（1.0.5 为探测增强宿主改为尝试＋复核，调用包在 @try/@catch 里；若 LC 真机启动就闪退，第一嫌疑就是这次尝试——日志里若连「待探测」都没有，就是启动时崩了）。
- 三档模式的复核时序未验证（复核在创建后 2 秒跑、场景未连上时 3 秒后再跑一次；真机上场景连接若慢于 5 秒，会误判兼容）。
- 1.0.5 的功能回归（五件／激活／三档／三渲染器／PiP 实验／Engine Fix／同步修正）要真机验，见 RUN_1.0.5.md 待验清单；锁屏已取消，不再验。
- 皇上 22:50:20 要的「最新的 1.0.5 完整源码 ZIP」——1.0.6 令下后未再提，待定，不要拿 build 19 的旧 ZIP 充数。

## §十 提交链

- 第 1 笔 `2606458`：1.0.6 核心（26 个文件，+985/-186）——RuntimeEnvironment 重写＋实测权限＋MediaRemote 签名修正＋start() 幂等＋native-candidate＋PiP 两段＋激活快照＋版本 1.0.6/20。
- 第 2 笔 `e091bf0`：check_1.0.6.py（242 PASS）＋RUN_1.0.6.md。
- 第 3 笔 `d699df1`：Widget 编译修——LyricStore 两处枚举引用改字符串 switch＋自检防回归（250 PASS）＋RUN 补失败经过。
- 第 4 笔（待补）：RUN 补头 run 45864188284 成功＋验包节。
- 头 run：45864188284（head d699df1）completed／success；IPA `桌面歌词-1.0.6-newbase.ipa`，1,675,065 B，SHA256 `70e8b329…`，验包 68 项全过。
- 分支：v1.0.6-lc（绝不从沙盒 git push；每笔先 check 再 gh_push.py 推；不要动 newbase／main／旧 v1.0.6 分支）。

## §十一 build 21（1.0.6/build 21，两处修：#1 重建竞态＋SecTask 三参数）

### 为什么修

- **#1 最可疑（主因）**：1.0.6 build 20 在 LC 机（硬件 iPhone 13 Pro，iOS 27.0.1——「iPhone 18 Pro Max」是皇上自己改的显示名）上进主页面就闪退，1.0.5 同台不闪。皇上 **2026-11-27 02:19 证实崩的时机是「主页面立刻闪」**——主页面一出现就闪，不是停一两秒后才闪。按审计的时机表，这指向第一批：DidBecomeActive → reactivate → rebuild（#1 那条路），或第一次轮询 → isPlaying 探针（#2）；2 秒看门狗不太可能是第一下。皇上 **02:22 又确认：重启手机后还是进主页面立刻闪**——重启清掉了内存压力还照样闪，说明不是内存紧那一下，是代码那处撞上了。#1 仍是最可疑，修 #1、编 build 21 的方向是对的。
- **SecTask 是真隐患（顺带修）**：皇上发来的 ChatGPT 链接（第 7 条）指出 `Compatibility/EffectiveEntitlements.swift` 第 49、55 行——`SecTaskCopyValueForEntitlement` 正确要 3 个参数（task、key、CFErrorRef *error），咱们的 CopyFn 只定义了 2 个、调用也只传 2 个。父级亲手核过代码，确实如此；协调员也亲自核过（见下）。但注意：7 个要查的键在 entitlements 文件里全都有，查都会成功，成功时系统不会往那个缺失的参数里写东西，所以这次闪退很可能不是它；而且它跑在主页面出现之前，崩了就看不到主页面——皇上是看到主页面立刻闪，时间对不上。皇上 **2026-11-27 02:27 定：两个都修，放进 build 21**。

### 改了什么（两笔提交，分开写清）

- **第 1 笔 `3c39be6`（#1 重建竞态）**：新锚点 `floatingSceneEverConnected`（`TLDSAppDelegate.h` 声明；`createFloatingSceneWithIdentifier` 里创建时清 NO；`TLDSSceneDelegate.m` willConnectToSession 悬浮分支里连上后置 YES）——区分「建了还没连上（连接窗口，绝不能销毁／重建）」和「连上过、后来断开（可以销毁重建）」。`rebuildFloatingOverlay` 里只有旧场景曾经连上才调 `requestSceneSessionDestruction`；旧场景建了还没连上时跳过销毁，只做 binder 摘场景＋窗口隐藏（走 1.0.5 的做法），让正在连接的会话自然完成或被放弃。触发侧（DidBecomeActive 的 `tlds_reactivateFromForegroundNotification` 与 2 秒看门狗 `tlds_watchdogReactivate`，都走 `reactivateFloatingOverlayWithTrigger:`）在连接窗口里跳过这次恢复（20 秒节流日志），等连接完成后再说。14:59:44 第二窗修法不回归：连上过、后来断开的旧场景照旧销毁。
  - 为什么不用 `floatingSceneCreated` 判断：它只表示「当前连着」，连上过、后来断开的场景也会是 NO——那一路（解锁重建）必须照旧销毁，否则旧窗残留。
  - 另：`didFinishLaunching` 里 `lastRebuildTime` 的 3 秒启动宽限是时间型保护，不可靠（主页面出现时若已过 3 秒就拦不住）；这次的守卫是状态型，窗口在就不撞。
- **第 2 笔 `e062657`（SecTask 三参数）**：`EffectiveEntitlements.swift` 第 49 行 `CopyFn` 改三参数：`typealias CopyFn = @convention(c) (UnsafeMutableRawPointer, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFTypeRef>?`；第 55 行调用补 nil：`... (task, key as CFString, nil)`。亲核：49 行 typealias 与 55 行调用确实都只有 2 个；7 个探针键（platform-application、com.apple.private.security.no-sandbox、com.apple.frontboard.launchapplications、com.apple.mediaremote.now-playing-read-access、com.apple.mediaremote.full-now-playing-read-access、com.apple.backboard.client、get-task-allow）在 `TrollLyricsDesk.entitlements` 里全都有、都是 true。
- **版本**：1.0.6 不变，build 20→21（两 Info.plist 的 CFBundleVersion＋pbxproj CURRENT_PROJECT_VERSION 4 处；MARKETING_VERSION 仍 1.0.6；build.yml 不动）。其余全部不动：不修 #2（isPlaying 探针），不加新功能，不动 entitlements、包名、MinOS 15.0。
- **diff 规模**：第 1 笔 7 个文件（+99/-13）；第 2 笔 2 个文件（+23/-3）。提交前逐行核对过，只在修法范围内。
- **作废的中间头**：`3c39be6` 推后曾建头 run 45875510487（只有 #1、缺 SecTask 修），皇上定两个都修后作废，不用它的包；最终头 run 以 `e062657` 为准。

### 构建（头 run 45876153085，head e062657）

- **completed／success，11 步全 success**（job 140078068668 同款流程：Set up job／Checkout／Xcode version／Install zsign／Archive (unsigned)／Verify archive layout／Sign with zsign (TrollStore)／Package IPA／Upload artifact／Post Checkout／Complete job）。轮询读 `status_field`／`conclusion`。
- 池子取消 ×4（每次都是 job "Build" 结论 cancelled＋steps 为 0，rerun-failed-jobs → 201 默默重跑，不报）；12 轮超時 ×4（分段接力監視，共 9 輪）；第 9 輪 poll 4 終於 in_progress，poll 6 success。晚间池子拥堵比 1.0.6 build 20 那次更严重（build 20 只取消 2 次）。
- 旧头 run 45875510487（head 3c39be6）一直 queued，未出结果就已作废，不跟。

### 验包（编成后下载真 IPA 亲验，不要只信 run 绿）

- **验包 PASS（71 项，`hidden_files/verify_1.0.6.py`，详见 `hidden_files/ipa_verify_1.0.6_build21.log`）**——68 项原有＋3 项 build 21 新增（新守卫字串「场景正在连接中，跳过这次恢复」「跳过销毁旧场景会话」「floatingSceneEverConnected」在二进制里在位）。
- IPA：`~/workspace/your_files/桌面歌詞-1.0.6-build21-newbase.ipa`（另存，**build 20 的 `桌面歌词-1.0.6-newbase.ipa` 未动**；注意 build 21 文件名用的是繁體「歌詞」，build 20 那个是简体「歌词」），**1,675,821 B，SHA256 `8fe421aaa8ee725da3ac55a9e77c081c0818f306f08187ce637af9203d8cd63a`**（artifact id 15149441254，名 桌面歌词-1.0.6，1,673,958 B；解出与拷本 SHA 一致）。
- 版本 1.0.6／build 21、包名 com.ycwl.Lyrics、MinOS 15.0；widget 1.0.6／build 21、com.ycwl.Lyrics.TrollLyricsWidget、MinOS 15.0。
- 锁屏不在位（NSSupportsLiveActivities／accessoryRectangular／LyricsLiveActivity／LiveLyricKey／publishLiveLyrics 全 0）；无 38473／DualProcessBridge／dynamic_lookup；ActivityKit 两二进制均 NOT LINKED；直链 FrontBoard／FrontBoardServices／RunningBoardServices／AppleAccount 在位；码值扫描 0 命中；BackBoard 仅 1 处对照表标签。
- **entitlements 与 1.0.5 一致（零新增，二进制级核对）**：app 二进制签名槽里的 entitlements（3,308 B）与 build 20 一字不差，widget（464 B，仅 application-groups）也一字不差；自检 §9 另查 entitlements 文件与 4f43991 一字未动。
- 同步修正、激活、五件、三档、三渲染器、PiP 实验标记、诊断串（1.0.6 前缀）、Engine Fix 串全在位；第 6 项新结论「托管结构检查通过；实际屏幕可见性未确认」在位，「已确认可见」0 命中；第 4 项 P0 行「P0——放着歌还读不到」在位，isPlaying 探针符号在位；第 9 项 PiP 两段键在位；第 1 项 native-candidate 在位。

### 自检

- `python3 check_1.0.6.py`：**261 PASS，0 FAIL，29 OPEN**（build 20 是 250 PASS／28 OPEN；§16 加 11 项——#1 守卫 9 项＋SecTask 2 项，全过；OPEN 加 1 条 build 21 真机验）。

### 待真机验证（LC 机 iPhone 13 Pro／iOS 27.0.1 为主线）

1. **进主页面不再闪退（第一项）**：主页面出现那一刻 DidBecomeActive／2 秒看门狗在连接窗口里跳过恢复，rebuild 不销毁未连上的会话；日志里若出现「场景正在连接中，跳过这次恢复」，说明守卫踩到了。
2. 悬浮窗／激活／逐歌偏移照常；解锁重建仍只建一个窗（连上过、后来断开的旧场景照旧销毁）。
3. PiP 两段、P0 仍按 build 20 的清单验（§七 A）。
4. **如果 build 21 试了还闪，下一处就查 #2（isPlaying 探针）**——那是下一步，不在这次范围里（皇上 02:22 已记下这条）。
5. 巨魔机 iPhone 11／TrollStore 回归照 §七 B（巨魔原生模式、无复核行、检测引擎计数恒为 1、悬浮窗／激活／逐歌偏移照常）。

### 提交链（build 21）

- 第 1 笔 `3c39be6`：#1 重建竞态（7 个文件，+99/-13）——锚点＋rebuild 守卫＋触发侧守卫＋版本 1.0.6/21＋自检 §16（9 项）。
- 第 2 笔 `e062657`：SecTask 三参数（2 个文件，+23/-3）——CopyFn 三参数＋调用补 nil＋自检 §16（2 项）。
- 第 3 笔（本节）：RUN 补 build 21 一节。
- 头 run：45876153085（head e062657）completed／success；IPA `桌面歌詞-1.0.6-build21-newbase.ipa`，1,675,821 B，SHA256 `8fe421aa…`，验包 71 项全过。
- 分支：v1.0.6-lc（绝不从沙盒 git push；每笔先 check 再 gh_push.py 推；不要动 newbase／main／旧 v1.0.6 分支）。**未部署上源**（部署未批）。

## §十二 build 22（1.0.6/build 22，只禁 isPlaying 探针：决定性实验）

### 为什么只禁这一处

- **build 21 在 LC 机（硬件 iPhone 13 Pro，iOS 27.0.1）上进主页面还是立刻闪**（皇上 2026-11-27 09:16 报）；#1 守卫已逐行核过没洞、SecTask 三参数已修，两个都被真机排除。审计的时机表里剩下的最可疑就是 **#2 isPlaying 探针**——第一次轮询 → GetNowPlayingInfo 回调 info==nil → `queryIsPlayingIfNeeded()` 里 `dlsym` 到的 `MRMediaRemoteGetNowPlayingApplicationIsPlaying` 符号，其假定签名（`(dispatch_queue_t, completion(Boolean))`，completion 为 block）只按 2013–2014 年公开头文件推测，iOS 27 可能已改（SecTask 已有先例）；时机也对得上（探针在主页面出现后约 1 秒内跑，正是闪的时刻）；且它只在 info==nil 时跑，LC 机上每次启动都 info==nil（P0），iPhone 11 上从不——正好对上「只在 LC 机上、每次都闪」。
- 皇上 **2026-11-27 09:22 定：先出 build 22，禁掉探针试试**。这是决定性实验：若 build 22 不闪了，#2 就是崩点（或崩点之一）；若还闪，#2 排除，下一处查 #4 场景创建时序。

### 改了什么（一笔提交 `6741c13`，只动这一处＋版本＋自检）

- **`MusicProviders/MediaRemoteAdapter.swift`（+4 行，唯一的产品代码改动）**：`queryIsPlayingIfNeeded()` 开头、5 秒节流检查之后（`lastIsPlayingQueryAt = Date()` 之后，节流戳照常更新，日志不刷屏），记一行 `LyricLogger.log("诊断1.0.6 MediaRemote：build 22：isPlaying 探针已禁用")` 然后直接 `return`，不调 `dlsym` 到的符号。探针代码（typealias、dlsym、`unsafeBitCast`、query 调用）一字不动留着，以后能恢复；调用点（GetNowPlayingInfo 回调里 info==nil 时调）未动——函数内直接返回。
- **版本**：1.0.6 不变，build 21→22（两 Info.plist 的 CFBundleVersion＋pbxproj CURRENT_PROJECT_VERSION 4 处；MARKETING_VERSION 仍 1.0.6；build.yml 不动）。其余全部不动：不碰 #1 守卫、SecTask 三参数、native-candidate、PiP 两段、激活、逐歌偏移、entitlements、包名、MinOS 15.0。
- **diff 规模**：5 个文件（+49/-11）——产品代码 1 个文件（+4）、版本 3 个文件（各 1 行）、自检 `check_1.0.6.py`（§2／§8 版本断言改 22，新增 §17 6 项，OPEN 加 1 条 build 22 真机验）。
- **一个小插曲（已如实处理，不是绕过）**：第一次用 Python `plistlib.dump` 改 App 的 Info.plist 时，它把键按字母重排、还吞了注释，diff 一下多了 87 行——已恢复原文件，改用正则只改 CFBundleVersion 后面那一行，两处 plist 最终各只有 1 行 diff。

### 构建（头 run 45922505795，head 6741c13）

- **completed／success，11 步全 success**（job Build：Set up job／Checkout／Xcode version／Install zsign／Archive (unsigned)／Verify archive layout／Sign with zsign (TrollStore)／Package IPA／Upload artifact／Post Checkout／Complete job）。轮询读 `status_field`／`conclusion`。
- 这次很顺：**0 次池子取消**，第 1 轮 poll 已 in_progress，第 3 轮 success（约 2 分钟）；build 21 那次取消了 4 次、接力了 9 轮。晚间池子这次没堵。

### 验包（编成后下载真 IPA 亲验，不要只信 run 绿）

- **验包 PASS（73 项，`hidden_files/verify_1.0.6.py`，详见 `hidden_files/ipa_verify_1.0.6_build22.log`）**——71 项原有＋2 项 build 22 新增（禁用标记字串「build 22：isPlaying 探针已禁用」在二进制里在位；readStatus 的「P0：放着歌还读不到」全角冒号版在位）。
- IPA：`~/workspace/your_files/桌面歌詞-1.0.6-build22-newbase.ipa`（另存，**build 21 的 `桌面歌詞-1.0.6-build21-newbase.ipa` 未动**；文件名继续用繁體「歌詞」，与 build 21 同写法），**1,674,367 B，SHA256 `e7de009ebe17f8e0fbf833527bcd3bd766d9fbb9c50fa89e3da36d1720c88eea`**（artifact id 15165735680，名 桌面歌词-1.0.6，1,672,406 B；解出与拷本 SHA 一致）。
- 版本 1.0.6／build 22、包名 com.ycwl.Lyrics、MinOS 15.0；widget 1.0.6／build 22、com.ycwl.Lyrics.TrollLyricsWidget、MinOS 15.0。
- 锁屏不在位（NSSupportsLiveActivities／accessoryRectangular／LyricsLiveActivity／LiveLyricKey／publishLiveLyrics 全 0）；无 38473／DualProcessBridge／dynamic_lookup；ActivityKit 两二进制均 NOT LINKED；直链 FrontBoard／FrontBoardServices／RunningBoardServices／AppleAccount 在位；码值扫描 0 命中；BackBoard 仅 1 处对照表标签。
- **entitlements 与 build 21 一致（零新增，二进制级核对）**：从两二进制的 code signature 槽（slot 5）抽出 entitlements blob 逐字节比对——app（3,308 B）与 build 21 一字不差，widget（464 B，仅 application-groups）也一字不差；自检 §9 另查 entitlements 文件与 4f43991 一字未动。
- 同步修正、激活、五件、三档、三渲染器、PiP 实验标记、诊断串（1.0.6 前缀）、Engine Fix 串全在位；第 6 项新结论「托管结构检查通过；实际屏幕可见性未确认」在位，「已确认可见」0 命中；第 1 项 native-candidate 在位；第 9 项 PiP 两段键在位；#1 守卫字串「floatingSceneEverConnected」在位。
- **验包里唯一一次 FAIL 及处理（已查明机制，不是放水）**：第一遍验包 71 PASS／1 FAIL——「在位：P0——放着歌还读不到」（破折号版）不在二进制里。逐字节核对确认：build 21 二进制里它在位，build 22 里不在位；同时 `recordIsPlaying`／`MRMediaRemoteGetNowPlayingApplicationIsPlaying` 字串在 build 22 里也不在位，而 readStatus 的「P0：放着歌还读不到」（全角冒号版）和「疑似 P0」仍在位。机制：early return 让 `recordIsPlaying` 的三个调用点全不可达，Whole-Module 优化把这个函数连同它那行唯一日志串、以及只被死代码引用的符号名字串一起裁掉了——这是禁掉探针的直接后果，源码里那行仍在（`MediaRemoteDiagnostics.swift:130`，自检 §15 断言），readStatus 的 P0 状态路径（DiagnosticsView 还在调）也没断。处理：验包脚本把破折号版 P0 串从「在位」移到「不在位（build 22 预期）」并写明机制，另加全角冒号版 P0 串为在位对照；重跑 **73 项全过**。产品代码一字未动，改的只是验包脚本的期望（`hidden_files/verify_1.0.6.py`，不进仓库）。

### 自检

- `python3 check_1.0.6.py`：**267 PASS，0 FAIL，30 OPEN**（build 21 是 261 PASS／29 OPEN；§17 加 6 项——禁用标记在位、节流后 return、return 在 bridge.symbol／dlsym 之前、探针代码仍在但不可达、调用点未动、其余不动，全过；OPEN 加 1 条 build 22 真机验）。

### 待真机验证（LC 机 iPhone 13 Pro／iOS 27.0.1 为主线）

1. **进主页面还闪不闪（第一项，决定性实验的判据）**：若不闪了，#2 就是崩点（或崩点之一）——探针以后可以删掉或改签名重做；若还闪，#2 排除，下一处查 **#4 场景创建时序**。日志里应有「build 22：isPlaying 探针已禁用」行（5 秒节流，首次进主页面时记一次）。
2. 其余照 build 20 清单 §七验：悬浮窗／激活／逐歌偏移照常；解锁重建仍只建一个窗；PiP 两段、P0 仍按 build 20 的清单验（§七 A）——注意：build 22 里 P0 的「放着歌还读不到」状态行不会再出现（探针已禁，`isPlaying` 永远未知），诊断页的 MediaRemote 状态应是「疑似 P0」而不是 P0，这是禁探针后的预期变化，不是新故障。
3. 巨魔机 iPhone 11／TrollStore 回归照 §七 B（巨魔原生模式、无复核行、检测引擎计数恒为 1、悬浮窗／激活／逐歌偏移照常）。

### 提交链（build 22）

- 第 1 笔 `6741c13`：只禁 isPlaying 探针＋版本 1.0.6/22＋自检 §17（5 个文件，+49/-11）。
- 第 2 笔（本节）：RUN 补 build 22 一节（只改文档，触发的 run 不用跟）。
- 头 run：45922505795（head 6741c13）completed／success；IPA `桌面歌詞-1.0.6-build22-newbase.ipa`，1,674,367 B，SHA256 `e7de009e…`，验包 73 项全过。
- 分支：v1.0.6-lc（绝不从沙盒 git push；每笔先 check 再 gh_push.py 推；不要动 newbase／main／旧 v1.0.6 分支）。**未部署上源**（部署未批）。

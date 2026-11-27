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

## §十三 build 23（1.0.6/build 23，只改回调回 @escaping：病根修复实验）

### 为什么只改这一处

- **build 22 在 LC 机（硬件 iPhone 13 Pro，iOS 27.0.1）上进主页面还是立刻闪**（皇上 2026-11-27 09:33 报）；#2 isPlaying 探针已禁仍闪，排除。第三次审计 2026-11-27 09:58 把病根钉到指令级：**1.0.6 把 `MRMediaRemoteGetNowPlayingInfo` 回调从 @escaping 改成 `@convention(block)`，编译器在调用点后插入 `swift_isEscapingClosureAtFileLocation` 逃逸检查，MediaRemote（异步 XPC）调用返回后仍持有 block，检查为真 → brk #1（build 22 二进制 0x44A5C，主线程，启动后 0.698s）**。1.0.5 的 @escaping 才是对的。`assumeIsolated` 已排除（它的 trap 在 0xDBF4，另一处 brk；调用栈里没有 ObjC 帧）；#4 场景创建时序、#3 队列改动也已排除。
- 皇上 **2026-11-27 09:59 定：做 build 23，改回 @escaping 试试**。这是病根修复实验：若 build 23 不闪了，逃逸检查就是崩点；若还闪，#2／回调签名都排除，下一处查 **#4 场景创建时序**。

### 改了什么（两笔提交，只动这一处＋版本＋自检）

- **第 1 笔 `ad6eb22`**：`MusicProviders/MediaRemoteAdapter.swift`（产品代码只动 1 行）：`MRMediaRemoteGetNowPlayingInfoFn` 的回调参数 `@convention(block) (CFDictionary?) -> Void` 改 `@escaping (CFDictionary?) -> Void`。第 36 行 isPlaying 探针的 `@convention(block) (UInt8) -> Void` **绝对未动**，探针保持禁用；不用 `withoutActuallyEscaping` 包起来，也不删回调。
- **版本**：1.0.6 不变，build 22→23（两 Info.plist 的 CFBundleVersion＋pbxproj CURRENT_PROJECT_VERSION 4 处；MARKETING_VERSION 仍 1.0.6；build.yml 不动）。其余全部不动：不碰 #1 守卫、SecTask 三参数、native-candidate、PiP 两段、激活、逐歌偏移、entitlements、包名、MinOS 15.0。
- **diff 规模（第 1 笔）**：5 个文件（+54/-15）——产品代码 1 个文件（1 行）、版本 3 个文件（各 1 行改 22→23）、自检 `check_1.0.6.py`（§2／§8 版本断言改 23，新增 §18 7 项，OPEN 加 1 条 build 23 真机验；旧「回调改 block」断言翻转为 @escaping 断言——旧断言的假定已被第三次审计推翻，注释里写明了机制）。
- **第 2 笔 `4e408f3`（编译强制的一词补丁，行为不变）**：第 1 笔的头 run 编译失败（见下），唯一错误是 `MediaRemoteAdapter.swift:210:5: error: implicit use of 'self' in closure`——@escaping 让回调闭包变成 escaping，Swift 要求显式 `self.`，原来 @convention(block) 时隐式 self 能过。只把第 210 行 `queryIsPlayingIfNeeded()` 改 `self.queryIsPlayingIfNeeded()`（＋1 行注释）；闭包已 `[weak self]`，内层 Task 已 `guard let self`，行为与原来隐式 self 相同。自检 §18 因此多 1 项（显式 self 断言）。diff：2 个文件（+4/-1）。

### 构建（两轮头 run；第一轮真失败，第二轮成功）

- **第一轮头 run 45925893663（head ad6eb22）：completed／failure**——job Build 11 步，Archive (unsigned) 失败，其余 9 步 success、Verify／Sign／Package／Upload skipped。**不是池子取消**（job 跑了 11 步，不是 cancelled＋0 步），不重跑。job 日志（`hidden_files/job-45925893663.log`，220,139 B）唯一错误就是上面那行 implicit self；其余编译全过。这是 @escaping 改动的直接后果，不是机器失败。
- **第二轮头 run 45926144366（head 4e408f3）：completed／success，11 步全 success**（Set up job／Checkout／Xcode version／Install zsign／Archive (unsigned)／Verify archive layout／Sign with zsign (TrollStore)／Package IPA／Upload artifact／Post Checkout／Complete job）。轮询读 `status_field`／`conclusion`。**0 次池子取消**，第 1 轮 poll 已 in_progress，第 3 轮 success（约 2 分钟）。

### 验包（编成后下载真 IPA 亲验，不要只信 run 绿）

- **验包 PASS（73 项，`hidden_files/verify_1.0.6.py`，详见 `hidden_files/ipa_verify_1.0.6_build23.log`）**——与 build 22 同数（71 项原有＋2 项 build 22 新增：禁用标记字串「build 22：isPlaying 探针已禁用」仍在位；readStatus 的「P0：放着歌还读不到」全角冒号版在位）。验包脚本本地改到 build 23（只改版本断言 22→23；探针标记串保留，因为探针仍禁着；不进仓库）。
- IPA：`~/workspace/your_files/桌面歌詞-1.0.6-build23-newbase.ipa`（另存，**build 22 的 `桌面歌詞-1.0.6-build22-newbase.ipa` 未动**；文件名继续用繁體「歌詞」，与 build 22 同写法），**1,674,848 B，SHA256 `47e4de0c37627288f37de349b77358f705f1089250a3b5ca7c9a0b7f9e90ce80`**（artifact id 15165894845，名 桌面歌词-1.0.6，1,672,993 B；解出与拷本 SHA 一致）。
- 版本 1.0.6／build 23、包名 com.ycwl.Lyrics、MinOS 15.0；widget 1.0.6／build 23、com.ycwl.Lyrics.TrollLyricsWidget、MinOS 15.0。
- 锁屏不在位（NSSupportsLiveActivities／accessoryRectangular／LyricsLiveActivity／LiveLyricKey／publishLiveLyrics 全 0）；无 38473／DualProcessBridge／dynamic_lookup；ActivityKit 两二进制均 NOT LINKED；直链 FrontBoard／FrontBoardServices／RunningBoardServices／AppleAccount 在位；码值扫描 0 命中；BackBoard 仅 1 处对照表标签。
- **entitlements 与 build 22 一字不差（二进制级核对）**：从两二进制的 code signature 槽（slot 5）抽出 entitlements blob 逐字节比对——app（3,308 B）与 build 22 一字不差，widget（464 B）也一字不差。
- 同步修正、激活、五件、三档、三渲染器、PiP 实验标记、诊断串（1.0.6 前缀）、Engine Fix 串全在位；第 6 项新结论「托管结构检查通过；实际屏幕可见性未确认」在位，「已确认可见」0 命中；第 1 项 native-candidate 在位；第 9 项 PiP 两段键在位；#1 守卫字串「floatingSceneEverConnected」在位。

### 关键断言：逃逸检查点计数（亲手数的，不是只信审计数字）

- **方法**（`hidden_files/escape_check_count.py`，capstone 5.0.7 反汇编；计数逻辑：解析 LC_SYMTAB＋LC_DYSYMTAB 间接符号表找 `_swift_isEscapingClosureAtFileLocation` 的 `__stubs` 入口，再在 `__text` 里数所有 `bl` 到该 stub 的调用点；函数归属按 LC_FUNCTION_STARTS 的 ULEB128 增量相对 `__TEXT` 段 vmaddr 算）：
- **先在 build 22 二进制上验证方法**：数出 **3 个点**，第 3 个正在 **0x44A5C**——与第三次审计的数字一字不差（详见 `hidden_files/escape_check_build22.log`）。另两个点在 0xDAE4／0xDB1C，同属函数 0xDA40。
- **build 23 二进制：2 个点**（详见 `hidden_files/escape_check_build23.log`）——0xDAE4／0xDB1C，仍在函数 0xDA40，地址与 build 22 完全相同；**MediaRemote 那个点消失了，总数回到 1.0.5 的 2 个**。
- **再单独核 MediaRemote 调用点所在的函数**：build 22 里含 0x44A5C 检查点的函数起于 **0x444FC**（有真实函数序言 `stp d9, d8, [sp, #-0x70]!`；下一函数起于 0x44ABC）；build 23 里**同一函数仍在同一地址 0x444FC、同一序言**，函数体内 `bl` 到逃逸检查 stub 的次数为 **0**（build 22 里是 1 次，正好是 0x44A5C）。附记：审计写的函数起址 0x42F60 与 LC_FUNCTION_STARTS 不符——0x42F60 处无函数序言，是另一函数中部；站点地址 0x44A5C 本身与审计完全一致，结论不受影响。

### 自检

- `python3 check_1.0.6.py`：**275 PASS，0 FAIL，31 OPEN**（build 22 是 267 PASS／30 OPEN；§18 加 8 项——@escaping 在 typealias 里在位、@escaping 就在该 typealias 里、block 版 CFDictionary 回调不在、isPlaying typealias 未动、无 withoutActuallyEscaping／回调未删、显式 self.、探针仍禁用、其余不动，全过；旧「回调改 block」断言翻转后也过；OPEN 加 1 条 build 23 真机验）。

### 待真机验证（LC 机 iPhone 13 Pro／iOS 27.0.1 为主线）

1. **进主页面还闪不闪（第一项，病根修复实验的判据）**：若不闪了，逃逸检查就是崩点；若还闪，#2／回调签名都排除，下一处查 **#4 场景创建时序**。日志里仍应有「build 22：isPlaying 探针已禁用」行（探针仍禁着）。
2. **P0 仍是 info=nil 待查，不受这次改动影响**：QQ 音乐在播、回调 info 仍 nil 的问题（诊断页「疑似 P0」）与回调签名无关，这次改动只修闪退，不修跟随读不到；P0 仍按 build 20 的清单验（§七 A）。
3. 其余照 build 20 清单 §七验：悬浮窗／激活／逐歌偏移照常；解锁重建仍只建一个窗；PiP 两段照常；巨魔机 iPhone 11／TrollStore 回归照 §七 B。

### 提交链（build 23）

- 第 1 笔 `ad6eb22`：回调改回 @escaping＋版本 1.0.6/23＋自检 §18（5 个文件，+54/-15）。头 run 45925893663 失败（implicit self，见上）。
- 第 2 笔 `4e408f3`：补显式 self. 一词＋自检 1 项（2 个文件，+4/-1）。头 run 45926144366 成功。
- 第 3 笔（本节）：RUN 补 build 23 一节（只改文档，触发的 run 不用跟）。
- 头 run：45926144366（head 4e408f3）completed／success；IPA `桌面歌詞-1.0.6-build23-newbase.ipa`，1,674,848 B，SHA256 `47e4de0c…`，验包 73 项全过；逃逸检查点 3→2，MediaRemote 函数里 1→0。
- 分支：v1.0.6-lc（绝不从沙盒 git push；每笔先 check 再 gh_push.py 推；不要动 newbase／main／旧 v1.0.6 分支）。**未部署上源**（部署未批）。**未发给皇上**（等上级转）。

## §十四 build 24（1.0.6/build 24，巨魔主线五件修）

### 为什么只做这五件

- 皇上 **2026-11-27 10:20 定：LC 宿主研究暂停，巨魔版（iPhone 11／iOS 16.5／Dopamine rootless，TrollStore）是正式开发主线**；皇上自己在 iPhone 11 上验 build 23，同时把下面五件修进 build 24。
- 皇上 **2026-11-27 10:22 定「不上源」：TrollLyricsDesk 不部署到越狱源**——现在就定了，不用等验收；真机验收照常继续。本节关于部署的写法按已定版写，不再写「等验收通过再定上源」。
- **未部署上源**（已定不上源）。**未发给皇上**（等上级转）。

### 改了什么（一笔提交 `0cef79c`，只做五件＋版本＋自检）

1. **环境识别修复（build 23 的漏判）**：build 23 在 LC 3.8.12 客人里 `isLiveContainer=false`，认成「普通签名（沙盒内）」走 compat，悬浮窗没建——newbase 重写时丢了旧统一版的信号。`Lyrics/LyricStore.swift` 的 `isLiveContainer` 补回两路旧信号（只读参考旧线分支 v1.0.6／工作区 `~/workspace/trolllyricsdesk`，commit 893f066，**旧分支与旧工作区一字未碰**；没有研究 LiveContainer 宿主源码）：
   - **信号一（排第一）**：环境变量 `LC_HOME_PATH`——宿主起客人 App 前 setenv，hideLiveContainer 不动环境变量，最可靠；
   - **信号二**：包路径含 `/Documents/Applications/`（客人包体在宿主 Documents/Applications/ 下；巨魔包在 `/var/containers/Bundle/Application/` 下，不会误中）。
   - 保留现有信号：Info.plist 键 TLDSLiveContainer、路径含 livecontainer 或 /lcapps/、类 LCAppDelegate。`liveContainerSignalDetail` 同步写清新信号的命中情况，「均无」行也改了。
   - `App/TrollLyricsDeskApp.swift` 新 `logEnvironmentDetection()`（`detectInstallEnvironment()` 里调，启动时记一次）：进程名、Home 目录、bundle 路径、argv[0]、LC_HOME_PATH 值、各信号结果——下次日志能看清为什么这样判。只读证据，不改判定。
   - **TrollStore 检测不动**：SecTask 正面证据（platform-application＋no-sandbox／沙盒外写探测）一字未动，`RuntimeEnvironment.detectInstallEnvironment()` 里 LC 判断仍在 TrollStore 证据之前。
2. **诊断日志版本标记**：`Lyrics/LyricStore.swift` 新统一常量 `versionTag = "build 24（1.0.6）"`——日志里的 build 号只从这里取，升版改这一处＋两处 plist＋pbxproj。`MusicProviders/MediaRemoteAdapter.swift` 的探针日志改走插值（`"诊断1.0.6 MediaRemote：\(LyricStore.versionTag)：isPlaying 探针已禁用"`），不再写死 "build 22"（build 23 的日志写 build 22 就是写死字串的教训；`:210` 的显式 `self.` 一字未动）。`Overlay/TLDSAppDelegate.m:784` 运行时字串里的 "build 21" 也去掉（改「竞态修」，历史仍在 :768 的注释里）。全树核查：其余 "build NN" 只剩注释里的历史引用，运行时字串里没有。
   - **versionTag 故意写成长串（19 字节 UTF-8）**：≤15 字节的字串在 Release 下会被编译器压成 small-string immediate 进代码段，字节扫描不到；长字串进 `__cstring`，验包能直接搜到 "build 24"（见验包节，确实搜到了）。
   - 启动时新增版本对账行（`detectInstallEnvironment()` 里）：versionTag 与 CFBundleVersion／CFBundleShortVersionString 并排记进日志；以后升版漏改任何一处，日志里当场看得见。
3. **dSYM**：`.github/workflows/build.yml` 加两步——`Package dSYM`（`ls` 先验 `xcarchive/dSYMs/` 在不在，没有就响亮地失败，不悄悄传空包；zip 打包）＋`Upload dSYM artifact`（产物名 `桌面歌词-1.0.6-dSYM`，与 IPA 同一个 run）。IPA 产物不变。Release 的 `DEBUG_INFORMATION_FORMAT` 本来就是 `dwarf-with-dsym`，archive 里自带 App 与 Widget 的 dSYM。
4. **完整诊断日志保留**：`Diagnostics/OverlayDiagnostics.swift` 的 `logSummary()` 在 1.0.6 里**全树无调用者**——1.0.5 的教训重演（无调用者就被整模块优化裁掉，字串不在包里）。修法：`TrollLyricsDeskApp.swift` 的 `setRunMode()` 末尾调一次——它是每条定档路径都调的入口（巨魔／待探测／兼容／原生候选／复核结论），复核结论路径里它在 `setDisplayCapability` 之后，读到的 runMode 是刚写的新值；摘要行每次定档都进日志，二进制里也留得住。其余诊断入口核过都有调用者：`RuntimeCapabilities.logSnapshot()`（DiagnosticsView 刷新时）、`EffectiveEntitlements.logReport()`（启动判定）、`EntitlementDiagnostics.logReport()`（DiagnosticsView 刷新时）。
5. **权限不足安全降级（只审计，不改代码）**：审计了全部四条权限依赖路径——SecTask 实测（`EffectiveEntitlements`：符号缺失回 nil、Create/Copy 规则的 retain/release 都对，三参数已修）、MediaRemote 调用（`MediaRemoteAdapter`：dlsym 找不到就回 nil、回调 `[weak self]`＋Task 内 guard、探针 early return 后代码不可达）、悬浮窗创建（`TLDSAppDelegate.m`：FBSystemShellInitialize 包 @try/@catch、binder 操作先 `respondsToSelector`、销毁有 #1 锚点守卫）、PiP 启动（`PiPLyricsRenderer`：`pipSupported` 先判、控制器 optional 全守卫、队列操作 `first` 有 guard）。陷阱点逐项核过：**全树 Swift 无 `as!`／`fatalError`；`try!` 只剩 `LyricParser.swift` 两行静态正则（字面量 pattern，不可能失败）；数组下标都有守卫**（`components[0..2]` 前有 `count >= 3`、`channel[0]` 是单声道缓冲）；`MainActor.assumeIsolated` 的两个调用方（`start()`←didFinishLaunching、`makeRootViewController()`←willConnect）都在主线程 ObjC 生命周期里，build 23 真机已证实不闪。**结论：无确有真实 trap 风险处，不改代码，不推测性重写。**
   - **build 23 的 @escaping 修法不动**：GetNowPlayingInfo 回调仍是 `@escaping`，isPlaying 探针仍是 `@convention(block)`，没有 `withoutActuallyEscaping`，回调没删。
- **版本**：1.0.6 不变，build 23→24（两 Info.plist 的 CFBundleVersion＋pbxproj CURRENT_PROJECT_VERSION 4 处；MARKETING_VERSION 仍 1.0.6）。其余全部不动：不碰 #1 守卫、SecTask 三参数、native-candidate、PiP 两段、激活、逐歌偏移、entitlements、包名、MinOS 15.0。
- **diff 规模**：9 个文件（+213/-25）——产品代码 5 个文件（LyricStore +35/-9、TrollLyricsDeskApp +23/-1、MediaRemoteAdapter +4/-1、TLDSAppDelegate.m 1 行、build.yml +21）、版本 3 个文件（各 1 行）、自检 `check_1.0.6.py`（§2／§8 版本断言改 24，§17／§18 探针标记断言改动态式，新增 §19 19 项，OPEN 加 4 条）。
- **自检里修掉的 2 处都是自检脚本断言写错、代码本身没错（已修正后重跑全过）**：①我加的注释里带了 `"build 22` 引号，撞上「写死字串不在源码里」的断言——注释改掉引号；②LC 信号顺序断言用 `index("TLDSLiveContainer")` 撞上文档注释里的先出现——改按代码行（`if ProcessInfo...`／`if Bundle.main.object...`／`lower.contains...`）比顺序。

### 构建（头 run 45928829264，head 0cef79c）

- **completed／success，13 步全 success**（Set up job／Checkout／Xcode version／Install zsign／Archive (unsigned)／Verify archive layout／Sign with zsign (TrollStore)／Package IPA／**Package dSYM**／Upload artifact／**Upload dSYM artifact**／Post Checkout／Complete job）。轮询读 `status_field`／`conclusion`。
- **0 次池子取消**，第 1 轮 poll 已 in_progress，第 3 轮 success（约 2 分钟）。

### 验包（编成后下载真 IPA＋dSYM 亲验，不要只信 run 绿）

- **验包 PASS（82 项，`hidden_files/verify_1.0.6.py`，详见 `hidden_files/ipa_verify_1.0.6_build24.log`）**——build 23 是 73 项；新增 9 项：`build 24`／`isPlaying 探针已禁用`／`LC_HOME_PATH`／`/Documents/Applications/`／`诊断1.0.6 环境检测`／`诊断1.0.6 版本：`／`悬浮窗复核摘要` 在位，`build 22`／`build 21`／`build 23` 不在位。
- IPA：`~/workspace/your_files/桌面歌詞-1.0.6-build24-newbase.ipa`（另存，**build 23 的 `桌面歌詞-1.0.6-build23-newbase.ipa` 未动**；文件名继续用繁體「歌詞」），**1,677,719 B，SHA256 `4b27a04388b16a462e19eb50e5f058a2a77b004c973929cfa10afca55d51a933`**（artifact id 15166819692，名 桌面歌词-1.0.6，zip 1,675,808 B；解出与拷本 SHA 一致）。
- dSYM：artifact id 15167880473，名 `桌面歌词-1.0.6-dSYM`，zip **2,154,058 B**，存档 `hidden_files/artifact-1.0.6-build24/桌面歌词-1.0.6-dSYM.zip`。内含 `TrollLyricsDesk.app.dSYM` 与 `TrollLyricsWidget.appex.dSYM`。
- **dSYM UUID 与 IPA 二进制的 Mach-O UUID 一致（两对都对得上，详见 `hidden_files/dsym_uuid_build24.log`）**：App `7230dc56f2d3366cbef0eeb09bbc2b99`、Widget `bc1cc20b5a673049a24d6837449392b8`——dSYM 里 DWARF 文件的 LC_UUID 与 IPA 二进制的 LC_UUID 逐字节相同，**zsign 重签没有改 LC_UUID**。方法：Python 直读 Mach-O（LC_UUID cmd 0x1b、LC_CODE_SIGNATURE cmd 0x1d；超块魔数是 0xfade0cc0，索引项是 8 字节 type＋offset，slot 5 是 XML entitlements——第一版核对脚本把魔数写成 0xfade7171、索引写成 12 字节，两处都错过，已修正，数字以修正后的为准）。
- 版本 1.0.6／build 24、包名 com.ycwl.Lyrics、MinOS 15.0；widget 1.0.6／build 24、com.ycwl.Lyrics.TrollLyricsWidget、MinOS 15.0。
- 锁屏不在位（NSSupportsLiveActivities／accessoryRectangular／LyricsLiveActivity／LiveLyricKey／publishLiveLyrics 全 0）；无 38473／DualProcessBridge／dynamic_lookup；ActivityKit 两二进制均 NOT LINKED；直链 FrontBoard／FrontBoardServices／RunningBoardServices／AppleAccount 在位；码值扫描 0 命中；BackBoard 仅 1 处对照表标签。
- **entitlements 与 build 23 一字不差（二进制级核对）**：从两二进制的 code signature 槽（slot 5）抽出 XML entitlements blob 逐字节比对——app（SHA 前 16 位 `b6a9f77ea2237d00`）与 build 23 一字不差，widget（SHA 前 16 位 `63c0e2c366ea9d85`）也一字不差；自检 §9 另查 entitlements 文件与 4f43991 一字未动。
- 同步修正、激活、五件、三档、三渲染器、PiP 实验标记、诊断串（1.0.6 前缀）、Engine Fix 串全在位；第 6 项新结论「托管结构检查通过；实际屏幕可见性未确认」在位，「已确认可见」0 命中；第 1 项 native-candidate 在位；第 9 项 PiP 两段键在位；#1 守卫字串「floatingSceneEverConnected」在位。
- **逃逸检查点仍是 2 个（详见 `hidden_files/escape_check_build24.log`）**：`hidden_files/escape_check_count.py` 数出 2 个点——0xDAE4／0xDB1C，同属函数 0xDA40，与 build 23 的地址完全相同；**MediaRemote 函数里的 0x44A5C 没有回来**，总数仍是 1.0.5 的 2 个。

### 自检

- `python3 check_1.0.6.py`：**294 PASS，0 FAIL，35 OPEN**（build 23 是 275 PASS／31 OPEN；§19 加 19 项——versionTag 统一常量（值＋19 字节长串）、探针日志走插值、:784 的 build 21 已去、LC_HOME_PATH 排第一、/Documents/Applications/ 信号、信号明细、环境检测日志（调用点＋五项值）、版本对账行、TrollStore 检测不动、logSummary 调用点＋摘要字串、dSYM 两步＋IPA 产物不变、@escaping 不动、审计结论（无 as!／fatalError，try! 只剩 2 行）、其余不动，全过；OPEN 加 4 条——巨魔五项、LC 复核、dSYM 核对、不上源已定）。

### 待真机验证

#### A. 主线：巨魔机 iPhone 11／iOS 16.5／Dopamine rootless／TrollStore（皇上 10:20 定正式开发主线）

1. **MediaRemote 实际权限**：诊断页／日志里 SecTask 实测 platform-application／no-sandbox 是不是 YES（巨魔机上应是 YES，与 LC 机的「读不到」对照）。
2. **三大音乐平台读歌**：QQ 音乐／酷我／网易云各放一首，看歌名读不读得到、回调 info 有没有内容。
3. **歌词同步**：逐歌偏移、LRCLIB 跟随、换歌不串词。
4. **跨 App 悬浮窗**：退到桌面／别的 App 上方有没有歌词窗；日志应是「巨魔原生模式」，无复核行。
5. **后台稳定性**：后台保活、回前台不丢窗、不闪退；检测引擎计数恒为 1。
6. 其余照 build 20 清单 §七 B：悬浮窗／激活／逐歌偏移照常；PiP 两段照常。

#### B. LC 机复核：iPhone 13 Pro／iOS 27.0.1／LiveContainer 3.8.12（环境识别修完后的复核）

1. **安装环境应判 livecontainer**（LC_HOME_PATH 信号命中），不再是「普通签名（沙盒内）」；悬浮窗复核照常跑。
2. 日志里应有「诊断1.0.6 环境检测」两行（进程名／Home 目录／bundle 路径／argv[0]／LC_HOME_PATH 值／各信号结果）＋「诊断1.0.6 版本」对账行（versionTag 与 CFBundleVersion 并排）。
3. 探针日志应写 **build 24**，不再是 build 22；每次定档后应有「诊断1.0.6 悬浮窗复核摘要」行。
4. P0 仍是 info=nil 待查，不受这次改动影响（与 build 23 同）。

### 提交链（build 24）

- 第 1 笔 `0cef79c`：五件修＋版本 1.0.6/24＋自检 §19（9 个文件，+213/-25）。
- 第 2 笔（本节）：RUN 补 build 24 一节（只改文档，触发的 run 不用跟）。
- 头 run：45928829264（head 0cef79c）completed／success，13 步全 success，0 次池子取消；IPA `桌面歌詞-1.0.6-build24-newbase.ipa`，1,677,719 B，SHA256 `4b27a043…`，验包 82 项全过；dSYM 产物在且 UUID 两对都对得上；逃逸检查点 2 个。
- 分支：v1.0.6-lc（绝不从沙盒 git push；每笔先 check 再 gh_push.py 推；不要动 newbase／main／旧 v1.0.6 分支）。**不上源已定（皇上 2026-11-27 10:22），不部署到越狱源；真机验收继续。未发给皇上**（等上级转）。

## §十五 build 25（1.0.6/build 25，启动＋回前台重建兜底）

### 为什么只做这一件

- 皇上 **2026-11-27 14:30 点选「做 build 25：启动＋回前台重建兜底」**（三选一：只做兜底／兜底＋保活加固／先不修）。
- 真机证据（iPhone 11／TrollStore，build 24，皇上 2026-11-27 实测）：
  - 10:53 锁屏那次重建跑通：旧窗藏起来，新窗 TLDSFloatingLyric_1 建起来报「已显示」。
  - 10:56 锁屏→解锁，主屏幕上悬浮窗没了（录像确认）。
  - 11:05 启动行：「上次会话结束于前台，未收到 WillTerminate（疑似被杀，距今 727 秒）」——进程在锁屏后在后台被系统杀了，解锁时没人重建。
  - 11:05 新启动后退到主屏幕，悬浮窗还是没有；皇上原话「只有启动APP才会来」，而且这次重启动也没回来——启动重建这条路本身靠不住，有时来有时不来。
- **病根（代码里坐实）**：首启建场景只靠异步 `FBSystemShellInitialize` 回调（`startFloatingOverlay`）；回调丢了，`floatingSceneEverCreated` 就永远是 NO；而所有恢复入口（2 秒看门狗 `tlds_watchdogReactivate`、回到前台 `tlds_reactivateFromForegroundNotification`、解锁重建 `rebuildFloatingOverlay`）都在「场景一次都没建过」时直接 return——启动创建丢一次就永远没窗，重启动只是重新掷骰子。第二缺口：场景建了但一直没连上（`willConnectToSession` 没跑）时，#1 守卫跳过恢复且无超时——卡住就无限等。
- **不上源已定**（皇上 2026-11-27 10:22），不部署到越狱源；真机验收继续。**未发给皇上**（等上级转）。

### 改了什么（一笔提交，产品代码＋版本＋自检 §20）

只改 `Overlay/TLDSAppDelegate.h`／`.m`＋版本 4 处＋自检；其余一字未动。

1. **兜底一：Shell 回调没来就直接建（根）**：`reactivateFloatingOverlayWithTrigger` 里原来「`!shellInitialized || !floatingSceneEverCreated` 就 return」那行拆开——`shellInitialized` 为 NO 仍 return（注册都没开始）；`floatingSceneEverCreated` 为 NO 时，2 秒看门狗／回到前台到这里就直接调同款 `createFloatingSceneWithIdentifier:` 建一次（与 Shell 回调同款入口，不复制新实现），记「诊断1.0.6 启动兜底：Shell 回调未到，直接建悬浮场景（触发：…，启动已过 N 秒）」，建完 return，下一次再走正常恢复流程。
2. **兜底一的护栏**：①启动 2 秒内不抢建——新 `launchTime`（didFinishLaunching 里记），`now - launchTime < 2.0` 就 return，给 Shell 回调先到的机会（看门狗本来就是 2 秒一轮，首轮正好 2 秒后）；②Shell 回调晚到时有守卫——`startFloatingOverlay` 的回调里 `floatingSceneEverCreated` 已是 YES 就记「Shell 回调到了，悬浮场景已由兜底建好，跳过（不建第二个窗）」并 return，不建第二个窗。
3. **兜底二：卡住超时 10 秒**：新 `floatingSceneCreatedTime`（`createFloatingSceneWithIdentifier` 里记）；#1 守卫的跳过只在「创建不到 10 秒」时生效，超过 10 秒还没连上就记「场景创建已超过 10 秒仍未连接（触发：…），判定卡住，走重建」，往下走 `rebuildFloatingOverlay`——rebuild 本身对未连上的场景跳过销毁（只摘 binder＋藏窗口），不会撞车。build 21 的闪退保护（连接窗口内跳过）一字未动。
4. **不动的**：解锁重建 `rebuildFloatingOverlay` 原样不动（3 秒节流、未连上跳过销毁、换新标识全在）；`startFloatingOverlayRecreate`（无调用方）不动；BackgroundKeepAlive（静音保活）不动——它本来就在巨魔模式下启动，进程还是被杀了，保活保证不了活，这次不加保活；MediaRemote 回调 `@escaping` 不动（build 23 闪退修法）；激活、逐歌偏移、Engine Fix、锁屏（继续不恢复）、entitlements（零新增）、无 TCP 桥、无新 UI、无 LC 主线改动、compatMode 跳过逻辑照旧。
- **版本**：1.0.6 不变，build 24→25（两 Info.plist 的 CFBundleVersion＋pbxproj CURRENT_PROJECT_VERSION 4 处＋`LyricStore.versionTag = "build 25（1.0.6）"`，19 字节 UTF-8，仍进 `__cstring`）。
- **diff 规模**：7 个文件（产品代码 3 个文件：TLDSAppDelegate.m +41/-7、TLDSAppDelegate.h +8、LyricStore.swift 版本 1 行＋注释；版本 3 个文件各 1 行；自检 `check_1.0.6.py` §20 新加 9 项 checks＋5 项 OPEN，§2／§8／§19 版本断言 24→25；总 +133/-26）。

### 自检

- `python3 check_1.0.6.py`：**303 PASS，0 FAIL，40 OPEN**（build 24 是 294 PASS／35 OPEN；§20 加 9 项——版本号三处一致、Shell 回调守卫、看门狗／回前台直接建场景、启动 2 秒门槛＋launchTime、卡住 10 秒超时＋floatingSceneCreatedTime、#1 守卫不动、解锁重建原样不动、保活不动、@escaping 不动，全过；OPEN 加 5 条——build 25 真机验三项＋主页面不闪退＋只建一个窗）。

### 待真机验证（巨魔机 iPhone 11／iOS 16.5／Dopamine rootless／TrollStore）

1. **① 冷启动后退到主屏幕，悬浮窗在不在**：11:05 那次重启动后退出来没有窗——修完冷启动 2 秒后看门狗兜底应已建好窗，退到主屏幕窗应在；日志里应有「启动兜底」或「系统 Shell 注册成功」＋创建行。
2. **② 锁屏→解锁，悬浮窗在不在**：10:56 那次解锁后主屏幕没窗——修完解锁重建照常跑；若进程还活着，窗应直接在；若进程被杀，解锁时没人重建，看第③项。
3. **③ 锁屏久一点（等进程被杀）→解锁→打开一次 App，窗回不回来**（核心验收）：进程被杀后重启动，2 秒内看门狗兜底建窗，打开 App 再退到主屏幕窗应回来；日志里应有「启动兜底」行，且只建一个窗（回调守卫，不建两个）。
4. **主页面不闪退**（#1 守卫仍在）：连接窗口（10 秒内）看门狗仍跳过恢复；进主页面不闪、悬浮窗／激活／逐歌偏移照常。
5. **只建一个窗**：兜底建窗＋Shell 回调晚到、解锁重建＋旧窗残留两种情况都不应出现两个窗；日志里活着的悬浮场景数应为 1。

### 构建（头 run 45952881898，head 4955361）

- **completed／success，13 步全 success**（job Build 13 步全 success）。轮询读 `status_field`／`conclusion`。
- **0 次池子取消**，第 2 轮 poll 已 success（约 2 分钟）。轮询脚本第一版读错字段（读了 HTTP `status` 200）已当场杀掉修正——`status_field` 才是 run 状态（2026-11-23 的教训重演，脚本 `hidden_files/poll_build25.py` 已改对）。
- 文档笔 e645695 的 run（45952904753）不用跟。

### 验包（编成后下载真 IPA＋dSYM 亲验，不要只信 run 绿）

- **验包 PASS（87 项，`hidden_files/verify_1.0.6_build25.py`，详见 `hidden_files/ipa_verify_1.0.6_build25.log`）**——build 24 是 82 项；新增 5 项：`build 25`／`启动兜底：Shell 回调未到，直接建悬浮场景`／`Shell 回调到了，悬浮场景已由兜底建好，跳过`／`场景创建已超过 10 秒仍未连接`／`判定卡住，走重建` 在位，`build 24`／`build 22`／`build 21`／`build 23` 不在位。
- IPA：`~/workspace/your_files/桌面歌詞-1.0.6-build25-newbase.ipa`（另存，**build 24 的 `桌面歌詞-1.0.6-build24-newbase.ipa` 未动**；文件名继续用繁體「歌詞」），**1,676,974 B，SHA256 `b04125b3f12db06b46e480ddcae7d9ad94c5f2217ec2988438432bfdad5eb412`**（artifact id 15177701953，名 桌面歌词-1.0.6，zip 1,675,183 B；解出与拷本 SHA 一致）。
- dSYM：artifact id 15177965318，名 `桌面歌词-1.0.6-dSYM`，zip **2,154,425 B**（内层 zip 2,164,386 B），存档 `hidden_files/artifact-1.0.6-build25/`（连同 IPA zip 与解出的 IPA）。内含 `TrollLyricsDesk.app.dSYM` 与 `TrollLyricsWidget.appex.dSYM`。
- **dSYM UUID 与 IPA 二进制的 Mach-O UUID 一致（两对都对得上，详见 `hidden_files/dsym_uuid_build25.log`）**：App `d554035b2ac43ab5a6796dff6639fa28`、Widget `bc1cc20b5a673049a24d6837449392b8`——Widget 的 UUID 与 build 24 一字不差（Widget 代码没动，合理）；zsign 重签没有改 LC_UUID。方法：新脚本 `hidden_files/dsym_ent_check.py`（LC_UUID cmd 0x1b；entitlements blob 口径与 build 24 一致——含 8 字节头，第一版写成只取 XML 体、尺寸少 8 字节，已修正，数字以修正后的为准）。
- **entitlements 与 build 24 一字不差（二进制级核对）**：app（3316B，SHA 前 16 位 `b6a9f77ea2237d00`）与 widget（472B，SHA 前 16 位 `63c0e2c366ea9d85`）均与 build 24 记录一字不差。
- 版本 1.0.6／build 25、包名 com.ycwl.Lyrics、MinOS 15.0；widget 1.0.6／build 25、com.ycwl.Lyrics.TrollLyricsWidget、MinOS 15.0。
- 锁屏不在位（NSSupportsLiveActivities／accessoryRectangular／LyricsLiveActivity／LiveLyricKey／publishLiveLyrics 全 0）；无 38473／DualProcessBridge／dynamic_lookup；ActivityKit 两二进制均 NOT LINKED；直链 FrontBoard／FrontBoardServices／RunningBoardServices／AppleAccount 在位；码值扫描 0 命中；BackBoard 仅 1 处对照表标签。
- **逃逸检查点仍是 2 个（详见 `hidden_files/escape_check_build25.log`）**：`hidden_files/escape_check_count.py` 数出 2 个点——0xDC6C／0xDCA4，同属函数 0xDBC8（地址相对 build 24 平移，同一函数）；**MediaRemote 函数里的 0x44A5C 没有回来**。注：跑脚本时 capstone 模块没了（`pip3 install --break-system-packages capstone` 重装 5.0.9 才跑起来；这台机 Python 模块会丢，部署／验包前要先确认）。

### 提交链（build 25）

- 第 1 笔 `4955361`：兜底两件＋版本 1.0.6/25＋自检 §20（7 个文件，+133/-26）。
- 第 2 笔 `e645695`：RUN 补 build 25 一节（只改文档，触发的 run 不用跟）。
- 第 3 笔（本节补填）：RUN §十五补构建＋验包实数（只改文档）。
- 头 run：45952881898（head 4955361）completed／success，13 步全 success，0 次池子取消；IPA `桌面歌詞-1.0.6-build25-newbase.ipa`，1,676,974 B，SHA256 `b04125b3…`，验包 87 项全过；dSYM 产物在且 UUID 两对都对得上；逃逸检查点 2 个；entitlements 与 build 24 一字不差。
- 分支：v1.0.6-lc（绝不从沙盒 git push；每笔先 check 再 gh_push.py 推；不要动 newbase／main／旧 v1.0.6 分支）。**不上源已定，不部署到越狱源；真机验收继续。未发给皇上**（等上级转）。

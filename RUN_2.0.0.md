# RUN 2.0.0 — HUD 守护进程并入 TrollLyricsDesk 正式版（build 29）

- 基线：`v1.0.6-lc` HEAD `c5c2c27`（1.0.6/build 28）
- 新分支：`v2.0-hud`（从 `c5c2c27` 建，绝不动 `v1.0.6-lc` 与 main）
- 提交：`9ded633`（`9ded6338aaf3cf83eec2c46243c7315873ce7065`）
- 仓库：`guhailon/trolllyricsdesk`（公开）
- 設計文檔：`docs/2.0.0-MERGE-DESIGN.md`（418 行）

## 一、为什么是 2.0.0 而不是 1.0.7

显示架构整代替换（FrontBoard 悬浮场景 → backboard 宿主 root 守护进程），
用户路径上没有 fallback 开关。旧路线死因已证：FrontBoard 在解锁瞬间因
后台 insecure drawing SIGKILL 杀进程（build 27 的 `.ips` 2026-11-27
16:13:05），不是 jetsam、不是代码闪退。build 25（重建）／26（前台复核）／
27（解锁重现）三代后台恢复共用同一个被证伪的假设，全部在真机上失败，
所以不再留开关——留开关等于维护两套显示栈。详见设计文档 §1、§6。

## 二、架构（设计文档 §2–§4）

- 新 target `TLDHUDDaemon`（`com.apple.product-type.tool`，bundle id
  `com.ycwl.Lyrics.hud`），可执行档由 App target 的 Run Script phase
  「Embed HUD Daemon」拷进 `TrollLyricsDesk.app/TLDHUDDaemon`（包根目录，
  不进 PlugIns／Frameworks）。App target 依赖 daemon target；scheme 加
  daemon BuildActionEntry。
- 主 App 继续写 App Group 快照（`group.com.hailong.TrollLyricsDesk`，
  `lyric.snapshot`）；daemon 每 1 秒只读快照，从不写、不联网、不用
  MediaRemote、不吞触摸（药丸 `_ignoresHitTest = YES`）。锁屏只藏视图停
  定时器，解锁只恢复显示——窗口／进程永不重建。
- **关键细节 1（helper 路径，设计 §3.2）**：HUD-Test 的 `InstallDaemonPlist`
  用 `_NSGetExecutablePath()`，在 helper 进程内是对的，主 App 调会拿到主
  App 自己的路径。`InstallDaemonPlist` 只留在 helper 二进位内；主 App 侧
  spawn 目标一律用新增函数 `TLDHUDHelperExecutablePath()`（当前可执行档
  所在目录＋`/TLDHUDDaemon`；若当前进程本身就是 helper 则返回自身）。
  模板路径也按可执行档目录找（tool 二进位无 bundle，`NSBundle
  pathForResource` 会返回 nil）。
- **关键细节 2（always-rewrite，设计 §4）**：Enable 一律重写 daemon plist
  （HUD-Test 0.2.1 的写法，commit `cb66edb`）。0.2.0 事故：重装后容器 UUID
  变了，旧 plist 指死路径，`launchctl load` exit 0 但进程永远起不来。
  重写是幂等的；先 best-effort `launchctl unload`，再 `load`，3 秒后
  `IsHUDEnabled()` 复核，两种结果都记日志。
- 设置页（`App/SettingsView.swift`）：新「悬浮歌词（HUD 守护进程）」区段
  在诊断区段之后——状态行（`TLDHUDIsEnabled()`＋PID 文件）、Enable／Disable
  按钮（后台队列调用 `TLDHUDSetEnabled`）、`NavigationLink` 到新
  `App/HUDLogView.swift`（读 `TLDHUDLogFilePath()`，末 120 行＋刷新）。
  LC 模式下只显示「LiveContainer 模式下不可用——宿主跑不了 root 守护进程，
  只显示应用内歌词。」绝不调 `SetHUDEnabled`。
- LC 启动分支直接定 compat／inApp，不试建场景、不等 6 秒兜底。

## 三、diff 摘要（`c5c2c27..9ded633`，48 文件，+3446／−88）

### 新增（HUD 移植，逐文件读过再搬）

| 文件 | 来源／说明 |
|---|---|
| `HUD/TLDHUDHelper.{h,mm}` | HUD-Test `HUDHelper` 改名；spawn 目标 4 处全用 `TLDHUDHelperExecutablePath()`；always-rewrite＋3 秒复核 |
| `HUD/TLDHUDPaths.{h,mm}` | 新增 `TLDHUDHelperExecutablePath()`；模板路径按可执行档目录；ID 换成 `com.ycwl.Lyrics.hud*` |
| `HUD/TLDHUDLog.{h,mm}` | 日志 `com.ycwl.Lyrics.hud.log`（`/var/mobile/Library/Logs/`） |
| `HUD/TLDHUDDaemonMain.mm` | daemon 入口：`-hud`／`-check`／`-exit`／`-install-daemon`；无参只记版本行＋用法错误（不跑 `UIApplicationMain`）；SpringBoard 重启后重拉 |
| `HUD/TLDHUDMainApplication.{h,mm}`、`TLDHUDMainApplicationDelegate.{h,mm}`、`TLDHUDMainWindow.{h,mm}`、`TLDHUDRootViewController.{h,mm}` | backboard 宿主窗口＋药丸视图；锁屏藏／解锁现；自清检查认主 App bundle id `com.ycwl.Lyrics`（移植时抓到的 bug：全局改名曾把它写成 daemon label，已修） |
| `HUD/TLDHUDLyricsSnapshot.{h,mm}` | 快照只读；分隔符表／`searchTerms` 只拆 `" · "`／`lyricLocation`／逐歌偏移与 `LyricStore.swift` @`c5c2c27` 逐行对过；新增测试文字模式（读 `floatingLyric.testTextEnabled`，显示 `懸浮測試 · 桌面歌詞 2.0.0 · HH:mm:ss`） |
| `HUD/TLDHUDVersion.h`（新） | `TLDHUD_VERSION_STRING @"2.0.0"`／`TLDHUD_BUILD_STRING @"29"`（daemon 无 Info.plist） |
| `HUD/TLDHUDDaemon.plist` | 模板：Label `com.ycwl.Lyrics.hud`，`ProgramArguments[0]` 是占位符（安装时重写），KeepAlive＋RunAtLoad，UserName root |
| `HUD/TLDHUDDaemon.entitlements` | 自有 entitlements（见 §五差異表） |
| `HUD/headers/*.h`（8 个） | TrollSpeed MIT 头文件，原样复制 |
| `HUD/Private/*.tbd`（3 个） | `BackBoardServices`／`GraphicsServices`／`SpringBoardServices` stub，原样复制 |
| `App/HUDLogView.swift`（新） | daemon 日志查看页 |
| `docs/2.0.0-MERGE-DESIGN.md`（新，418 行） | 设计文档 |
| `check_2.0.0.py`（新，438 行） | 自检脚本（§六） |

### 改动（主 App）

| 文件 | 改动 |
|---|---|
| `Overlay/TLDSAppDelegate.m`（+70／−49） | kill-switch `static const BOOL TLDSFrontBoardOverlayDisabled = YES;`；启动分支重写（trollstore→`nativeHUD`、unknown→native-candidate＋`nativeHUD`、LC→compat／inApp，均不再调 `startFloatingOverlay`／`TLDSInstallNativeWindowFix`，无 6 秒 fallback dispatch）；锁屏监听／前台复核监听／2 秒看门狗创建各包进 `if (!TLDSFrontBoardOverlayDisabled)`（3 处）；5 个入口 early-return（`startFloatingOverlay`、`reactivateFloatingOverlayWithTrigger:`、`unlockRestoreFloatingOverlay`、`foregroundVerifyFloatingWindow`、`verifyFloatingVisibility`，日志 `诊断2.0.0 FrontBoard 已停用`）；旧恢复方法本体保留未删 |
| `Overlay/TLDSSceneDelegate.m`（+7） | 任何 `TLDSFloatingLyric*` 会话记日志并忽略，窗口永不建 |
| `App/SettingsView.swift`（+88） | HUD 区段＋`@State hudStatusText/hudRunning/hudBusy`＋`refreshHUDStatus()` |
| `Lyrics/LyricStore.swift` | `versionTag` → `build 29（2.0.0）`；`testText()` → 2.0.0；`displayCapabilityDescription` →「HUD 守护进程悬浮歌词」 |
| `Compatibility/RuntimeEnvironment.swift` | 两处 `displayName` →「HUD 守护进程悬浮歌词」 |
| `Renderer/NativeHUDRenderer.swift` | `engineName` 同上＋头注释 |
| `Diagnostics/DiagnosticsView.swift` | 「原生悬浮显示能力」→「HUD 守护进程显示能力」 |
| `Overlay/TrollLyricsDesk-Bridging-Header.h` | import `TLDHUDHelper.h`／`TLDHUDLog.h`／`TLDHUDPaths.h` |
| `TrollLyricsDesk/Info.plist`、`TrollLyricsWidget/Info.plist` | 2.0.0／29（sed 精准改两行） |
| `LICENSE` | 加 `Copyright (c) 2023 Lessica (TrollSpeed HUD mechanism, see docs/2.0.0-MERGE-DESIGN.md)` |
| `TrollLyricsDesk.xcodeproj/project.pbxproj`（+496） | daemon target＋Debug／Release 配置＋配置列表；App `HEADER_SEARCH_PATHS` ＋`$(SRCROOT)/HUD`（×2）；HUD 组＋headers 子组；daemon Sources／Frameworks phases；Embed HUD Daemon script phase（`cp -f`＋`test -f` 断言）；App→daemon 依赖＋proxy；App Sources ＋4 文件；App Resources ＋daemon plist 模板；`MARKETING_VERSION 2.0.0` ×6／`CURRENT_PROJECT_VERSION 29` ×6。修过两处手术事故：App Sources 多出的一个 `};` 已删（大括号已平衡）；Resources 里被吃掉的 Assets.xcassets 已补回。**已知旧问题（HEAD 就有，不是本次引入）**：未定义引用 `2AC9C558E40544F86D76B6FD`（Widget phase 里的旧文件 dangling），留着不动 |
| `TrollLyricsDesk.xcodeproj/xcshareddata/xcschemes/TrollLyricsDesk.xcscheme`（+14） | daemon BuildActionEntry（3 个条目：App＋Widget＋daemon） |
| `.github/workflows/build.yml`（+39／−） | `zsign -a -f -e HUD/TLDHUDDaemon.entitlements "$APP/TLDHUDDaemon"`＋`codesign -d --entitlements -` 打印；archive 布局检查断言 helper 二进位＋plist 模板在位、dSYM 恰好 3 个；产物名 `桌面歌词-2.0.0` |

### 未动（保留项，缺一不可）

激活（`POST https://guhailong-repo.pages.dev/api/verify`，TLD 码表只在
worker codes 文件里）、MediaRemote 跟随、LRCLIB、逐歌偏移、「·」修复
（`searchTerms` 只拆 `" · "`）、应用内歌词、小组件、About 页（作者
China fly、QQ 群 166623677、Telegram @Guhailon）。不恢复锁屏歌词。
LC 检测（`LyricStore.isLiveContainer`，6 个信号）一字不动。
`@escaping` 回调修法不动（build 23 的闪退教训）。LCProbe／v0.2 不动
（另有侧聊在推）。TrollSpeed MIT 署名不动；XExternalHUD 代码零复制
（代码区 grep 0 命中）；`JetsamHelper`／`BypassJetsamByProcess` 死代码
不抄（daemon 靠 launchd KeepAlive＋root 存活）。

## 四、构建

头 run：**46056504139**（head `2b7d6e3`），`status_field=completed`，
`conclusion=success`。分支 `v2.0-hud`，5 个提交：
`9ded633`（合併本體）→ `4043000`（daemon 链接修）→ `d08f8c6`（补回
DiagnosticsView）→ `5a1df59`（TLDHUDLogMessage wrapper）→ `2b7d6e3`
（两处 1.0.6 测试文字）。

构建经过（晚间池子拥堵严重，池子取消一律默默重跑，不逐次上报）：
- run 46037981048（`9ded633`）：6 次池子取消（Build cancelled，0 steps）
  后终于跑起来，**真失败**——Archive 步：daemon 链接报 UIKit 符号
  undefined（`_OBJC_CLASS_$_UIApplication`／`UIColor`／`UIFont`／`UILabel`／
  `UIWindow`、`_UIApplicationInitialize` 等）。原因：HUD-Test 是同一二进制
  双模式，UIKit 由 app target 链进来；新 tool target 只加了 3 个私有 .tbd。
  修：daemon 两配置 OTHER_LDFLAGS 加 `-framework Foundation`／`-framework UIKit`
  （提交 `4043000`；自检新增同款断言）。
- run 46052617013（`4043000`）：**真失败**——`SettingsView.swift:295`
  `cannot find 'DiagnosticsView' in scope`。原因：pbxproj 手术时锚点替换
  把 App Sources 里的 `DiagnosticsView.swift` 一行吃掉了（定义还在，
  phase 文件表里没了）。修：补回该行（提交 `d08f8c6`）；全相位扫过无其他
  丢失；自检新增 §7b phase 文件集对照（与 HEAD `c5c2c27` 比，旧文件一个
  不能少）。
- run 46053945402（`d08f8c6`）：**真失败**——`SettingsView.swift:343/345/
  358/360`：`'TLDHUDLog' is unavailable: Variadic function is unavailable`。
  原因：`TLDHUDLog` 是 C 变参函数，Swift 调不了；HUD-Test 是 ObjC 调用
  所以没事。修：新增非变参 wrapper `TLDHUDLogMessage(NSString *)`
  （`HUD/TLDHUDLog.h`／`.mm`，内部转 `TLDHUDLog(@"%@", message)`），Swift
  4 处改调 wrapper；ObjC 侧继续用变参版（提交 `5a1df59`；自检新增断言）。
- run 46055218565（`5a1df59`）：**success**，但独立验包发现 IPA 里还含
  「悬浮测试 · 桌面歌词 1.0.6」（`SettingsView.swift:280` 说明文字、
  `PiPLyricsRenderer.swift:108` PiP fallback 文本漏改版本；该 IPA 已作废，
  SHA256 `55b0d33d…`）。修：两处改 2.0.0（提交 `2b7d6e3`；自检新增断言）。
  另：验包时 capstone 模组又掉了（pip 重装后恢复）；`escape_check_count.py`
  在该 IPA 上实测正好 2 站点。
- run 46056504139（`2b7d6e3`）：2 次池子取消后跑起来，**success**。
  验包见 §五，0 FAIL。

## 五、验包（`hidden_files/verify_2.0.0.py`，独立下载的 IPA，0 FAIL）

- IPA：`hidden_files/artifact-2.0.0/桌面歌词-2.0.0.ipa`，
  **1,712,731 B**，SHA256
  `8e9b5a6ddeb452ca8c457026e055eb45c7eb28f2bd30beee2536b180e955591a`
  （头 run 46056504139，head `2b7d6e3`）。
- 版本／包名：App＋Widget 均为 2.0.0／build 29，包名
  `com.ycwl.Lyrics`／`com.ycwl.Lyrics.TrollLyricsWidget`，MinOS 15.0；
  无 `NSSupportsLiveActivities`（锁屏已取消）。
- helper 在位：`TrollLyricsDesk.app/TLDHUDDaemon`＋`TLDHUDDaemon.plist`
  模板（Label `com.ycwl.Lyrics.hud`，`ProgramArguments[0]` 是占位符
  `/var/jb/Applications/TrollLyricsDesk.app/TLDHUDDaemon`，KeepAlive＋
  RunAtLoad，UserName root）。
- Mach-O：三二进制 thin arm64，`LC_CODE_SIGNATURE` ×3；ActivityKit 三者
  都不链；App 直链 FrontBoard／FrontBoardServices／RunningBoardServices
  （旧代码仍在）；daemon 直链 Foundation／UIKit／BackBoardServices／
  GraphicsServices／SpringBoardServices，**不链 FrontBoard**。
- 三 dSYM UUID（与二进制 LC_UUID 一一对上）：
  - App：`5b91241dbbe8347f90fcdf7273523b7e`
  - Widget：`24d000bc2f29311ebddf5b8d184170f3`（与上一成功 IPA 相同，
    Widget 未动）
  - daemon：`6b73606391b33f0892dc1f5f5de7892e`（与上一成功 IPA 相同，
    daemon 未动）
- entitlements：三二进制 slot 5 的 key 集与源码文件逐项一致（无多无少，
  值也一致）；差異表见本节下方（由脚本实测打印）。
- 字串：在位——`2.0.0`／`build 29`／`api/verify`／`tld.activated`／
  `tg://resolve?domain=Guhailon`／`TLDSLiveContainer`／`LC_HOME_PATH`／
  `nativeHUD`／`HUD 守护进程悬浮歌词`／`诊断2.0.0 FrontBoard 已停用`／
  `LiveContainer 模式下不可用`／daemon 侧 `com.ycwl.Lyrics.hud*`／
  `hud: lyrics now`／`hud: window registered`／`rewriting daemon plist
  (always on Enable)`／`daemon started after launchctl load (3s check)`／
  `hud: locked, view hidden`／`hud: unlocked, view shown`／
  `lyric.snapshot`／`floatingLyric.testTextEnabled`／
  `SBSpringBoardDidLaunchNotification`；不在位——`38473`（旧 widget
  token）、`DualProcessBridge`、`dynamic_lookup`、锁屏相关
  （`NSSupportsLiveActivities`／`LyricsLiveActivity`／`ActivityKit` 等）、
  `诊断1.0.5`、`悬浮测试 · 桌面歌词 1.0.6`、`build 21–28`、
  `XEHUD`／`XExternalHUD`、`JetsamHelper`／`BypassJetsamByProcess`。
  （旧「诊断1.0.6」前缀故意不在 ABSENT——死代码里仍有，见 §八。）
- TLD 码值扫描：0 命中。
- 逃逸检查：App 正好 **2 个** `swift_isEscapingClosureAtFileLocation`
  站点（0x10000d02c／0x10000d064，同在 0x10000cf88 函数内），0x44A5C
  崩点未回来；daemon 不含该符号。

### entitlements 差異表（二进制 slot 5 实测，与源码文件逐项一致）

| key | App | Widget | daemon | 为什么 |
|---|---|---|---|---|
| `application-identifier` | — | — | `com.ycwl.Lyrics` | daemon 自有（HUD-Test 0.2.0／0.2.1 验证集，只改了这一项的值） |
| `com.apple.security.application-groups` | ✓ | ✓ | ✓ | 三者都要读同一 App Group 快照 |
| `com.apple.mediaremote.now-playing-read-access`／`full-now-playing-read-access` | ✓ | — | — | 只有主 App 跟随播放；daemon 只读快照 |
| `com.apple.private.security.no-sandbox`／`platform-application`／`get-task-allow`／`com.apple.private.persona-mgmt`／`com.apple.private.kernel.jetsam`／`com.apple.private.memorystatus` | ✓ | — | ✓ | root 守护进程存活＋读写所需；Widget 不需要 |
| `com.apple.frontboard.launchapplications`／`com.apple.backboard.client`／`com.apple.QuartzCore.displayable-context`／`com.apple.QuartzCore.secure-mode`／`com.apple.springboard.CFUserNotification`／`com.apple.springboard.appbackgroundstyle`／`com.apple.springboard-ui.client`／RunningBoard 7 项／`file-read-data`／`user-preference-read`／`user-preference-write`／`com.apple.private.security.storage.*` ×2 | ✓ | — | ✓ | 显示＋宿主所需，daemon 与 App 相同 |
| `com.apple.springboard.statusbarstyleoverrides`／`com.apple.private.allow-background-haptics` | ✓ | — | — | 主 App 旧 FrontBoard 路径遗留；daemon 不做状态栏／触觉 |
| `com.apple.security.exception.mach-lookup.global-name` | 6 项（含 `com.apple.appstored.xpc` ×2、`com.apple.mobileassetd.v2`） | — | 3 项（frontboard.systemappservices、UIKit.statusbarserver、springboard.SBRendererService） | daemon 不碰 App Store／mobileassetd |
| `com.apple.security.iokit-user-client-class` | 5 项（含 `AppleJPEGDriverUserClient`） | — | 4 项（无 AppleJPEG） | daemon 不做 JPEG 解码 |

## 六、自检（`check_2.0.0.py`，0 FAIL）

- 版本／包名／MinOS（两 plist 2.0.0／29／15.0；pbxproj MARKETING 2.0.0 ×6、CURRENT 29 ×6）
- HUD 移植关键细节：helper 路径规则、4 处 spawn 全用 helper 路径、模板按可执行档目录、always-rewrite＋3 秒复核、daemon 四模式、无参不跑 `UIApplicationMain`
- FrontBoard 触发点：kill-switch、3 处条件包、5 个入口 early-return、LC 分支、SceneDelegate 守卫
- LC 硬性要求：6 个检测信号一字在位；设置页 LC 禁用说明
- 保留项：激活／MediaRemote／LRCLIB／偏移／「·」／应用内歌词／小组件／About／无锁屏／`@escaping`
- pbxproj：大括号平衡、引用皆有定义（除已知旧 dangling `2AC9C558E40544F86D76B6FD`）、daemon target／配置／3 个 .tbd／entitlements／Embed phase／scheme 3 条目
- build.yml：daemon zsign＋entitlements 打印＋helper 在位断言＋3 dSYM 断言＋2.0.0 檔名
- 署名／禁区：LICENSE Lessica 行、XExternalHUD 0、JetsamHelper 0、旧 widget token（38473）0
- 验包脚本：`hidden_files/verify_2.0.0.py`（本地，`hidden_files/` 不进仓库）——IPA 独立验包用：3 二进制版本／thin arm64／3 dSYM UUID 对上／entitlements 三方比对／字串在位＋不在位／TLD 码值 0 命中／逃逸检查 App 仍为 2 个、daemon 0 个

## 七、给 Lee 的真机测试清单

前置：Sileo 刷新源，装 2.0.0（build 29）。**注意：2.0.0 没有回退开关——
旧 FrontBoard 悬浮场景已从用户路径移除，悬浮歌词只能走 HUD 守护进程。**

1. 全新安装 Enable：设置页 →「悬浮歌词（HUD 守护进程）」→ 点 Enable，
   状态行变「已启用」，桌面出现药丸（显示当前歌词或 `桌面歌词 2.0.0` 测试文字）。
2. 覆盖旧版安装 Enable（stale-plist 回归）：在已装 1.0.6 的机上直接覆盖装
   2.0.0 再 Enable——容器 UUID 变了也必须能起（0.2.0 事故的回归项）。
3. 五项歌词测试：①跟行（当前行高亮跟随）②切歌（歌名／歌词立即换）
   ③暂停／续播（暂停定住，续播继续跟）④无歌 fallback（停歌后药丸显示
   「未在播放」类提示）⑤锁屏解锁后还在跟（**只看主屏幕上的歌词本身在不在、
   跟不跟，不看日志行**——Lee 2026-11-27 的验收标准）。
4. 回归：回桌面／切 App／连续 10 次锁屏解锁／后台 30 分钟——药丸一直在、
   歌词一直在跟，不黑屏、不闪退。
5. 设置页日志查看：点「查看守护进程日志」，能看到 daemon 日志（末 120 行）。
6. LC 模式（LC 手机）：设置页 HUD 区段只显示禁用说明，daemon 不出现；
   应用内歌词正常。
7. 测试文字开关：设置页打开悬浮测试文字，药丸显示
   `懸浮測試 · 桌面歌詞 2.0.0 · HH:mm:ss`（时间每秒变）。

## 八、已知限制／风险

- daemon dSYM 已确认进 archive（验包：3 个 dSYM，UUID 全对上；
  build.yml 的 3 个断言在 CI 里通过）。
- 旧「诊断1.0.6」日志前缀仍在死代码里（历史），新行用「诊断2.0.0」；
  验包 ABSENT 列表故意不含 `诊断1.0.6`。
- pbxproj 里 App Sources phase 仍有 5 个 `EA000000000000000000000x`
  占位引用（HEAD 就有），不影响构建，本次不动。
- 未定义引用 `2AC9C558E40544F86D76B6FD`（HEAD 就有，Widget phase 旧文件
  dangling），本次不动。
- 真机未验证：Enable／stale-plist 回归／五项歌词／10 次锁解／30 分钟后台／
  LC 禁用——全部等 Lee 的设备测试；在此之前不宣称修好。
- 不上源、不发 Telegram（频道暂停中，Lee 未说恢复）；2.0.0 只发 IPA 给 Lee
  真机测试。

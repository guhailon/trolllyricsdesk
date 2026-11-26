# TrollLyricsDesk 1.0.5 — run log

1.0.3 cycle is in RUN_1.0.3.md (1.0.3 build 16 built + verified 2026-11-26, run 45753959179).
1.0.5 = 1.0.3 底子＋皇上发来的 1.0.4 DualProcess 源码包融合（`~/workspace/user/files/TrollLyricsDesk-1.0.4-DualProcess-source.zip`，926,776 B）。
独立版（TrollStore）保留 MediaRemote、FrontBoard、Live Activity、激活；
新增 DualProcessBridge：独立版在 127.0.0.1:38473 起只读 TCP 服务，LC 版
（LiveContainer）每秒读歌词快照；两端分别激活；配对码是本机 UUID
（`tlds.bridge.token`，存在 UserDefaults），不是激活码。桥只同步歌词快照，
不同步设置／激活／音乐控制。LC 开关双保险：运行时读 Info.plist 的
`TLDSLiveContainer` 键（`LyricStore.isLiveContainer`），编译期
`-DTLDS_LIVE_CONTAINER=1` 只进 Overlay 的两个 .m 文件；TrollStore 构建
两者都没有，行为与 1.0.3 一致（只多一个本机桥服务＋「复制 LiveContainer
配对码」按钮）。**作者自述：只做过 Linux Swift parser 和 bash 语法检查，
不是 Xcode 类型检查或真机测试**——云端构建＋验包这关从严。
1.0.5 不修 Telegram 行点了没反应、不修锁屏歌词不见（那两件还在等皇上回
对照测试结果）。
Branch v1.0.1, worktree `~/workspace/trolllyricsdesk-1.0.1`, local HEAD dfbebfb.

## 推送（2026-11-26 16:10 CST）

远端 v1.0.1 从 0e1e014 起，gh_push.py 逐笔推（每笔推前先 check，均为
fast_forward_one_commit），三笔全上，远端终为 dfbebfb：

- b28cfc7（补 RUN_1.0.3.md：1.0.3 run 45753959179 成功记录＋BUILD_NOTES 自检行
  ——上个周期留下的未提交修改，先单独提交推送；其 run 45780900297 也是
  success，中间 run，不管）
- c68acc6（1.0.5 build 17：融合 DualProcess；其两个 run 也都是 success：
  Build 45780978241、Build LiveContainer 45780978244，中间 run，不管）
- dfbebfb（加 check_1.0.5.py 自检，锚点 0e1e014）

本地自检 `check_1.0.5.py`：**57 PASS、FAILED: none、OPEN 12**（提交后重跑才算数；
提交前红线两项必然 FAIL——HEAD 里还没有改动）。

LC 开关核实（融合前逐文件 diff 读过）：`LyricStore.isLiveContainer` 是运行时
读 Info.plist 的 `TLDSLiveContainer` 键；`build.yml` 的 TrollStore 构建不传
`-DTLDS_LIVE_CONTAINER`、Info.plist 里也没有这个键；Overlay 两个 .m 文件的
改动只是 `#ifndef/#ifdef TLDS_LIVE_CONTAINER` 守卫；其余 Swift 改动一律用
`if !LyricStore.isLiveContainer` 包起来。`scripts/build-livecontainer.sh`
在隔离副本里改 plist（加 `TLDSLiveContainer=true`，删 `BSServiceDomains`／
`UIBackgroundModes`／`NSSupportsLiveActivities`，显示名改「桌面歌词 LC」，
单场景）＋`OTHER_CFLAGS -DTLDS_LIVE_CONTAINER=1`＋去签名＋删 PlugIns。
一个坑：zip 里 `MARKETING_VERSION` 还是 1.0.3（只改了 Info.plist 的版本号），
直接编会出 1.0.3——融合时按 1.0.3 的做法把四处 MARKETING_VERSION＋两
Info.plist＋两 workflow 产物名都升到 1.0.5／build 17 才推。

## run 45781002214（Build，TrollStore）— head dfbebfb — 2026-11-26 16:10–16:14 CST — SUCCESS

- attempt 1 一次上机成功，无池子取消。轮询（读 `status_field`／`conclusion`）。
- Artifact：id 15098876776，名「桌面歌词-1.0.5」，zip 1,627,968 B。
- IPA：**桌面歌词-1.0.5.ipa，1,629,723 B，SHA256 `c458410133b1efb8757c20abcaeeec7c66fae181d98287420461d7f6afd2bade`**。
  存 `~/workspace/trolllyricsdesk-1.0.1/hidden_files/artifact-45781002214/`
  （artifact.zip＋IPA＋check/），另拷一份到
  `~/workspace/your_files/桌面歌词-1.0.5.ipa`（SHA 一致）。

## run 45781002225（Build LiveContainer）— head dfbebfb — 2026-11-26 16:10–16:12 CST — SUCCESS

- attempt 1 一次上机成功，无池子取消。
- Artifact：id 15098167666，名「TrollLyricsDesk-LiveContainer」，zip 1,564,582 B。
- IPA：**桌面歌词-1.0.5-LiveContainer.ipa，1,565,462 B，SHA256 `3f364cef1c2f408717d7c5dd7dd053bc4cf390d5b0db24a798160b0193e2f94b`**。
  存 `~/workspace/trolllyricsdesk-1.0.1/hidden_files/artifact-45781002225/`
  （artifact.zip＋IPA＋check/），另拷一份到
  `~/workspace/your_files/桌面歌词-1.0.5-LiveContainer.ipa`（SHA 一致）。

## 验包（TrollStore IPA，全过）

- App：1.0.5／build 17、显示名「桌面歌词」、包名 com.hailong.TrollLyricsDesk2、
  MinOS 15.0、`NSSupportsLiveActivities=true`、`UIBackgroundModes=[audio]`、
  `BSServiceDomains` 在位、`TLDSLiveContainer` 不在（独立版）
- Widget：1.0.5／build 17、MinOS 15.0，二进制含 `accessoryRectangular`（×1）
- 架构：Mach-O 64-bit arm64，两二进制均为 arm64（subtype 0）
- 签名（zsign）：两二进制均含 LC_CODE_SIGNATURE
- 弱链接（本机无 otool，用 `~/workspace/trolllyricsdesk/hidden_files/macho_inspect.py`
  核实，弱链接 cmd 0x80000018 含 LC_REQ_DYLD 位）：App 与 Widget Extension
  两二进制的 ActivityKit 均为 **LC_LOAD_WEAK_DYLIB**
- 激活串在位：App 二进制含 `api/verify`（×1）、`tld.activated`（×1）、
  `tld.activationType`（×1）
- Telegram 新行在位：`tg://resolve?domain=Guhailon`、`https://t.me/Guhailon`；
  旧 invite 串 0（`seadragonjb`／`I-I8aw7HUAw1NGY9` 皆 0）
- 桥在位：`DualProcessBridge` 类名＋符号（×2）、`tlds.bridge.token`、
  `tlds.bridge.lastReceived`；端口 38473 是数值字面量、127.0.0.1 是 Swift
  内联小字符串，二进制里搜不到字面量是正常的（同 1.0.3 的 `tld.activated`
  内联情况），桥以类符号＋Network 引用为准
- Overlay 在位（独立版应有）：`FBSystemShellInitialize`（×2）、
  `TLDSFloatingLyric`（×1）
- 无码值：TLD-XXXX-XXXX-XXXX 格式扫 App 二进制，命中 0
- 否定项：`BackBoard`／`TLHUDApplication` 大小写敏感 0；
  `com.apple.backboard.client`（×2）是签名里嵌的 entitlements 键，
  1.0.3 二进制里一模一样有，不是 1.0.5 新引入的；`dynamic_lookup` 0

## 验包（LC IPA，全过；按脚本实际做法核对）

- App：1.0.5／build 17、显示名「桌面歌词 LC」、包名 com.hailong.TrollLyricsDesk2、
  MinOS 15.0、`TLDSLiveContainer=true`、`UIBackgroundModes` 不在、
  `NSSupportsLiveActivities` 不在、`BSServiceDomains` 不在、单场景
  （`UIApplicationSupportsMultipleScenes=false`）
- 无 PlugIns 目录（Widget 已按脚本删掉）；无小组件、无锁屏歌词是设计，
  不要当 bug 报
- 架构：Mach-O 64-bit arm64；签名：**LC_CODE_SIGNATURE 不在——未签名**，
  按脚本做法（`CODE_SIGNING_ALLOWED=NO`），LiveContainer 导入时由宿主签名
- 弱链接：App 二进制的 ActivityKit 仍为 **LC_LOAD_WEAK_DYLIB**
- 桥在位：`DualProcessBridge` 类名＋符号（×2）、`tlds.bridge.token`、
  `tlds.bridge.lastReceived`、Network 引用（`NWListener`／`NWConnection` ×44）
- Overlay 初始化已编掉：`FBSystemShellInitialize` 0；类名
  `TLDSFloatingLyric`／`TLDSPassThroughWindow` 各剩 1 处符号——Overlay
  两个 .m 文件仍在 target 里编译，类符号留着，但初始化调用被 `#ifndef`
  编掉、场景委托在 LC 下强制主场景（`isMain=YES, isFloating=NO`），
  悬浮窗不会起来
- 激活串在位：`api/verify`（×1）、`tld.activated`、`tld.activationType`；
  Telegram 新行在位；旧 invite 串 0；TLD- 格式码值 0；
  `BackBoard`／`TLHUDApplication` 大小写敏感 0；`dynamic_lookup` 0

## 实现改了哪些文件（c68acc6＋dfbebfb）

- 融合 13 改＋4 新增（以皇上发的 zip 为准）：`.github/workflows/build.yml`
  （只改版本号＋产物名）、`App/ActivationView.swift`（@AppStorage 改
  `LyricStore.defaults`；widget 刷新加 LC 判断）、`App/ContentView.swift`／
  `App/SettingsView.swift`／`App/PlaybackDashboardView.swift`（@AppStorage
  改 `LyricStore.defaults`；LC 下锁屏区显示「LiveContainer 模式不支持
  锁屏歌词和小组件」；仪表盘 LC 分支：配对码输入框＋连接状态＋手动
  暂停／归零，独立版分支：复制配对码按钮）、`App/LyricsSearchView.swift`
  （widget 刷新加 LC 判断）、`App/TrollLyricsDeskApp.swift`（`import Network`；
  保活＋检测启动加 LC 判断；新增 `DualProcessBridge`：独立版起
  127.0.0.1:38473 只读 TCP 服务，36 字节配对码＋已激活＋快照 ≤1MB 才回
  JSON；LC 版每秒请求一次，收到快照写 `LyricStore`＋刷新时间戳）、
  `Lyrics/LyricStore.swift`（加 `isLiveContainer` 运行时判断＋
  `LyricStore.defaults` 按 LC 切标准／App Group 两套存储）、
  `Overlay/TLDSAppDelegate.m`／`Overlay/TLDSSceneDelegate.m`（只加
  `#ifndef/#ifdef TLDS_LIVE_CONTAINER` 守卫）、
  `PlaybackEngine/LyricsLiveActivityController.swift`（取色键改读
  `LyricStore.defaults`）、`PlaybackEngine/PlaybackCoordinator.swift`
  （LC 下不启动检测、不推 widget 刷新）、`TrollLyricsDesk/Info.plist`
  （键重排＋版本号）、`.github/workflows/livecontainer.yml`（新）、
  `DUAL_PROCESS.md`／`LIVE_CONTAINER.md`（新）、
  `scripts/build-livecontainer.sh`（新）
- 版本升 1.0.5／build 17：`MARKETING_VERSION` 四处＋两 Info.plist＋
  build.yml／livecontainer.yml／build-livecontainer.sh 产物名＋
  DUAL_PROCESS.md 标题；`CURRENT_PROJECT_VERSION` 保持 1 不动
  （1.0.3 起就这样，build 号以 Info.plist 的 CFBundleVersion 为准）
- `check_1.0.5.py`（新，dfbebfb）：57 PASS、FAILED: none、OPEN 12，
  红线锚点固定基点 0e1e014，提交后重跑才算数
- 另有 b28cfc7：上个周期留下的两份文档（BUILD_NOTES.md、RUN_1.0.3.md）
  单独提交，与 1.0.5 融合无关

## 待真机验（OPEN 12，自检原样）

- loopback 可达性：LC 版在 LiveContainer 里能不能连上 127.0.0.1:38473
- 后台挂起：独立版被挂起或杀死时桥不可用，没有系统守护进程兜底
- 宿主网络限制：LiveContainer 宿主的网络限制会不会挡住本机回环
- 切歌／暂停／拖进度：桥接下切歌、暂停、拖进度跟不跟，旧快照会不会残留显示
- 配对失败和重连：配对码错了、独立版没开、重连时 LC 版的表现
- 未连接时旧快照可能仍显示：连接状态只表示收到快照，不保证音乐仍在播放
- LC 偏好隔离／网络激活／导入行为未验证；原工程私有框架链接设置保留，
  可能需要进一步精简
- LC 版没有全局悬浮窗和锁屏歌词（设计，不要当 bug 报）
- Telegram 行点了没反应（1.0.3 结转，1.0.5 没修）：等皇上回 QQ 行对照测试结果
- 锁屏歌词显示后不见（1.0.3 结转，1.0.5 没修）：等皇上确认不见时屏幕亮不亮＋
  锁屏开关状态
- 1.0.2 五件真机验（结转）：背景图／悬浮窗固定／日志复制清除／Telegram 行／
  提示文字＋标题居中
- 1.0.3 激活真机验（结转，已通一次）：首次打开输码、错码／没网各提示各的、
  杀掉重开不再要码、卸载重装要重新激活

# RUN_2.0.2 — 2.0.2/build 32

分支 `v2.0.2`，基线 cf78428（2.0.1/build 31）。HEAD `9b0ae60`
（完整 SHA `9b0ae60b85fe213e108af056bfd162658c33b885`）。

## 1. 分支与提交顺序

```
cf78428  2.0.1/build 31
a35f08b  ChatGPT 建议：PID 校验＋Enable 健壮性（2.0.2 底子）← 底子第一笔
3b55028  2.0.2/build 32：六项功能＋升版 31→32（变基后）
25094ff  2.0.2：自检＋验包补 ChatGPT 底子断言（§16）
160581e  libproc.h 不在 iOS SDK 里，proc_pidpath 改前置声明
4d11918  proc_pidpath 前置声明加 extern "C"
9b0ae60  药丸 hitTest 几何改手算（HEAD，编出 IPA 的那笔）
```

- 底子提交必须是第一笔：功能提交 3e2e656 已先推上远程，接到
  底子任务后用 rebase 把它移到 a35f08b 之上（3b55028），远程 ref
  用 git-data API PATCH `force: true` 一次移到 25094ff（旧头
  3e2e656／ab52312 作废；v2.0.2 是当天新建的编包分支，无其他人
  拉过）。其后三笔小修全是快进推（gh_push.py）。
- 本地临时分支 `v2.0.2-base`（建底子用）已无用，未推远程。

## 2. 底子核对：zip 与任务描述不符（只拷了三份文件）

`~/workspace/user/files/ChatGPT.zip` 解开后与 cf78428 对比，**不是
只有三处改动**：共 23 处不同——除三份文件外，还有 19 个文件改动
（build.yml、ActivationKeychain、PlaybackDashboardView、SettingsView、
TrollLyricsDeskApp、RuntimeEnvironment、DiagnosticsView、EngineTests、
LyricLine、LyricParser、LyricStore、MediaRemoteAdapter、MusicTrack、
TLDSAppDelegate、PlaybackCoordinator、PlaybackState、pbxproj、两处
Info.plist）＋一个 zip 自带的 `RUN_2.0.2.md`（写的是个大号
“first compatibility patch”：Apple Music fallback、增强 LRC 词级
timing、激活 allowlist 等）。任务说的“diff 干净，只有三处改动”
与 zip 实测不符。

按任务执行：**只拷了三份文件**，其余 19 处＋zip 的 RUN 文档一律
没动。三份文件各自与任务描述逐字相符，且自包含（不依赖 zip 里
其他文件）：

1. `HUD/TLDHUDDaemonMain.mm`：新 `TLDHUDOwnPID(pid)`（proc_pidpath
   ＋realpath 核对可执行路径）；`-exit` 先验 PID，未通过记
   `hud: refusing stale or unverified PID` 并拒绝；
   `-check` 未通过直接回 EXIT_SUCCESS。
2. `HUD/TLDHUDHelper.mm`：(a) waitpid 后只在 WIFEXITED 时读退出码；
   (b) `TLDHUDIsEnabled` 由 `status != 0` 改 `status == 1`；
   (c) Enable 只有 plist 装成功才走 launchctl unload/load，load
   失败直接返回（走直启 -hud 兜底）。
3. `HUD/TLDHUDVersion.h`：注释里的 check_2.0.1.py → check_2.0.2.py，
   另含升版 2.0.2／32（与功能提交的升版一致，变基时只冲突了注释
   这一行，留了底子的 check_2.0.2.py）。

## 3. 六项功能（3b55028）

1. **药丸长按拖动**：`TLDHUDRootViewController.mm`，pill 存成 ivar，
   top＋centerX 两根可调约束定位（Auto Layout 仍管尺寸，不打架）；
   `UILongPressGestureRecognizer`（0.5s，allowableMovement 放大到
   10000，防按住后手指已动导致手势失败）；Began 半透明（alpha 0.6），
   Changed 跟手，Ended／Cancelled 恢复并保存。位置写 App Group 新键
   `hudPill.positionX`／`hudPill.positionY`（存中心点），启动后首次
   布局读回；锁屏只藏视图、解锁只显示，约束不动故不丢位置。位置用
   UIScreen bounds 夹，药丸任何一边不出屏。只加了长按，无点按／双击。
   窗口侧：`TLDHUDMainWindow` 的 `_ignoresHitTest` 由 YES 改 NO（否则
   药丸接不到触摸），并重写 `hitTest:` 只放行药丸框内的触摸，其余
   return nil 落到下层 App——药丸不吞全屏触摸。
2. **「固定位置」开关**：主页面 HUD 区段（非 LC 分支）启用按钮旁，
   `Toggle("固定位置")`，新键 `hudPill.positionLocked`（默认关），
   旧死键 `floatingLyric.positionLocked` 与声明一字未动。锁住时手势
   处理直接 return（无反馈）；守护进程每秒 tick＋解锁时重读标志。
   LC 下开关不出现。
3. **关于页删「日志」行**：`AboutView` 里 `NavigationLink(LogView())`
   那一行删掉；作者／当前版本／加入官方群组／Telegram 频道四行原样。
   `LyricLogger` 写 `Documents/TrollLyricsDesk.log` 不动，主页面
   「查看守护进程日志」不动。
4. **「悬浮歌词颜色」取色器**：主页面 HUD 区段，复用旧键
   `floatingLyric.textColorHex` 与 `lyricTextColor` 互转 helper
   （build 30 只藏了控件，键与声明都在）。守护进程每秒 tick 从 suite
   重读颜色，应用到 `_testLabel` 三档（白底换成读到的颜色，
   alpha 0.65／0.45／1.0 照旧）；键不存在时白色。fallback 测试字也跟色，
   仍 15pt。
5. **透明度修（两处同类 bug）**：(a) 药丸背景读
   `floatingLyric.cardOpacity`（设置页滑块一直在写，daemon 从没读过），
   每 tick 应用；键不存在时 0.75（Lee 现在看到的样子，不是滑块初值
   0.23），夹 0–1。(b) 歌词字读快照 `opacity`（`LyricSnapshot.opacity`，
   poll 与搜索／导入写入时已带），应用到 `_testLabel.alpha`，与颜色
   三档乘算（最终 alpha＝三档×opacity），缺省 1.0。快照解析在
   `TLDHUDLyricsSnapshot.mm`（`opacity`／`fontSize` 进
   `TLDHUDLyricsDisplay`，缺省 1.0／23.0，夹 0–1／14–36）。
6. **歌词简繁切换**：设置页歌词区段（与三滑块同区）分段选择器
   「歌词简繁」（简体／繁体，默认简体），新键 `lyric.displayScript`
   （"Hans"／"Hant"），写 App Group。转换**只在显示层**：
   - 主页面歌名／歌手渲染时转（`PlaybackDashboardView`）；
   - 应用内歌词行渲染时转（`InAppLyricsRenderer.currentDisplayText`）；
   - 药丸歌名行＋上下歌词行渲染时转（`TLDHUDLyricsSnapshot.mm`，
     每 tick 对四行显示字串应用转换）。
   - 快照里的 title／artist／lyrics[] 一律存 MediaRemote 原文：
     `stableSongIdentity`（换歌判定）与逐歌偏移键都从原文派生，
     LRCLIB 搜索与缓存键也用原文。**为什么不按字面“写快照前转换
     title／artist”**：`syncLiveLyricsAndProgress` 每 tick 用
     `stableSongIdentity(快照 title／artist)` 对
     `stableSongIdentity(MediaRemote 原文)`，快照里转了就对不上，
     字段型播放器歌词会卡住；daemon 的逐歌偏移键也从快照 title／
     artist 派生，同样会丢键。所以只转显示用的行文本，身份键保持原文。
   - 引擎：系统 ICU `CFStringTransform`（"Hant-Hans" 繁→简／
     "Hans-Hant" 简→繁），零依赖。已在本机系统 ICU 74.2（uconv）
     实测：夢→梦、煙→烟、劉→刘双向都对，" · " 等标点不动，已是目标
     字体的文本原样返回（幂等）；iOS 15 真机效果以 Lee 的设备测试为准。
     无歌 fallback 测试字（15pt）不转、不改字号。

版本：2.0.2／build 32（`LyricStore.versionTag`、两处 Info.plist
sed 精准改 CFBundleVersion 行、pbxproj MARKETING／CURRENT 各 ×6、
`TLDHUDVersion.h`、fallback 测试字、SettingsView 与 PiPLyricsRenderer
里的测试文字字串同步）。

## 4. 构建经过（5 个 run，4 次真失败＋1 次成功）

| run | HEAD | 结论 | 原因 |
|---|---|---|---|
| 46108648211 | 3e2e656（已作废） | failure | Archive 步编译错：`mutable` 是 C++ 关键字，`TLDHUDLyricsSnapshot.mm:112` 的 `NSMutableString *mutable` 在 .mm 里编不过。改名 `converted`，合进功能提交。 |
| 46109489987 | 25094ff | failure | Archive 步编译错：`'libproc.h' file not found`——ChatGPT 加的 import 在 iOS SDK 里没有。改前置声明（160581e）。 |
| 46109630838 | 160581e | failure | Archive 步链接错：`_proc_pidpath` 找不到——.mm 里 C 声明被 C++ 修饰。声明加 `extern "C"`（4d11918）。 |
| 46109741847 | 4d11918 | failure | Archive 步链接错：`_CGRectContainsPoint`／`_CGRectIsEmpty`／`_CGRectZero`——daemon target 不链 CoreGraphics，这三个是外部符号（CGPointMake 是 inline，不受影响）。hitTest 几何与 pillFrameInWindow 改手算（9b0ae60）。 |
| **46109882544** | **9b0ae60** | **success** | 头 run 一次成功（Archive＋签名＋打包＋上传全过）。 |

- 四次全是真失败（Build job 各走了 13 步，Archive 步挂），没有一
  次池子取消。另：轮询脚本第一版读错了字段——`gh_api.py run` 把
  HTTP 码放在 `status`、run 自身状态放在 `status_field`，第一版
  读 `status` 导致 46108648211 看似永远 in_progress（实际已 failure）；
  已改读 `status_field`，并用 jobs 接口核对结论。
- 每次失败都拉了 job 日志（`hidden_files/job_46109*.log`／
  `joblog-46108648211.txt`）再修，没有盲推。

## 5. 验包结果（`hidden_files/verify_2.0.2.py`，151 PASS、0 FAIL）

- IPA：`~/workspace/your_files/桌面歌詞-2.0.2-newbase.ipa`
  （1,726,849 B，SHA256 `7bdd3bfb05bdb43fe1c6c6718fa626c29dd0fbce3013d22af01ce3e4243497b5`）。
- dSYM：`~/workspace/your_files/桌面歌詞-2.0.2-newbase-dSYM.zip`
  （2,270,915 B，SHA256 `7c48f6bb2e53050f6bd61b936848e90a692a36de65abf2b2b691ea06c8c58537`）。
- 版本：App／Widget Info.plist 均为 **2.0.2／build 32**，包名
  `com.ycwl.Lyrics`，MinOS 15.0；三二进制 thin arm64（无 arm64e 混装），
  LC_CODE_SIGNATURE 三个都在位，ActivityKit 未链接。
- dSYM UUID 与二进制 LC_UUID 一字不差（3 对）：
  App `8ab357c831c83521bed402e334b92163`、
  Widget `24d000bc2f29311ebddf5b8d184170f3`（与 build 31 相同——Widget
  二进制没动）、daemon `6d867526866039a1a1c2a5a23bbbb67c`。
- 逃逸检查（`escape_check_count.py` 亲跑）：**App 仍为 2 个**，
  0x44A5C 崩点没回来；daemon 无逃逸检查符号。
- entitlements 与 build 31 逐项比对：**零差异**（App／Widget／daemon
  三路，key 集与值全一致，见验包日志差异表）。
- 字串在位（二进制）：`build 32`、`lyric.displayScript`、
  `Hant-Hans`、`悬浮歌词颜色`、`hudPill.positionLocked`、
  daemon 侧 `floatingLyric.textColorHex`／`floatingLyric.cardOpacity`／
  `lyric.displayScript`／`Hant-Hans`／`opacity`／`fontSize`／
  `refusing stale or unverified PID`；`build 31`／`2.0.1`／旧死标签
  「固定悬浮窗位置」「悬浮窗歌词颜色」不在二进制中；码值扫描 0 命中。
- 关于页日志行：**只做源码级断言**（`check_2.0.2.py` §14f：AboutView
  里无 `"日志"` 入口字串、无 `LogView()` 调用，四行都在；
  `LyricLogger` 照常写日志，主页面「查看守护进程日志」保留）。
  二进制不断言「日志」——它是「查看守护进程日志」的子串，裸子串查
  分不出来；二进制仍含「查看守护进程日志」（主页面入口保留）。
- 「固定位置」「歌词简繁」两个标签不在二进制字节扫描里：两个都是
  4 个汉字（12 字节 UTF-8），Swift 在 Release 下把 ≤15 字节的字串压
  成 small-string immediate 进代码段，字节扫不到（与 versionTag 注释
  里记过的同一效应；18 字节的「悬浮歌词颜色」进 __cstring，扫得到）。
  在位由源码级断言保证（`check_2.0.2.py` §13／§14b／§15），且与它们
  同处一个 HUD 区段函数体的「启用 HUD 守护进程」「悬浮歌词颜色」
  「hudPill.positionLocked」都在二进制里，说明这段 UI 代码进了包。
- 自检 `check_2.0.2.py`：**337 PASS、0 FAIL**（§1–§16，日志
  `hidden_files/check_2.0.2.log`；验包日志
  `hidden_files/verify_2.0.2.log`）。

## 6. 给 Lee 的真机测试清单（build 32）

1. **长按拖动**：放歌，药丸出来后长按药丸约半秒（药丸变半透明）→
   手指拖到新位置松手 → 药丸留在新位置（外观恢复）。
2. **锁屏解锁后还在新位置**：拖到新位置 → 锁屏 → 解锁 → 药丸还在
   新位置，歌词跟着歌走。
3. **停用再启用还在新位置**：主页面点「停用 HUD 守护进程」→ 药丸
   消失 → 再点启用 → 药丸回到上次拖到的新位置（不是回顶部中央）。
4. **固定位置**：主页面打开「固定位置」→ 长按药丸拖不动（药丸钉
   在原地，也不给半透明反馈）→ 关掉开关 → 又能长按拖动。
5. **歌词颜色**：主页面改「悬浮歌词颜色」→ 药丸歌词字变色（三档
   深浅照旧）；停用再启用后颜色还在。
6. **悬浮窗透明度**：设置页滑「悬浮窗透明度」→ 药丸底变透／变实
   （滑到 0 只剩歌词字）；歌词透明度滑块 → 歌词字变淡／变实。
7. **字体大小**：设置页滑「歌词字体大小」→ 药丸歌词字变大变小
   （当前行最大，歌名／上下行同比例小一圈）；无歌时的测试字不跟着变。
8. **简繁切换**：设置页切「歌词简繁」→ 简体：药丸与主页面歌词变简体
   （夢→梦）；切繁体：变回去。切歌、逐歌偏移、搜索不受影响。
9. **关于页**：关于页没有「日志」那行了，其余四行（作者、当前版本、
   加入官方群组、Telegram 频道）都在；主页面「查看守护进程日志」
   还能点开。
10. **底子回归**：启用／停用、重装免激活照常；切歌、暂停／续播照常；
    主页面启用与重装免激活回归照常；LC 模式下 HUD 区段只显示禁用说明。
11. 其余回归（2.0.0 清单）：五项歌词、10 次锁解、30 分钟后台。

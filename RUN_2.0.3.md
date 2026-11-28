# RUN_2.0.3 — 2.0.3/build 33

分支 `v2.0.3`，基线 9b0ae60（2.0.2/build 32）。HEAD `07d3c8a`
（完整 SHA `07d3c8a0b7dec1bfd8e6c6cf8c6c5599b1bbd806`）。

## 1. 分支与提交顺序

```
9b0ae60  2.0.2/build 32（药丸 hitTest 几何改手算）
07d3c8a  2.0.3/build 33：七项改动＋升版 32→33（HEAD，编出 IPA 的那笔）
```

- 分支不存在，先用 git-data API POST 建 ref（全 40 位 SHA
  `9b0ae60b85fe213e108af056bfd162658c33b885`，201），再 check 再推。
- 功能＋升版一笔提交（gh_push.py，`fast_forward_one_commit` → pushed，
  远程 ref 由 9b0ae60 移到 07d3c8a）。v2.0.2 与 main 一字未动。
- 本 RUN 文档另起一笔提交在最后（见 §5）。

## 2. 七项改动（07d3c8a，Lee 全定）

1. **药丸直接拖动 pan（替代 2.0.2 长按）**：`TLDHUDRootViewController.mm`，
   2.0.2 的长按在 Lee 真机上不触发（固定关了还是拖不动，停用再启用后
   还是一样），改回以前浮窗的做法——直接拖动。`UILongPressGestureRecognizer`
   整段拆掉（viewDidLoad 创建＋`handlePillLongPress:`＋类扩展声明），换成
   `UIPanGestureRecognizer`（target `handlePillPan:`，不设
   `minimumPressDuration`，默认一碰就触发）。Began：锁住记一行
   `hud: pill drag blocked (locked)` 后 return；否则 `_dragging=YES`、算
   `_dragTouchOffset`、`_pill.alpha=0.6`、记一行
   `hud: pill drag began (locked=NO)`。Changed：`movePillToCenter`＋
   `layoutIfNeeded`，只记首行（`_dragLogged` 标志，Began 时清零，记的是夹
   后的中心点）。Ended／Cancelled：`_dragging=NO`、alpha 回 1.0、
   `savePillPosition`、记一行 ended／cancelled（含保存的中心点）。
   复用 2.0.2 现成的 `movePillToCenter`／`savePillPosition`／
   `clampedPillCenterForCenter`／`readPositionLocked`／每秒 tick 重读锁，
   没重写。hitTest 里不记日志（全屏窗口每触必调，会刷屏）。注释里的
   Long-press 字样同步改成 pan／直接拖动。
2. **歌卡／药丸藏掉歌名 · 歌手身份行，只留歌词**：主页面歌卡
   `PlaybackDashboardView.swift` 里下行 `bottomText` 那个 Text 整行删掉
   （`let bottomText` 一并撤掉，免得留个没人用的变量），上行歌词行
   `topText`（大字）、PLAYING、「进度」行（当时还在，后由第 6 项藏掉）
   不动。HUD 药丸 `updateDisplay` 里 `songAttrs` 字典＋
   `if (lyrics.songLine.length > 0)` 追加块整段撤掉，只留 previous／
   current／next 三行；0.65 那档 alpha 随 `songAttrs` 一起撤掉（现两档
   0.45／1.0）。无歌 fallback 测试字保留。快照不动：
   `TLDHUDLyricsSnapshot.mm` 里 songLine／track／artist 构造照常（搜索、
   逐歌偏移、歌识别继续用原文）；`LyricStore` 快照写入不动；2.0.2 简繁
   转换接线不动（它转的是显示字串，藏掉的行本来也不显示）。LC 模式应用
   内歌词区、小组件、关于页都不动。
3. **主页面 HUD 两个大按键改一个开关**：`PlaybackDashboardView.swift`
   HUD 区段里「启用 HUD 守护进程」（紫色）／「停用 HUD 守护进程」（灰色）
   两个 Button 整段撤掉，换成一个 `Toggle("启用悬浮歌词", isOn:
   hudEnabledToggle)`。开关状态跟守护进程真实状态一致，不只记上次点的：
   `hudEnabledToggle` 是 Binding，get 读 `@State hudRunning`，set 调
   `setHUDEnabled(newValue)`（走原来按钮那套后台队列＋`hudBusy` 防连点＋
   完事 `refreshHUDStatus()`）。没用 @AppStorage 存偏好值当开关状态（那
   就是旧死开关的毛病），也没复用 `floatingLyric.enabled` 死键。进页面
   显示真实状态：Toggle 所在区段出现时 onAppear 刷新一次；body 每 0.25s
   重建不调 -check（那样太贵）。状态行（运行中／未运行＋pid）由第 4 项
   藏掉；「固定位置」Toggle、悬浮歌词颜色取色器、说明文字（后由第 7 项
   藏掉）、查看守护进程日志链接不动；LC 分支（只显示禁用说明，绝不调
   SetHUDEnabled）不动。
4. **主页面 HUD 状态行藏掉**：`Text("守护进程状态")`＋`Text(hudStatusText)`
   那行 HStack 整行藏掉，开关本身就表示开／关。状态逻辑没一起删：
   `refreshHUDStatus()` 保留，简化成只更新 `hudRunning`
   （`hudRunning = TLDHUDIsEnabled()`，供 Toggle 绑定读）；读 PID 文件
   只为显示 pid，显示没了随行删掉；`hudStatusText` @State 随行清理。
   日志不动：守护进程日志里照常记 pid（主页面「查看守护进程日志」里能
   看到）；`HUDLogView` 不动。
5. **主页面 HUD 区段标题藏掉**：`Text("悬浮歌词（HUD 守护进程）")`
   那行整行藏掉，开关、固定位置、颜色、说明文字（后由第 7 项藏掉）都留着。
6. **歌卡进度行藏掉**：`Text("进度：\(Int(state.position)) 秒")` 那行整行
   藏掉；歌词行（topText）与 PLAYING 状态行不动。只改显示，
   `coordinator.state` 的 position 照常更新、不动。只藏歌卡里这一行，
   文件别处没有其他进度显示，没顺手多藏。
7. **主页面 HUD 区段说明文字藏掉**：`Text("启用后歌词药丸显示在桌面与其它
   App 之上，锁屏解锁后仍在跟；停用后药丸消失。每次启用都会重写 daemon
   配置（重装后容器路径变了也不怕）。")` 整段藏掉。区段只剩三行：悬浮
   歌词开关、固定位置、悬浮歌词颜色（＋保留的「查看守护进程日志」链接）。
   「查看守护进程日志」链接保留不动——Lee 定过主页面查看守护进程日志要
   留着（关于页日志行就是因为它才删的）。

版本：2.0.3／build 33（`LyricStore.versionTag`、两处 Info.plist
sed 精准改版本行、pbxproj MARKETING／CURRENT 各 ×6、`TLDHUDVersion.h`、
fallback 测试字、SettingsView 与 PiPLyricsRenderer 里的测试文字字串、
build.yml 产物名 `桌面歌词-2.0.3(.ipa／-dSYM.zip)` 同步）。

## 3. 构建经过（1 个 run，头 run 一次成功）

| run | HEAD | 结论 | 原因 |
|---|---|---|---|
| **46111489002** | **07d3c8a** | **success** | 头 run 一次成功（Archive＋签名＋打包＋上传全过）。Build job success，13 步。 |

- 没有池子取消，没有真失败。轮询读 `status_field`／`conclusion`（2.0.2
  的教训：不读 HTTP status），并用 jobs 接口核对 Build 结论。

## 4. 验包结果（`hidden_files/verify_2.0.3.py`，160 PASS、0 FAIL）

- IPA：`~/workspace/your_files/桌面歌詞-2.0.3-newbase.ipa`
  （1,722,817 B，SHA256 `494900a7da4fd17edef0edfb4213be93f45104eb567cbbbf176e580394ddac3c`）。
- dSYM：`~/workspace/your_files/桌面歌詞-2.0.3-newbase-dSYM.zip`
  （2,263,964 B，SHA256 `6f39dfcfd0b40c86100785801a66801c9b5d9c8d97070c2251197d9e230d4ac1`）。
  （下载的 artifact 外层 zip 里各包着一个同名内层文件，拆出来才是真正的
  IPA／dSYM——与 2.0.2 的 outer-*.zip 做法一致。）
- 版本：App／Widget Info.plist 均为 **2.0.3／build 33**，包名
  `com.ycwl.Lyrics`，MinOS 15.0；三二进制 thin arm64（无 arm64e 混装），
  LC_CODE_SIGNATURE 三个都在位，ActivityKit 未链接。
- dSYM UUID 与二进制 LC_UUID 一字不差（3 对）：
  App `5910dd69f3d73c64b6caa5c6df155aca`、
  Widget `24d000bc2f29311ebddf5b8d184170f3`（与 build 32 相同——Widget
  二进制没动）、daemon `6057a852d9c53d0c95c905e46763837a`。
- 逃逸检查（`escape_check_count.py` 亲跑）：**App 仍为 2 个**，
  0x44A5C 崩点没回来；daemon 无逃逸检查符号。
- entitlements 与 build 32 逐项比对：**零差异**（App／Widget／daemon
  三路，key 集与值全一致，见验包日志差异表）。
- 字串在位（二进制）：`2.0.3`、`build 33`、daemon 侧
  `hud: pill drag began`／`hud: pill drag blocked`／
  `hud: pill drag changed`／`saved centre`／`handlePillPan`、
  App 侧 `启用悬浮歌词`；`UILongPressGestureRecognizer`／
  `handlePillLongPress`／`build 32`／`2.0.2` 测试文字不在二进制中；
  码值扫描 0 命中。
- 没断言二进制里无「启用 HUD 守护进程」／「停用 HUD 守护进程」／
  「守护进程状态」／「悬浮歌词（HUD 守护进程）」——SettingsView 死页面
  里还有这些字串且照常编进包，二进制断言会误报（check_2.0.3.py §14h
  与 verify 注释里记了原因）；主页面源码级断言在位（§13／§14h／§14j）。
  同理「进度」也不断言二进制缺失。
- 自检 `check_2.0.3.py`：**365 PASS、0 FAIL**（§1–§16，日志
  `hidden_files/check_2.0.3.log`；验包日志
  `hidden_files/verify_2.0.3.log`）。自检里修过两处 2.0.2 脚本留下的
  坑：Info.plist build 断言曾写死 `== "32"`（已改 33）；§14c 颜色三档
  断言随 songLine 撤掉 0.65 档改成两档。

## 5. 给 Lee 的真机测试清单（build 33）

1. **直接拖药丸**：放歌，药丸出来后直接按住药丸拖（不用长按等半秒）
   → 药丸跟手走，松手留在新位置（拖动时半透明，松手恢复）。
2. **锁屏解锁后还在新位置**：拖到新位置 → 锁屏 → 解锁 → 药丸还在
   新位置，歌词跟着歌走。
3. **停用再启用还在新位置**：主页面开关关掉 → 药丸消失 → 再打开 →
   药丸回到上次拖到的新位置（不是回顶部中央）。
4. **固定位置**：主页面打开「固定位置」→ 直接拖药丸拖不动（药丸钉
   在原地）→ 关掉开关 → 又能直接拖动。拖动被挡时主页面「查看守护进程
   日志」里有一行 `hud: pill drag blocked (locked)`；正常拖动有
   `hud: pill drag began`／`changed`／`ended` 行。
5. **只剩歌词**：歌卡和药丸都只剩歌词行，看不到「歌名 · 歌手」那行
   （例如「附送折磨 · 洋洋」）；换歌／暂停续播／逐歌偏移不受影响。
6. **HUD 一个开关**：开关开 → 药丸出来；开关关 → 药丸消失。重装后
   打开页面，开关状态与实际一致（开着就是开着，不用再点一次）。
7. **主页面 HUD 区段**：看不到「悬浮歌词（HUD 守护进程）」标题、看不到
   运行中／pid 状态行、看不到那段说明文字；只剩悬浮歌词开关、固定位置、
   悬浮歌词颜色三行＋「查看守护进程日志」链接。日志里仍有 pid。
8. **歌卡**：看不到「进度：N 秒」那行，只剩歌词行和 PLAYING；歌词跟随
   和播放状态不受影响。
9. **其余回归**：颜色、透明度、字体大小、简繁切换、重装免激活；五项歌词、
   10 次锁解、30 分钟后台。

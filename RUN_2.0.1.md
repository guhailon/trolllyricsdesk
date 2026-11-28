# RUN_2.0.1 — TrollLyricsDesk 2.0.1 / build 30

两项改动：① Keychain 激活持久化（重装免激活，主任务）；② 主页面死开关整组藏掉
（Lee 2.0.0 真机踩坑追加）。基线 2.0.0 HEAD d30f2c4（分支 v2.0-hud），
新分支 v2.0.1，代码提交 c6340d0，本文档另提交。不上源、不发 Telegram。

## 1. 改动（相对 d30f2c4，15 文件，+760/−96）

### 1.1 Keychain 激活持久化（主任务）

- **新文件 `App/ActivationKeychain.swift`（93 行，import Security）**：
  generic password，service = App 自身标识 `com.ycwl.Lyrics`，account 固定为
  激活标记键 `tld.activated`，value 存激活类型（`"master"`／`"code"`，不是码值）。
  三个静默接口：`read()`（有标记返回类型、无返回 nil、任何失败返回 nil）、
  `write(type)`（SecItemAdd，已存在则 SecItemUpdate，失败静默）、
  `syncWithDefaults()`（UserDefaults 已激活＋Keychain 为空 → 补写；
  UserDefaults 未激活＋Keychain 有标记 → 写回 UserDefaults 恢复；两边一致不动）。
  全部调用失败一律静默忽略、绝不抛错、绝不崩溃、不记任何日志。
  注释写明依据与局限：iOS Keychain item 在删 App 后仍保留，同一签名身份
  （同一 access group／同一 Team＋bundle 种子）下重装可读，这是方案成立的前提；
  若重装时签名身份变了，旧 Keychain 可能读不到，届时仍需重新激活一次。
  `kSecAttrAccessibleAfterFirstUnlock`（后台拉起也能读写）；不同步 iCloud
  （无 `kSecAttrSynchronizable`）；无自定义 access group，不新增 entitlements。
- **`App/TrollLyricsDeskApp.swift`：`makeRootViewController()` 内**、
  构造 `ActivationGateView` 之前调一次 `ActivationKeychain.syncWithDefaults()`。
  为什么这个位置够早：Gate 的 `@AppStorage` 在视图构造／求值时读
  `tld.activated`，这里是读数前最后一个关口，不依赖 AppDelegate 与
  SceneDelegate 的调用顺序；`didFinishLaunching`（`start()`）虽然更早，
  但一旦调用顺序变了就不再保证。sync 是幂等的，场景重连再调一次无害。
- **`App/ActivationView.swift`：`activate()` 内**，`markActivated(type:)`
  下一行同步调 `ActivationKeychain.write(type)`。
  故意不放进 `markActivated` 本体：它在 `Lyrics/LyricStore.swift` 里，
  Widget target 也编那份文件，而 `ActivationKeychain.swift` 只在 App target，
  写进去会断 Widget 编译（自检 §11 有断言守着）。
- 不改服务端、不改 daemon／快照／锁屏逻辑；LC 宿主模式只 try 不报错
  （defaults 走 `.standard`，Keychain 读写失败静默跳过）。

### 1.2 主页面死开关整组藏掉（追加，Lee 2.0.0 真机踩坑）

- `App/PlaybackDashboardView.swift`：非 LC 分支里整组藏掉——
  「显示悬浮歌词窗」Toggle（`floatingLyric.enabled`）、
  「固定悬浮窗位置」Toggle（`floatingLyric.positionLocked`）、
  「悬浮窗歌词颜色」取色器（`floatingLyric.textColorHex`）、
  旧提示「悬浮窗口 · 长按拖动 · 双击隐藏」。
- 查证结论（写在代码注释里）：三样管的都是已死的 FrontBoard 悬浮窗，
  唯一消费方是 `Overlay/FloatingLyricViewController.swift`
  （读 `floatingLyric.enabled` 控显隐、`positionLocked` 控拖动、
  `textColorHex` 控颜色）；2.0.0 起 `TLDSFrontBoardOverlayDisabled = YES`
  把整条路关掉，VC 只在 `TLDSSceneDelegate` 已死分支里实例化；
  HUD 药丸不读 `textColorHex`（快照只有透明度／字号）。
  所以「固定悬浮窗位置」同样已死，一并藏掉；取色器同理（同簇第三个死控件，
  留着 Lee 调了颜色药丸也不会变）。
- 只改 UI 呈现：三个存储键、`@AppStorage` 声明、`syncFloatingEnabled()`
  一律不动。原位置改为一句说明：
  「悬浮歌词药丸只从设置页「悬浮歌词（HUD 守护进程）」里启用打开」。
- 已知残留（非界面，不影响）：`FloatingLyricViewController.swift:206`
  的诊断日志字串仍提到「显示悬浮歌词窗」，死代码本体保留在源码里，
  字串仍在二进制中，仅日志可见，主页面已无此开关。

### 1.3 升版 2.0.0/29 → 2.0.1/30

- 两处 Info.plist：`CFBundleShortVersionString` 2.0.1、`CFBundleVersion` 30
  （sed 精准改 20／22 行，未用 plistlib 重写）。
- `Lyrics/LyricStore.swift`：`versionTag = "build 30（2.0.1）"`（33 行），
  测试文字 `悬浮测试 · 桌面歌词 2.0.1`（420 行）。
- `project.pbxproj`：`MARKETING_VERSION = 2.0.1` ×6、
  `CURRENT_PROJECT_VERSION = 30` ×6；新文件手工加 file reference
  `2623F61B31953B42913FCE72`＋build file `537A01F5F1D42E0B24658D2C`，
  进 App group 与 App target Sources phase（紧跟 ActivationView 条目后）。
  核对：大括号平衡、引用皆有定义（除已知旧 dangling
  `2AC9C558E40544F86D76B6FD`）、App Sources 相对 HEAD 只多这一个文件、
  Resources 与 HEAD 一致（自检 §7b）。
- 用户可见版本字串同步：`HUD/TLDHUDVersion.h`（2.0.1／30）、
  `HUD/TLDHUDRootViewController.mm` 兜底文字、
  `Renderer/PiPLyricsRenderer.swift` 测试文字、`App/SettingsView.swift`
  测试文字说明与 HUD 区段标题、`HUD/TLDHUDDaemonMain.mm` 文件头注释。
  「2.0.0：」开头的历史注释（FrontBoard 停用等）一律未动。
- `.github/workflows/build.yml`：产物名 2.0.0 → 2.0.1
  （`桌面歌词-2.0.1.ipa`／`-dSYM.zip`，13 处＋标题）；
  「2.0.0/build 29 起」历史注释保留。
- 新自检 `check_2.0.1.py`（以 `check_2.0.0.py` 为底，基线 d30f2c4，
  版本改 2.0.1/30，加 §11 Keychain 与 §12 死开关断言）。

## 2. 构建经过

- 分支：`git checkout -b v2.0.1 d30f2c4`；代码提交
  `c6340d005becdd4579548f150984a9b96a3f2466`（15 文件）。
- 远端分支：git-data API POST 建 ref（201），
  `refs/heads/v2.0.1` → 全 40 位 `d30f2c45e1dcfbe31879be14fd31b29d981408a5`；
  再 `gh_push.py push guhailon/trolllyricsdesk . v2.0.1 v2.0.1`：
  check `fast_forward_one_commit`（缺 15 blobs／9 trees），push 结果
  `pushed`，remote_after `c6340d0`。未碰 main、未 force-push。
- 头 run **46106202724**（head c6340d0）：轮询 `hidden_files/poll_2.0.1.py`，
  round 1–2 in_progress，round 3 completed **success**，0 rerun，
  无池子取消（job "Build" 一次跑成）。
- 本地自检 `check_2.0.1.py`：**235 PASS、0 FAIL**（提交前亲跑；
  中途修过 4 个自检脚本本身的 bug，全是断言写法问题：
  注释里的 "try"、注释里的 "ActivationGateView"、旧注释里的 "双击隐藏"、
  未提交时 diff 为 0——代码本身无问题）。
- 注意：本文档提交再推一次会触发同代码的第二次 run（仅文档差别），
  不是交付 run；交付以 46106202724 为准。

## 3. 验包结果（独立亲验，`hidden_files/verify_2.0.1.py`）

- IPA：`桌面歌词-2.0.1.ipa`，**1,712,576 B**，
  SHA256 `f099361ec30d44203b6091c59193937eef27ec5b8d30baaa774809805f98b855`。
  交付路径：`~/workspace/your_files/桌面歌詞-2.0.1-newbase.ipa`
  （SHA 与上同）；dSYM：`~/workspace/your_files/桌面歌詞-2.0.1-newbase-dSYM.zip`
  （2,240,090 B，SHA256 `538cddab5980ec4e1e023bdaabcf38ca17075449e5bdd5da1abafdbc0e57b021`）。
- 版本：App／Widget Info.plist 均为 **2.0.1／build 30**，包名
  `com.ycwl.Lyrics`，MinOS 15.0；三二进制 thin arm64（无 arm64e 混装），
  LC_CODE_SIGNATURE 三个都在位，ActivityKit 未链接。
- dSYM UUID 与二进制 LC_UUID 一字不差（3 对）：
  App `436d3e5e78b03c6c94673f11cbd7a001`、
  Widget `24d000bc2f29311ebddf5b8d184170f3`、
  daemon `e17f9a51d8893d10bc3e24d22a3bbec4`。
- 逃逸检查（`escape_check_count.py` 亲跑）：**App 仍为 2 个**，
  与 2.0.0 基线地址完全相同（site `0x10000d02c`／`0x10000d064`，
  同属 function `0x10000cf88`），0x44A5C 崩点没回来。
  （中途：这台机缺 `capstone` 模块致验包脚本该项空跑 FAIL，
  `pip3 install --break-system-packages capstone` 装 5.0.9 后重跑通过；
  是环境缺模块，不是包的问题。）
- entitlements 与 2.0.0 逐项比对：**零差异**（App 34 键、Widget 1 键、
  daemon 30 键，key 集与值全一致，见验包脚本输出的差异表）。
- `verify_2.0.1.py`：**128 PASS、0 FAIL**。
  其中：Keychain 类型名 `ActivationKeychain` 与新说明字串
  「悬浮歌词药丸只从设置页」在二进制在位；死标签
  「固定悬浮窗位置」「悬浮窗歌词颜色」与旧测试文字
  「悬浮测试 · 桌面歌词 2.0.0」不在二进制中；码值扫描 0 命中；
  旧 widget token（38473）0 命中。
- 自检 `check_2.0.1.py`：235 PASS、0 FAIL。

## 4. 给 Lee 的真机测试清单

1. **重装免激活（主任务）**：全新安装 2.0.1 → 输入激活码激活一次 →
   确认进主界面 → 删 App → 重装 2.0.1 → **不应再弹激活页**，直接进主界面。
2. **覆盖升级路径**：已激活的 2.0.0 直接覆盖安装 2.0.1 → 不应弹激活页；
   之后再删 App 重装 2.0.1 → 也不应弹激活页（首次进 2.0.1 时已把标记补进 Keychain）。
3. **主页面无假开关**：主页面不应再有「显示悬浮歌词窗」「固定悬浮窗位置」
   开关与颜色取色器；只有一句「悬浮歌词药丸只从设置页……」说明。
4. **药丸只从设置页开**：设置页「悬浮歌词（HUD 守护进程）」→ 启用，
   药丸出现跟歌；停用后药丸消失。
5. **LC 模式不受影响**：LiveContainer 机上照常应用内歌词，无 daemon、
   无激活行为变化（LC 下首次仍需激活一次，之后同走 Keychain 恢复）。
6. 其余回归（2.0.0 清单）：Enable／stale-plist 回归、五项歌词、
   10 次锁解、30 分钟后台。
7. 若重装后仍弹激活页：先确认两次安装的签名方式是否一致（换签名会读不到
   旧 Keychain，见 §1.1 局限），再报奴才。

---

# 5. build 31（HUD Enable 放主页面，Lee 定）

Lee 2026-11-28 12:16 改放主页面，覆盖「放 ContentView」的要求：HUD 启用
放到主页面（PlaybackDashboardView，App 首页「桌面歌词」那页），不要放
ContentView 设置页。原因：Lee 视频证明他从主页面点齿轮 → 设置中心 →
「设置」看到的是 ContentView，滑到底也没有 HUD 区段；而 SettingsView
从未被实例化（全工程 grep「SettingsView(」零命中），HUD 区段放在那里
用户根本进不去。Lee 要的是打开 App 第一眼就能点启用。

## 5.1 改动（相对 c6340d0，7 文件，+765/−21）

- **`App/PlaybackDashboardView.swift`**：build 30 在死开关原位置留的那句
  说明「悬浮歌词药丸只从设置页「悬浮歌词（HUD 守护进程）」里启用打开」
  整句撤下，换成真正能用的 HUD 区段（死开关原位置，非 LC 分支内）：
  标题「悬浮歌词（HUD 守护进程）」＋状态行（守护进程状态：运行中（pid
  N）／未运行，绿／红）＋「启用 HUD 守护进程」／「停用 HUD 守护进程」
  按钮＋「查看守护进程日志」（NavigationLink → HUDLogView，主页面在
  NavigationView 里，可用）＋启用说明文案。调用与文案复用
  SettingsView.swift:322 的现成写法（TLDHUDSetEnabled／TLDHUDIsEnabled／
  TLDHUDPIDPath／TLDHUDLogMessage，Enable／Disable 走后台队列，不卡 UI），
  不重写 daemon 逻辑。新增 @State 三件（hudStatusText／hudRunning／
  hudBusy）＋refreshHUDStatus()（SettingsView:462 同款，-check 为准，
  PID 文件只用来显示 pid）。LC 分支内只显示禁用说明，绝不调
  SetHUDEnabled（沿用 SettingsView:317-324 的判定）。
- **不动**：SettingsView 死页面（HUD 区段仍在原处，未删未改）；
  ContentView（HUD 没放设置页——本版中途一度已改 ContentView，Lee 改令
  后用 `git checkout -- App/ContentView.swift` 整文件撤回，diff 里无它）；
  死开关三键的 @AppStorage 声明与存储键（只改 UI 呈现）；FrontBoard
  老路（仍关着）；锁屏歌词（不恢复）；Keychain 激活持久化（build 30
  原样保留）；不新增 entitlements；不记码值。
- **升版 2.0.1/build 30 → build 31**：两处源码 Info.plist
  CFBundleVersion 30→31（sed 精准改字面量，未用 plistlib 重写）；
  `Lyrics/LyricStore.swift` versionTag = "build 31（2.0.1）"；
  pbxproj CURRENT_PROJECT_VERSION = 31 ×6；`HUD/TLDHUDVersion.h`
  build 30→31（注释＋#define＋twin 注释）。MARKETING_VERSION 仍 2.0.1。
- 新自检 `check_2.0.1_b31.py`（以 `check_2.0.1.py` 为底，基线 c6340d0，
  版本改 31，加 §13 主页面 HUD 断言：HUD 文案／调用／@State 三件／
  LC 禁用说明／ContentView 未动／SettingsView 未动且仍无实例化／
  旧说明已撤下；§12「药丸只从设置页开的说明」断言改为「已撤下」）；
  新验包 `hidden_files/verify_2.0.1_b31.py`（基线改 build 30 的包，
  entitlements 与 build 30 逐项比对，加「启用／停用 HUD」「查看守护进程
  日志」在位断言、「build 30」不在位断言）。

## 5.2 构建经过

- 分支 v2.0.1（不建新分支，不动 v2.0-hud 与任何 main）；代码提交
  `cf78428`（7 文件）。
- 推送：`gh_push.py push guhailon/trolllyricsdesk . v2.0.1 v2.0.1`，
  check `fast_forward_one_commit`（缺 7 blobs／6 trees），push 结果
  `pushed`，remote_after `cf78428`。未碰 main、未 force-push。
- 头 run **46106989203**（head cf78428）：轮询
  `hidden_files/poll_2.0.1_b31.py`，round 1 in_progress，round 2
  completed **success**，0 rerun，无池子取消（job "Build" 一次跑成）。
- 本地自检 `check_2.0.1_b31.py`：**259 PASS、0 FAIL**（提交前亲跑；
  中途修过 3 个自检断言本身：源码 Info.plist 字面量 30→31 漏改、
  App Sources 断言的基线已含 ActivationKeychain——代码本身无问题）。
- 注意：本文档提交再推一次会触发同代码的第二次 run（仅文档差别），
  不是交付 run；交付以 46106989203 为准。

## 5.3 验包结果（独立亲验，`hidden_files/verify_2.0.1_b31.py`，131 PASS、0 FAIL）

- IPA：`桌面歌词-2.0.1.ipa`，**1,719,223 B**，
  SHA256 `380e200d7c376dc5a087619bc221482bc76bf208200b4867ed51963436b71fb3`。
  交付路径：`~/workspace/your_files/桌面歌詞-2.0.1-newbase.ipa`
  （SHA 与上同）；dSYM：`~/workspace/your_files/桌面歌詞-2.0.1-newbase-dSYM.zip`
  （2,254,912 B，SHA256 `0123e54b4856db95006f171d3899d064eb24371c9ec1fd6c101eda323bf9bf18`）。
  build 30 的旧包已改名留档（`桌面歌詞-2.0.1-build30-newbase.ipa`／`-dSYM.zip`）。
  （下载小插曲：gh_api.py download-artifact 下来的是 artifact 外层 zip，
  里面才是真正的 IPA／dSYM zip——解开一层后才是上列大小与 SHA；外层 zip
  留在 `hidden_files/artifact-2.0.1-b31/*.outerzip` 备查。）
- 版本：App／Widget Info.plist 均为 **2.0.1／build 31**，包名
  `com.ycwl.Lyrics`，MinOS 15.0；三二进制 thin arm64（无 arm64e 混装），
  LC_CODE_SIGNATURE 三个都在位，ActivityKit 未链接。
- dSYM UUID 与二进制 LC_UUID 一字不差（3 对）：
  App `8a4731d5c6e437aa83a72b4bd31b5f2d`、
  Widget `24d000bc2f29311ebddf5b8d184170f3`、
  daemon `91853923b9b337edb1f570f4d80641a0`。
- 逃逸检查（`escape_check_count.py` 亲跑）：**App 仍为 2 个**，
  0x44A5C 崩点没回来；daemon 无逃逸检查符号。
- entitlements 与 build 30 逐项比对：**零差异**（App／Widget／daemon
  三路，key 集与值全一致，见验包日志差异表）。
- 主页面 HUD 在位：二进制含「启用 HUD 守护进程」「停用 HUD 守护进程」
  「查看守护进程日志」「悬浮歌词（HUD 守护进程）」；旧说明
  「悬浮歌词药丸只从设置页」不在二进制中；「build 30」不在二进制中；
  死标签「固定悬浮窗位置」「悬浮窗歌词颜色」不在二进制中；码值扫描 0 命中。
- 自检 `check_2.0.1_b31.py`：259 PASS、0 FAIL。

## 5.4 给 Lee 的真机测试清单（build 31）

1. **主页面点启用 HUD（第一步）**：删旧版装 2.0.1/build 31 → 打开 App，
   主页面「桌面歌词」那页直接就能看到「悬浮歌词（HUD 守护进程）」区段
   → 点「启用 HUD 守护进程」→ 状态变「运行中（pid …）」→ 主屏幕药丸
   出来跟歌词。**不用再进设置页找。**
2. **锁屏解锁后药丸还在跟**：放歌 → 锁屏 → 解锁 → 药丸还在主屏幕上，
   歌词跟着歌走（这是最初 11:55 未结案的那件）。
3. **停用**：主页面点「停用 HUD 守护进程」→ 药丸消失；再启用 → 药丸回来。
4. **查看守护进程日志**：主页面点「查看守护进程日志」，能看到 daemon 日志。
5. **重装免激活（build 30 主任务，回归）**：全新安装激活一次 → 删 App →
   重装 → 不应再弹激活页。
6. **主页面无假开关（回归）**：不应再有「显示悬浮歌词窗」「固定悬浮窗
   位置」开关与颜色取色器，也不应再有「药丸只从设置页开」那句说明。
7. **LC 模式不受影响**：LiveContainer 机上主页面 HUD 区段只显示禁用说明，
   点不到启用，应用内歌词照常。
8. 其余回归（2.0.0 清单）：五项歌词、10 次锁解、30 分钟后台。

# RUN_compat-test.md — TrollLyricsDesk 兼容补丁测试版（2.0.2/build 90）

Lee 批准：把 ChatGPT.zip 里另外 20 处改动单独编一个测试版，真机测一圈。
与主线完全分开：2.0.2/build 32（好用的版本）不动，2.0.3（直接拖动）在另一条分支上做。
不上源、不发频道。

## §1 基线与范围

- 基线：cf78428（2.0.1/build 31 代码提交）。
- ChatGPT.zip（`~/workspace/user/files/ChatGPT.zip`，1,179,402 B）相对 cf78428 共 **23 处不同**：
  3 处底子（HUD/TLDHUDDaemonMain.mm、HUD/TLDHUDHelper.mm、HUD/TLDHUDVersion.h，
  已进 2.0.2）＋另 19 个文件＋RUN_2.0.2.md 新文件。
- 另 20 处是 ChatGPT 自称的 "first compatibility patch"：HUD 退出状态校验、PID 可执行路径检查、
  过期 plist 防加载、正面证据 HUD UI 门控（`RuntimeEnvironment.canUseNativeHUD`）、未知环境
  fail-closed、Apple Music 仅播放时兜底、按 bundle-ID 分类、单调播放外推、可选增强 LRC 词级
  timing 模型（`LyricWord`／`activeWord`）、生成守卫、降低空闲轮询／写入、激活类型 allowlist
 （`["master", "code"].contains(type)`）、诊断权限按钮、CI 回归步骤（Engine regression tests）。
- ChatGPT 自己写明：没用 Xcode／iOS SDK 编过、没签名、没真机测过；未知环境 fail-closed
  「including possible misclassified TrollStore installs」。
- 本测试版把 23 处**原样**搬进来（RUN_2.0.2.md 只作参考留档，不是交付文档），再升版到
  2.0.2/build 90 以便与主线区分。

## §2 分支与提交（分支 `compat-test`）

| 提交 | 内容 |
|---|---|
| `3511e6a` | 原样并入 ChatGPT.zip 全部 23 处改动（23 文件，+242/−76） |
| `6d4d211` | 版本 2.0.2/build 90＋自检 `check_compat-test.py` |
| `1ff0d6f` | 编译修复：libproc.h 不在 iOS SDK——proc_pidpath 前向声明（行为不变） |
| `dd3301c` | 编译修复：proc_pidpath 声明加 `extern "C"` |
| （本文档） | RUN_compat-test.md（文档-only 提交，见 §6） |

- 工作区：`~/workspace/trolllyricsdesk-compat-test`（独立 worktree；`trolllyricsdesk-newbase`
  的 2.0.3 在途工作未碰）。
- 远端分支用 git-data API POST 建 ref（201，建在 cf78428 上），两笔提交逐笔经
  `gh_push.py check`（fast_forward_one_commit）后推送；修复提交同款。

## §3 自检（`check_compat-test.py`，以 `check_2.0.1_b31.py` 为底）

- 本地跑过：**268 PASS／0 FAIL**（OPEN 6，皆为 macOS／真机项）。
- 改动点：BASE 改 cf78428；版本断言 2.0.2/build 90（Info.plist、versionTag、testText、
  TLDHUDVersion.h、pbxproj ×6）；build.yml 档名断言改 2.0.2；§5/§13 三处旧文案按补丁的
  正面证据门控改断言（`LiveContainer 模式下不可用`→`当前环境未确认具备原生 HUD 权限`，
  `LiveContainer · 应用内歌词模式`→`兼容环境 · 应用内歌词模式`）；diff 集合断言改为
  精确集合（含未追踪文件）；新增 §14 补丁标记断言（OwnPID、WIFEXITED、status == 1、
  canUseNativeHUD、LyricWord、激活 allowlist、CI 回归步骤）。
- 门控逻辑（`Compatibility/RuntimeEnvironment.swift:76`）：
  `canUseNativeHUD = !isLiveContainer && installEnvironment == "trollstore"`；
  `preferredEngine` 里 "native-candidate" 不再走 nativeHUD，改为 .inApp。

## §4 构建经过

| 尝试 | Run | HEAD | 结论 |
|---|---|---|---|
| 1 | 46111260146 | 6d4d211 | failure——真失败（Archive unsigned 步骤失败，job "Build" 跑了 14 步，非池子取消） |
| 2 | 46111514648 | 1ff0d6f | failure——真失败（同上，链接错） |
| 3 | **46111727732** | **dd3301c** | **success**（0 池子取消） |

编译修复（只许最小编译修复，均在 `HUD/TLDHUDDaemonMain.mm` 一个文件，行为逻辑一字未动）：
1. ChatGPT 新增的 `TLDHUDOwnPID` 用了 `#import <libproc.h>`，iOS SDK 里没有（只在 macOS
   SDK 有）→ `fatal error: 'libproc.h' file not found`（run 46111260146）。
   修法：删 import，改前向声明 `extern int proc_pidpath(int, void*, uint32_t)`＋补
   `PROC_PIDPATHINFO_MAXSIZE=4096`（与头文件同一签名）。
2. 上修引发链接错——`.mm` 是 C++ 编译，无 `extern "C"` 的声明按 C++ 修饰名链接，
   `Undefined symbols: proc_pidpath`（run 46111514648）。修法：声明包进 `extern "C"` 守卫。
两次修后自检仍是 268 PASS／0 FAIL。

## §5 交付物与独立验包

- IPA：`~/workspace/your_files/桌面歌詞-2.0.2-compat-test.ipa`——**1,730,882 B，
  SHA256 `9f44c0fb23e2350e87ef161a0a26ea6cc4f1460d9951590ac15889974785004c`**
- dSYM：`~/workspace/your_files/桌面歌詞-2.0.2-compat-test-dSYM.zip`——2,281,334 B，
  SHA256 `8ee9549e82a2d5b55deca16a0d3cb35cd15ae7d48764db179d8b4b05639cbe18`
- 原 2.0.2 的包未被覆盖（`桌面歌詞-2.0.2-newbase.ipa` 时间戳 04:59 未动）。
- 验包脚本：`hidden_files/verify_compat-test.py`（以 newbase 的 `verify_2.0.1_b31.py` 为底改写），
  日志在 `hidden_files/artifact-compat-test/verify-compat-test.log`：**145 PASS／0 FAIL**
  （初版 144 PASS／1 FAIL：继承自 b31 的旧检查 `LiveContainer 模式下不可用`——查 diff 证实是
  补丁本身换了文案，已把该检查改为验新句并注明原因，重跑后 145 PASS）。
- 协调员独立亲验（非转述监视员数字）：SHA／大小与上一致；App／Widget 均为 2.0.2/build 90、
  包名 com.ycwl.Lyrics、三二进制 thin arm64、LC_CODE_SIGNATURE 在位；逃逸检查点 **2 个**
  （0x10000d060／0x10000d098，同属函数 0x10000cfbc），0x44A5C 没回来；三 dSYM UUID 与二进制
  一字不差（App `c200975d…`、Widget `a3164378…`、daemon `e52f11ee…`）；
  entitlements 与 build 32 逐项比对**零差异**（三二进制 entitlements XML 字节级一致）；
  补丁标记在位：daemon 含 `refusing stale or unverified PID`；App 含
  `floatingLyric.cardOpacity`、`LyricWord`（App＋Widget）、`RuntimeEnvironment`／
  `installEnvironment`／`native-candidate`；2.0.2 的标记 `Hant-Hans`、`hudPill.positionLocked`、
  `build 31`／`build 32` 均不在位；TLD 码值扫描 0 命中。
- 一处如实记录：字面量 `canUseNativeHUD` 本身不在二进制里——Swift 把这个 internal
  computed static var 的 accessor 在全部调用处内联后符号被剥离；门控逻辑的可观测字串在位，
  记为 OBSERVE，不判 FAIL。

## §6 给 Lee 的真机测试清单（build 90）

前置：这是**测试版**，与好用的 2.0.2/build 32 分开装。测出问题就删了装回 2.0.2/build 32。

1. **巨魔安装后 HUD 启用是否正常（最重要）**：装好打开，主页面 HUD 区段应正常显示、点启用后
   守护进程 RUNNING、药丸出来。fail-closed 不许误伤巨魔环境——如果主页面显示
   「当前环境未确认具备原生 HUD 权限」或启用点不动，就是误伤，立即报。
2. **激活**：已激活的 2.0.2 覆盖安装，不应弹激活页；删 App 重装后的行为（Keychain 恢复照常）。
3. **Apple Music 兜底**：巨魔机上放 Apple Music，看跟歌／歌词有无可见变化（应无异常）。
4. **跟歌、暂停／续播、快进切歌照常**。
5. **逐字 timing 有无可见变化**：歌词行跟随照常（词级高亮渲染器里本来就没有接，不应凭空多出逐字效果）。
6. **锁屏解锁药丸还在跟**。
7. **PiP 固定文字**照常。
8. 其余回归：五项歌词、10 次锁解、30 分钟后台、停用／查看守护进程日志。

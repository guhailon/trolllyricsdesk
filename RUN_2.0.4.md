# RUN_2.0.4.md — TrollLyricsDesk 2.0.4 / build 34

- 分支：`v2.0.4`（新建，从 2.0.3 产品提交 `07d3c8a` 建；不动 v2.0.3 与 main）
- 功能提交：`5392b69`（`5392b69df2efaa328fc14afa0330c02f8bce946e`）
- Actions run：`46117628090`，head `5392b69`，`completed` / `success`（轮询第 3 轮即成功，约 3 分钟；无池子取消）
- 时间：2026-11-28 上午 UTC；IPA 下载 06:42 UTC
- 推送方式：git-data API POST 建 ref（201，在 `07d3c8a` 上）→ `gh_push.py check`（fast_forward_one_commit）→ `gh_push.py push`（remote_after `5392b69`）。建 ref 顺带触发了父提交在新分支上的 run `46117571703`（head `07d3c8a`，success，无害；与真正的 run 按 head SHA 区分）。
- 本文档提交：见本仓库 `v2.0.4` 分支 RUN 提交（单独一笔，在功能提交之后）。

## 1. 版本 2.0.4 / build 34

`LyricStore.versionTag` = `build 34（2.0.4）`；两处 Info.plist、pbxproj（MARKETING_VERSION ×6、CURRENT_PROJECT_VERSION ×6）、build.yml、TLDHUDVersion.h、SettingsView、PiPLyricsRenderer、HUD fallback 药丸文字同步到 2.0.4。

## 2. 合并来源（兼容补丁 20 处）

- 来源：独立 worktree `~/workspace/trolllyricsdesk-compat-test`，分支 `compat-test`，RUN 文档 `RUN_compat-test.md`。
- 并入提交：`3511e6a`（ChatGPT.zip 23 处原样）＋ `1ff0d6f`、`dd3301c`（两处编译修复：libproc 前向声明＋`extern "C"`）。**不含** `6d4d211`（build 90 测试版本号）。
- 基线差异处理：compat-test 基线是 cf78428（2.0.1），2.0.4 基线是 07d3c8a（2.0.3），中间隔着 2.0.2 七件＋2.0.3 七件——未用 cherry-pick，以 2.0.3 代码为底把兼容逻辑手工并入，未整文件覆盖，未丢 2.0.2/2.0.3 功能。
- 已在 2.0.3 里的项（2.0.2 基线 `a35f08b` 已有，未重复并）：`TLDHUDOwnPID`＋`proc_pidpath` 前向声明＋`extern "C"`、`WIFEXITED`、`status == 1`、installed-gate、`loadRc != 0 return`。 cosmetic 差异保留：`PROC_PIDPATHINFO_MAXSIZE` 在 newbase 是 1024（compat-test 是 4096）。
- 并入的 20 处（逐项核对过 RUN_compat-test.md）：fail-closed 门控（`canUseNativeHUD`、`preferredEngine`：trollstore  gated，`native-candidate`→`.inApp`）、激活 allowlist（`["master", "code"]`，读＋写）、Apple Music 兜底（`authorizedFallback`，仅非原生 HUD 环境＋已授权＋在播时）、逐字 timing 模型（`LyricWord`＋`words`＋`activeWord(at:)`、`<mm:ss>` 词级解析）、诊断权限按钮（`requestMusicPermission`＋"授权 Apple Music 备选数据源"）、轮询代次守卫（`pollingGeneration`＋`nextPollUptime`）、单调播放外推（`estimatedPosition`＋`observedUptime`）、AppDelegate 未知环境记 `compat`（不再 `native-candidate`）、保活只在 `canUseNativeHUD` 时启动、诊断页标题 `诊断（2.0.4）`。
- 注意：`TLDSAppDelegate.m` 的死代码 `verifyFloatingVisibility` 仍有一处写 `native-candidate`（compat-test 原样，未动）。

## 3. 新功能

### 3a. 横竖滑块定位药丸
- 主页面 HUD 区段：「固定位置」之后、「悬浮歌词颜色」之前，加「横向」「纵向」两条滑块。
- 写同一对 App Group 键 `hudPill.positionX`／`hudPill.positionY`（复用 2.0.2 的键，与 movePillToCenter／savePillPosition 同一套，未发明新键）；固定位置开＝滑块 `.disabled(hudPillPositionLocked)` 置灰拖不动。
- 进页面 `onAppear` 经 `syncPillSliders()` 读回当前药丸位置（无键时默认居中偏上）；拖滑块 `onChange` → `writePillSliderPosition()` 写键。
- daemon 活应用：`TLDHUDRootViewController.mm` 新增 `applySavedPillPositionIfChanged`——每秒 tick（`onTimerTick`）与解锁（`hudDidUnlock`）都重读位置键，变化超 0.5pt 才经 `movePillToCenter` 移药丸（复用夹取，不出屏；拖动中 `_dragging` 时直接 return 不抢；日志 `hud: pill position applied from slider (%.0f, %.0f)`）。位置经 App Group 键持久化（锁屏解锁、停用再启用、重装后进页面不丢）。
- 拖动手势代码原样未动。

### 3b. 卡拉OK模式（药丸＋应用内）
- 开关在设置页（ContentView）歌词区段「卡拉OK模式」，默认开；键 `lyric.karaokeEnabled`，键不存在＝开（主 App 与 daemon 读同一把键）。
- 数据源：LRCLIB 增强 LRC 的逐字时间戳（`LyricWord`＋`words`＋`activeWord(at:)`）；有逐字时间戳的歌逐字亮（已唱金色 `RGB(1.0, 0.8, 0.1)`、未唱 `baseColor.opacity(0.45)`）；无逐字时间戳退回整行高亮，不会没词显示。
- 只改显示层：快照 title／artist／lyrics[] 一律存 MediaRemote 原文，转换与逐字渲染只在显示时做（搜索、逐歌偏移、「·」识别继续用原文）；歌词简繁切换对逐字也生效（逐词 `convertForDisplay`）。
- 药丸：daemon 快照带 `currentWords`＋`elapsed`，当前行逐字上色，上一句／下一句照常（暗行，不受逐字影响）；应用内：歌卡大字是当前歌词行时逐字亮（TimelineView 0.25s＋原文比对），LC 应用内歌词区逐字亮（测试文字开时不逐字）。

### 3c. 药丸版本号
- HUD fallback 药丸文字写死的 `2.0.1` → `桌面歌詞 2.0.4`，与 `versionTag` 一致。

## 4. 自检

`check_2.0.4.py`（由 compat-test 的 `check_compat-test.py` 改名改版而来，§1–§14 兼容断言＋§15 2.0.3 回归＋§16 2.0.4 新功能）：

- 提交前：414 PASS / 0 FAIL（提交顺序断言 OPEN）。
- 提交后复跑：**415 PASS / 0 FAIL** / 6 OPEN（全是真机待测项）。
- 验包脚本 `hidden_files/verify_2.0.4.py` 在自检后又修了 4 处陈旧断言（见 §6），不影响源码。

## 5. 构建与验包

- run `46117628090` success；产物：
  - IPA：`~/workspace/your_files/桌面歌詞-2.0.4-newbase.ipa`，**1,744,788 B**，SHA256 `6e76143c0b8c704de0985c8eeb02bba43a0ebbef552c61303903ce778b192c53`
  - dSYM：`hidden_files/artifact-2.0.4/桌面歌词-2.0.4-dSYM.zip`，**2,316,712 B**，SHA256 `ceee8e81bb21c5a57ebd6f8dff669d64240151d7a80f8d1027806c61a3b41d0a`
  - 注意：GitHub artifact 下载下来是外层 zip（内含同名文件），已解开取内层真文件；上面尺寸／SHA 都是内层真文件的。外层 zip 保留为 `桌面歌词-2.0.4-artifact.zip`／`桌面歌词-2.0.4-dSYM-artifact.zip`。
- `hidden_files/verify_2.0.4.py`：**176 PASS / 0 FAIL**（exit 0）。要点：
  - bundle id `com.ycwl.Lyrics`，版本 2.0.4 / build 34（App＋Widget Info.plist），MinOS 15.0。
  - thin arm64 ×3（App／Widget／daemon，无 arm64e 混装）。
  - dSYM UUID 与二进制一致 ×3：App `d8980270fb8330c89e6adcabec73ed53`、Widget `8b3ec0848d303930a814b0b10f0a8f98`、daemon `ef59e59d67973591abd5813f5957b8ae`。
  - entitlements 与 build 33 逐项零差异（App／Widget／daemon 的 key 集与值全一致；源码 vs 二进制也一致）。
  - 逃逸检查点：App 仍为 **2 个** call sites（0x10000d060、0x10000d098，同在函数 0x10000cfbc；0x44A5C 崩点没回来）。daemon 无 `swift_isEscapingClosureAtFileLocation`。
  - 新功能字串在位（UTF-8 字节查）：`hudPill.positionX`／`hudPill.positionY`、`lyric.karaokeEnabled`、`KaraokeLyricText`、`LyricWord`、daemon `hud: pill position applied from slider`、`currentWords`、`readKaraokeEnabled`。
  - fail-closed 门控字串在位：`RuntimeEnvironment`、`installEnvironment`、`native-candidate`。
  - 旧版字串不在位：`桌面歌詞 2.0.3`、`悬浮测试 · 桌面歌词 2.0.3`、`build 33`（及更早版本）。
  - 码值扫描 `TLD-XXXX-XXXX-XXXX`：0 命中。
  - 旧 LC 文案 `LiveContainer 模式下不可用` 已不在位——是兼容补丁有意替换（新文案 `兼容环境 · 应用内歌词模式`／`当前环境未确认具备原生 HUD 权限；使用应用内歌词或独立 PiP 测试。` 在位）。
- 未动：激活／Keychain（除 allowlist 两行）、FrontBoard 老路（仍停用）、锁屏歌词（未恢复）、entitlements 文件（无改动）、拖动手势代码。

## 6. 验包脚本修注（不影响源码，只修断言）

首轮 verify 176 项里 5 FAIL，全是脚本问题，已修后复跑 0 FAIL：
1. Info.plist build 比较值写错：脚本沿用 `== "33"`（sed 只改了 `build 33` 标签字串，没改到比较值），IPA 里实际已是 `34`。→ 改成 `== "34"`。
2. 同上，Widget 的 `== "33"` → `== "34"`。
3. `LiveContainer 模式下不可用` 断言陈旧：该文案已被兼容补丁替换（2.0.3 基线两处 Text），二进制里正确地没有。→ 改断言新文案在位。
4. `currentLyricAndElapsed` 二进制查不到：小 static func 被优化器内联，连 `currentLyric` 都是 0 命中；`KaraokeLyricText` 与 `lyric.karaokeEnabled` 在位已证明卡拉OK代码进了包。→ 撤掉该二进制断言，helper 由 `check_2.0.4.py` §16b 在源码级断言。
5. 逃逸检查点 FAIL：本机缺 `capstone` 模块（脚本直接崩掉、无输出）。→ `pip3 install --break-system-packages capstone`（5.0.9）后实测 App = 2 个 sites，通过。注：该模块 2026-11-25 装过又不见了，部署前要先确认。

## 7. 给 Lee 的真机测试清单

1. 滑块横竖拖 → 药丸跟到位置（横向改左右、纵向改上下；拖到边缘不出屏）。
2. 固定位置开 → 两条滑块灰掉拖不动；关掉 → 又能拖。
3. 位置持久化：锁屏解锁后药丸还在滑块定的位置；停用 HUD 再启用，位置还在；重装后进主页面，滑块反映上次位置。
4. 卡拉OK：有逐字时间戳的歌，药丸和应用内都一个字一个字亮（已唱金色、未唱灰色）；没逐字时间戳的歌退回整行亮，不会没词显示。
5. 卡拉OK：歌词简繁切换对逐字生效；开关关掉变回整行亮。
6. 药丸版本号显示 `2.0.4`。
7. HUD 启用正常（fail-closed 没误伤巨魔机：巨魔环境仍能启用原生 HUD）。
8. 激活照常（重装免激活：全新安装激活一次 → 删 App → 重装 → 不弹激活页）。
9. Apple Music 兜底无坏变化。
10. 其余回归：颜色、透明度、字体大小、藏行、开关与 2.0.3 一致。

## 8. 未决／待 Lee

- 以上 10 项真机测试等 Lee。
- 兼容补丁里 `TLDSAppDelegate.m` 死代码 `verifyFloatingVisibility` 仍写一次 `native-candidate`（compat-test 原样，未动；不影响运行分支）。
- 药丸版本号与 daemon 日志版本号的显示口径：daemon 日志写 `Build 34`，药丸 fallback 文字写 `桌面歌詞 2.0.4`，与 `versionTag` 一致。

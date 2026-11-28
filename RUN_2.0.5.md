# RUN_2.0.5.md — TrollLyricsDesk 2.0.5 / build 35（HID 注入全量移植）

- 分支：`hid-touch`（新建，从 2.0.4 产品提交 `5392b69` 建；不动 v2.0.4、hid-probe、main）
- 产品提交：`650e8e6`（`650e8e61a098330de956def07b9a856244128d32`）＋修复笔 `643037a`（`643037a3f0401690ade295004ae0f611ff54d1f7`，见 §6 末）
- Actions run：`46133432118`，head `643037a`，`completed` / `success`（轮询第 4 轮即成功，约 4 分钟；job Build success，14 步全跑；无池子取消）
- 首跑 run `46133137613`（head `650e8e6`）也 success（第 3 轮，job Build success 14 步），但验包发现 1 FAIL（见 §6 末），修后重推重建，产物以第二跑为准。
- 时间：2026-11-28 UTC
- 推送方式：git-data API POST 建 ref（201，在 `5392b69` 上）→ `gh_push.py check`（fast_forward_one_commit）→ `gh_push.py push`。建 ref 顺带触发父提交在新分支上的 run（head `5392b69`，无害；与真正的 run 按 head SHA 区分）。
- 本文档提交：见本仓库 `hid-touch` 分支 RUN 提交（单独一笔，在产品提交之后）。

## 1. 版本 2.0.5 / build 35

`LyricStore.versionTag` = `build 35（2.0.5）`；两处 Info.plist、pbxproj（MARKETING_VERSION ×6、CURRENT_PROJECT_VERSION ×6）、build.yml（产物名 2.0.5）、TLDHUDVersion.h、SettingsView、PiPLyricsRenderer、HUD fallback 药丸文字、诊断标题 `诊断（2.0.5）` 同步到 2.0.5。

## 2. 底子：hid-probe cherry-pick

产品提交之前先有一笔探针底子提交（`hid-probe 底子`，cherry-pick 自 hid-probe 分支 `331623d`＋`3f7473f`，`--no-commit` 后去掉探针的 `check_hid-probe.py`／RUN 文档，只留源码改动）：5 个 hid.* entitlements、BKSHIDEventRegisterEventCallback 只记日志回调、hitTest 节流日志、BackBoardServices.tbd 加 `_BKSHIDEventRegisterEventCallback` 符号。升版 34→91 是探针原样带过来的，下一笔（本产品提交）改成 2.0.5/build 35。

## 3. 全量移植（TrollSpeed 触摸管线，MIT © 2023 Lessica）

来源：本地 clone `~/workspace/trolllyricsdesk-hud-test/hidden_files/trollspeed/`（HEAD `a609be2`，上游 https://github.com/lessica/TrollSpeed，MIT）。XExternalHUD 无许可证，只作机制对照，**一行代码都没抄**。

### 3a. 回调：TLDHIDEventCallback（HUD/TLDHUDDaemonMain.mm）

- 搬 TrollSpeed `sources/HUDApp.mm:27-100` 的 `_HUDEventCallback`：经 `BKSHIDEventRegisterEventCallback` 收原始 HID 事件 → `AXEventRepresentation` 解码（`representationWithHIDEvent:hidStreamIdentifier:@"UIApplicationEvents"`，先 `load` AccessibilityUtilities.framework）→ 相位映射（TouchDown=Began、Move=Moved、Cancel=Cancelled、Lift/InRange/InRangeLift=Ended）→ pointerId 取 `handInfo.paths[0].pathIdentity`，夹到 1..98 → `TSEventFetcher receiveAXEventID:atGlobalCoordinate:withTouchPhase:inWindow:onView:`。
- iOS 15.1 以下才 `_enqueueHIDEvent`（TrollSpeed 原样，不双发）；iOS 15.0 的 `isExactly15` 分支原样保留。
- 探针日志保留：前 10 个事件全记（`CFCopyDescription`＋`CFRelease`），之后每秒最多一个计数行（`hid: probe count N`），前缀统一 `hid: probe`，回调自己的 `probeLock`。
- **安全门（TLD 自加，TrollSpeed 没有）**：主队列里先 `hitTest` 药丸窗口（Gate 1，窗口自己的 hitTest 已缩窄到药丸），再取 `pillFrameInWindow` 手算比对（Gate 2，不用 CoreGraphics）；药丸外直接 return，**不吞、不改、不注入到别的窗口**。注入只发给药丸窗口自己的 view（`inWindow:keyWindow onView:keyView`）。第一次药丸内注入记一行 `hid: touch in pill, injecting`。
- 旧探针回调 `TLDHIDProbeCallback` 已撤，不再存在。

### 3b. 合成触摸：TSEventFetcher（HUD/TSEventFetcher.h/.mm）

- 搬 TrollSpeed `sources/TSEventFetcher.mm` 全文：`+load` 建 100 个触摸池＋run loop source；`receiveAXEventID:` 用 KIF `initAtPoint:inWindow:onView:` 造新触摸、旧触摸 `setLocationInWindow:` 跟、`setPhaseAndUpdateTimestamp:` 更新相位，经 `[app _touchesEvent]`＋`sendEvent:` 发出。
- **唯一改动（TLD）**：`+load` 里 `initTouch` 包 `@try/@catch`——daemon 进程没有 scenes，`initTouch` 读 `connectedScenes[0]` 会抛；池子里的触摸只是占位，首次真触摸会被 `initAtPoint:` 替换，抛时改用裸 `[[UITouch alloc] init]`＋phase Ended。
- KIF 两件（`HUD/UITouch-KIFAdditions.m`、`HUD/IOHIDEvent+KIF.m`）原样搬入（只加署名注释）。

### 3c. 事件管线：TLDHUDMainApplication（HUD/TLDHUDMainApplication.mm）

- 搬 TrollSpeed `sources/HUDMainApplication.mm:33-135`：手动装 UIEventDispatcher 的 run loop sources（`_installEventRunLoopSources:`，无此方法时走 pac_helper 扫描 `-[UIApplication _run]` 找 BL＋CBZ 兜底）、建 UIEventFetcher 并接成 sink（`setEventFetcherSink:`／`eventFetcherSink` 键）。
- **唯一改动（TLD，fail-closed）**：整个安装包 `@try/@catch`——私有 API 形状变了、安装抛异常时记 `hud: touch pipeline install failed`，daemon 照常活着（药丸照显示、照跟歌），只是没触摸。撤场 handler（fade out＋terminateWithSuccess）原样保留。

### 3d. 头文件（HUD/headers/，新增 10 个）

任务书点的 6 个：`AXEventRepresentation.h`、`UIEvent+Private.h`、`UITouch-KIFAdditions.h`、`UIEventFetcher.h`、`UIEventDispatcher.h`、`pac_helper.h`；依赖拉进来的 4 个：`AXEventHandInfoRepresentation.h`、`AXEventPathInfoRepresentation.h`、`UITouch+Private.h`、`IOHIDEvent+KIF.h`。每个文件顶部都有 Lessica © 2023 署名注释（KIF 的三个文件保留 KIF 自身的头，只加来源注释）。

### 3e. 链接

- daemon `OTHER_LDFLAGS` 加 `-framework IOKit`（Debug＋Release 各一处）：KIF 造 digitizer 事件调 `IOHIDEventCreateDigitizerEvent` 等 IOKit 导出函数，之前 daemon 只链 Foundation＋UIKit＋3 个 .tbd stub。TrollSpeed 是链 `IOKit.tbd`，等效。
- pbxproj：3 个 `.m` 进 daemon target Sources（BuildFile 定义＋Sources 列表各一处，共 12 个源文件）；14 个新文件进 HUD／headers 组。
- `HUD/TLDHUDMainWindow.mm` 未动：hitTest 节流日志（只记第一次）＋药丸矩形缩窄原样保留。
- 拖动代码未动：`handlePillPan` 原样；1 秒 tick 的 `applySavedPillPositionIfChanged` 开头 `if (_dragging || !_pill) return;` 核对还在，拖动中不抢位置。

## 4. 未动

2.0.4 全部功能原样保留（滑块、卡拉OK、20 处兼容、固定位置、颜色／透明度／字号）；激活／Keychain 未动；FrontBoard 老路仍停用；锁屏歌词未恢复；码值扫描 0 命中（验包见 §6）。

## 5. 自检

`check_2.0.5.py`（由 `check_hid-probe.py` 改名改版而来，§1–§16 保留＋§17 探针底子保留＋§18 HID 全量移植新断言）：

- 提交前：493 PASS / 0 FAIL（提交顺序断言 OPEN，RUN 文档未提交时正常）。
- 提交后复跑：**494 PASS / 0 FAIL** / 8 OPEN（全是真机待测项；比提交前多 1 项是通过的提交顺序断言本身）。

## 6. 构建与验包

- run `46133432118` success；产物：
  - IPA：`~/workspace/your_files/桌面歌詞-2.0.5-newbase.ipa`，**1,752,022 B**，SHA256 `c2a59840f058c2125c98439c45c86a406c82a6045a2f361fe581d1a2b5dd3f5f`
  - dSYM：`~/workspace/your_files/桌面歌词-2.0.5-newbase-dSYM.zip`，**2,743,153 B**，SHA256 `5c54ad5d04eeea8bb5502d8ec553aabeef7ee599e227d78cc08f5b2b29d33166`
  - 注意：GitHub artifact 下载下来是外层 zip（内含同名文件），已解开取内层真文件；上面尺寸／SHA 都是内层真文件的。外层 zip 保留为 `桌面歌词-2.0.5-artifact.zip`／`桌面歌词-2.0.5-dSYM-artifact.zip`（`hidden_files/artifact-2.0.5/`）。
- `hidden_files/verify_2.0.5.py`：**204 PASS / 0 FAIL**（exit 0）。要点：
  - bundle id `com.ycwl.Lyrics`，版本 2.0.5 / build 35（App＋Widget Info.plist），MinOS 15.0。
  - thin arm64 ×3（App／Widget／daemon，无 arm64e 混装）。
  - dSYM UUID 与二进制一致 ×3。
  - entitlements 与 build 34 比对：只差 daemon 的 5 个 hid.* 键；与 build 91 比对：零差异。
  - 逃逸检查点：App 仍为 **2 个** call sites（0x44A5C 崩点没回来）。daemon 无 `swift_isEscapingClosureAtFileLocation`。
  - 注入管线字串在位（daemon）：`BKSHIDEventRegisterEventCallback`、`TSEventFetcher`、`receiveAXEvent`、`hid: probe event`／`hid: probe count`、`hid: probe hitTest first call point`、`hid: touch in pill, injecting`、`hud: touch pipeline installed`、`AXEventRepresentation`、`UIEventFetcher`、`UIEventDispatcher`。
  - 旧版字串不在位：`悬浮测试 · 桌面歌词 2.0.4`、`桌面歌詞 2.0.4`、`build 91`、`build 34`。
  - 码值扫描 `TLD-XXXX-XXXX-XXXX`：0 命中。
  - dSYM UUID：App `fb1feee30f7134bbb7fd97b2c23aadb8`、Widget `8b3ec0848d303930a814b0b10f0a8f98`、daemon `27547cddea0635159aa50bc4b2a576e3`，三二进制一致。

### 6a. 验包发现的唯一问题（已修，重建重验）

首跑产物（run 46133137613，IPA 1,752,025 B，SHA `7deedf9a…`）验包 203 PASS / 1 FAIL：`不在位：build 91`——二进制里还有一处 `build 91`，定位在 daemon 的签名 entitlements 注释里（`HUD/TLDHUDDaemon.entitlements` 注释写了 `(2.0.4/build 91)`，entitlements 文件全文进签名 blob）。功能版本号本身全是 35，App／Widget 二进制干净。修法：注释里的 `(2.0.4/build 91)` 改成 `(hid-probe verification build)`，只改注释、功能零改动；另起一笔 `643037a`（check 脚本提交顺序断言同步改成四笔），重推重建（run 46133432118），复验 **204 PASS / 0 FAIL**。旧产物 IPA／dSYM 已被新产物覆盖。

## 7. 给 Lee 的真机测试清单

1. 覆盖安装本 IPA（免激活应仍通过，同 2.0.4/build 34 行为），启用 HUD 守护进程。
2. 药丸拖动：手指按住药丸拖，药丸跟手走；松手后位置存住（锁屏解锁后还在）。
3. 药丸外不干扰：在桌面／任意 App 里点、滑，App 正常接事件（药丸外的触摸一个都不能被吞）。
4. 守护进程日志里找 `hid: probe event`（前 10 个）＋`hid: probe count`＋`hid: touch in pill, injecting`（第一次拖药丸时）＋`hid: probe hitTest first call point`。
5. 若药丸拖不动：把守护进程日志发回（看 `hud: touch pipeline install failed` 在不在——在就是管线没装上，daemon 本身还活着）。
6. 其余回归与 2.0.4 清单一致（滑块定位、卡拉OK、颜色／透明度／字号、固定位置、10 次锁解、30 分钟后台）。

## 8. 未决／待 Lee

- 以上 6 项真机测试等 Lee。
- 触摸只在 daemon 的药丸窗口内验证；主 App 应用内歌词区的触摸本来就是系统正常触摸，未动。

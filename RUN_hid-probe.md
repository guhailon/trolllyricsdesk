# RUN_hid-probe — TrollLyricsDesk 2.0.4/build 91 hid-probe（HID 注入验证版）

> 只记日志，不注入。绝不上源、不发频道、不给用户。本分支只做验证，测完即弃；
> 正版线仍是 v2.0.4 的 2.0.4/build 34。

## 提交链（分支 `hid-probe`，仓库 guhailon/trolllyricsdesk）

| 提交 | SHA | 说明 |
|---|---|---|
| 基底（产品提交，v2.0.4） | `5392b69df2efaa328fc14afa0330c02f8bce946e` | 2.0.4/build 34（**不是** RUN 文档提交 ac3ae0a） |
| 产品提交 | `331623d94ae094c4d8c0de86d0611034a6c389c9` | 2.0.4/build 91 hid-probe：两件改动＋升版 34→91 |
| 链接修复 | `3f7473ff3df8a81fab54321245c72cb2e2e2f096` | BackBoardServices.tbd 加 `_BKSHIDEventRegisterEventCallback`（见下） |
| RUN 文档提交 | （本文件提交后填） | RUN_hid-probe.md |

- 远端分支 `hid-probe` 由 git-data API POST 建 ref（201，指向 5392b69 全 40 位 SHA），
  两笔提交均经 `gh_push.py check/push` 快进推送，sandbox 未直接 git push，未动
  v2.0.4 与任何 main。

## 构建

- run **46128242880**（head `3f7473f`），build.yml，**success**。
- 首跑 run 46127968236（head `331623d`）**failure**：Archive 步链接失败——
  `Undefined symbols: _BKSHIDEventRegisterEventCallback`。根因：本工程的
  `HUD/Private/BackBoardServices.tbd` 是只导出 `_BKSDisplayServicesStart` 的最小
  stub，声明在 `HUD/headers/BackboardServices.h` 里但 stub 没列该符号。修复只改
  stub 一行（加 `_BKSHIDEventRegisterEventCallback`），不改任何代码逻辑。
  该 run 不是池子取消（job Build 14 步，Archive 真失败），故按规矩修后重推，
  未默默重跑。
- IPA 出自产品提交＋链接修复，不含任何 RUN 文档提交。

## 产物

- IPA：`~/workspace/your_files/桌面歌詞-2.0.4-hid-probe.ipa`
  - 大小 **1,745,602 B**
  - SHA256 `2467a9cd4b7663a2b5a05f05994918a2beee97e666a6026d058f6b77e069717c`
- dSYM：`~/workspace/your_files/桌面歌词-2.0.4-hid-probe-dSYM.zip`
  - 大小 **2,317,749 B**
  - SHA256 `04f1a2b7660e709f1c106ae99b3732c19d1c98ce2c6d90ec6170a1760ed550ec`
- 构建产物原名 `桌面歌词-2.0.4.ipa`／`桌面歌词-2.0.4-dSYM.zip`（build.yml 未改），
  下载后改名；副本在 `hidden_files/artifact-hid-probe/`。

## 自检与验包

- 自检 `check_hid-probe.py`：**0 FAIL**（RUN 文档算进 diff 预期集合——2.0.4 那个
  bookkeeping FAIL 就是没算 RUN 文档，本次已算；7 OPEN，全是需 macOS／真机项）。
- 验包 `hidden_files/verify_hid-probe.py`（日志 `hidden_files/verify_hid-probe.log`）：
  **186 PASS / 0 FAIL**。capstone 5.0.9（验包前确认不在，已 `pip3 install --break-system-packages capstone` 装上）。
  - 版本 2.0.4／build 91（App＋Widget Info.plist、TLDHUDVersion.h、pbxproj ×6、
    LyricStore.versionTag），包名 com.ycwl.Lyrics，thin arm64（三二进制），
    daemon 在包内（TrollLyricsDesk.app/TLDHUDDaemon），dSYM UUID 与三二进制一致
    （app 3235a77b…、widget 8b3ec084…、daemon 8598f473…）。
  - 逃逸检查点 2 个（App 仍为 2，0x44A5C 没回来；daemon 0 个）。
  - entitlements 与 build 34 比对：**只差 daemon 的 5 个 hid.* 键**，多一个少一个
    都没有；app／widget 零差异；值全部一致。
  - 二进制含 `"hid: probe"` 与 hitTest 日志字串（daemon 内：`hid: probe event`、
    `hid: probe count`、`hid: probe hitTest first call point`、
    `BKSHIDEventRegisterEventCallback`）。
  - 码值扫描 TLD-XXXX-XXXX-XXXX：**0 命中**。

## 两件改动（除升版外别的什么都没动）

### 1. daemon HID 探针（只记日志，不注入）

- `HUD/TLDHUDDaemon.entitlements` 行 51–60：加 5 个键（全 `<true/>`）：
  `com.apple.private.hid.client.event-dispatch`、`event-filter`、`event-monitor`、
  `service-protected`、`com.apple.private.hid.manager.client`。文件顶部注释里
  "hid.* keys (no touch in v1)" 改成 hid-probe 验证版说明。
- `HUD/TLDHUDDaemonMain.mm`：
  - 行 99–131 回调 `TLDHIDProbeCallback`：只记日志，绝不注入，不调任何事件处理
    函数。节流：前 10 个事件全记（`CFCopyDescription` 取描述，`CFRelease` 释放；
    event 为空记一行 `(null event)`），之后每秒最多一个计数行（累计总数）。
    日志前缀统一 `hid: probe`。回调可能不在主线程跑——`TLDHUDLog` 本身已有
    `@synchronized` 锁（TLDHUDLog.mm），计数器另有自己的 `probeLock`
    （行 104–109，`dispatch_once` 建锁＋`@synchronized`）。
  - 行 176 注册 `BKSHIDEventRegisterEventCallback(TLDHIDProbeCallback);`，
    在 `-hud` 分支 `[NSRunLoop currentRunLoop];` 之后（TrollSpeed HUDApp.mm 同款位置）。
    `BKSHIDEventRegisterEventCallback` 已在 `HUD/headers/BackboardServices.h` 声明，
    `IOHIDServiceRef`／`IOHIDEventRef` 在 `HUD/headers/IOKit+SPI.h` 有 typedef，
    未新增头文件。
  - 行 88–98 回调上方注释：说明这是 TrollSpeed（MIT © 2023 Lessica）HUDApp.mm 的
    `_HUDEventCallback` 注册方式的最小引用，只注册、不抄它的 AX 解码与注入逻辑。
  - 链接修复（另见构建一节）：`HUD/Private/BackBoardServices.tbd` 加
    `_BKSHIDEventRegisterEventCallback` 到导出符号表。

### 2. hitTest 节流日志

- `HUD/TLDHUDMainWindow.mm` 行 11 加 `#import "TLDHUDLog.h"`；行 35–38 在
  `hitTest:withEvent:` 开头：`static BOOL` 已记过就跳过，第一次调用记一行
  `hid: probe hitTest first call point (%d,%d)`。不全量记（全屏窗口每触必调会刷屏）。
- 未新增任何 CoreGraphics 调用，只记两个 int（2.0.2 教训：daemon 不链
  CoreGraphics，`CGRectContainsPoint`／`CGRectIsEmpty`／`CGRectZero` 是外部符号）。

## 升版（按 2.0.4 的做法，34→91）

- `HUD/TLDHUDVersion.h` 行 11–12：`VERSION_STRING @"2.0.4"` 不变，`BUILD_STRING @"91"`。
- `Lyrics/LyricStore.swift` 行 33：`versionTag = "build 91（2.0.4）"`。
- `TrollLyricsDesk/Info.plist`、`TrollLyricsWidget/Info.plist` 行 22：`CFBundleVersion`
  `34`→`91`（sed 精确改版本行，未用 plistlib 重写）。
- `TrollLyricsDesk.xcodeproj/project.pbxproj`：`CURRENT_PROJECT_VERSION = 34`→`91`（×6；
  `MARKETING_VERSION = 2.0.4` 不变）。2.0.4 的做法含这一处，否则编出的 build 号不对。

## 真机测试清单（给 Lee，守护进程日志里找 `hid: probe`）

1. 覆盖安装本 IPA（免激活应仍通过，同 2.0.4/build 34 行为），启用 HUD 守护进程。
2. 在桌面／任意 App 里点几下、滑几下，看守护进程日志：
   - 应有 `hid: probe event 1…10`（带事件描述）；
   - 之后每秒最多一行 `hid: probe count N`；
   - 应有一行 `hid: probe hitTest first call point (x,y)`（第一次触到药丸窗口时）。
3. 若全程一条 `hid: probe` 都没有：说明 Backboard 没把 HID 事件递给 daemon 回调
   （注册成功但无事件，或 entitlements 未生效）——把日志发回。
4. 测完删了装回正版 2.0.4/build 34 即可回退。

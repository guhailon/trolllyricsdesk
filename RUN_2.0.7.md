# RUN_2.0.7.md — TrollLyricsDesk 2.0.7 / build 37

- 基线：`aebd725`（2.0.6/build 36 卡拉OK修复，分支 v2.0.6）
- 分支：`v2.0.7`（从 aebd725 建）
- 版本：**2.0.7 / build 37**
- 产品提交：`fad60e0`（2.0.7/build 37：拖动修顺＋ChatGPT 稳定性＋歌词搜索回退）
- CI run：**46138783993** success（head fad60e0，一次成功，0 池子取消，约 2 分钟）
- IPA：`~/workspace/your_files/桌面歌詞-2.0.7-newbase.ipa`，**1,771,550 B，SHA256 `2866acf4dc34b1197a2fabb0a66a5bf7848942b74036377b70f7815555070145`**
- dSYM：`~/workspace/your_files/桌面歌词-2.0.7-newbase-dSYM.zip`，**2,776,990 B，SHA256 `fc14f7b3fa713db1c3fe7c87864a943f75847434b7ea5ad41fb411d818495087`**

## 1. 这一版做三件（Lee 2026-11-28 批准）

1. **拖动修顺**——药丸能走但生涩（Lee 2026-11-28 18:28「药丸太难滑动了」）。
2. **ChatGPT 稳定性修补并进来**——Lee 2026-11-28 18:31 点选，拖动优先、两件同一版。
3. **歌词搜索放宽回退**——Lee 2026-11-28 19:03 批准（追加进同一版）：翻唱歌手搜不到歌词。

三件同在一版，改同一文件时合在一起改，没有互相覆盖。

## 2. ChatGPT 稳定性修补：来源与核对

- 来源：`~/workspace/user/files/桌面歌詞-2.0.6-ChatGPT-源碼.zip`（1,300,816 B，SHA256 `db56e0072a3b22049c237691348ac279a7e37e3d3ee68fbdd4b7bf9923c3edd7`），是同一条「歌词引擎升级建议」对话的续篇，ChatGPT 交的它自己的 2.0.6 Build 36 源码包。
- 核对：奴才全树 diff 对照 643037a，恰好 **12 改＋3 新**，与声称一致；六项关键改动均在代码里（见 `hidden_files/REPORT_2.0.7_CHATGPT_PACKAGE_CHECK.md`）。基线交叉核对：每一项声称的缺口在 643037a 里都真实存在。
- **版本号撞号**：ChatGPT 的 2.0.6 与卡拉OK 2.0.6 内容完全不同，不能都叫 2.0.6；它的内容进我们的 **2.0.7**，版本字串一律重定 2.0.7／build 37，不得原样取它的 2.0.6／build 36。
- **诚实口径**：ChatGPT 的包只做过 Linux swiftc parser 验证，没编过、没签名、没真机测。2.0.7 的并入以我们自己的 CI 编译＋验包＋Lee 真机为准。
- 并入内容（六项）：
  1. `TLDHUDHelper.mm`：launchctl 命令加 8 秒超时（单调时钟 deadline，WNOHANG 轮询＋0.05 秒 sleep，超时 SIGKILL＋异步回收）；`TLDHUDSetEnabled` 加串行保护（`@synchronized`＋Locked 内函数）；Enable 已运行时直接返回；unload 看 rc，失败或仍在运行才走 `-exit` 兜底；`-exit` 失败记日志。
  2. `TLDHUDDaemonMain.mm`：daemon 每 10 秒心跳（pid＋uptime，注释写明心跳不证明窗口可见）；单实例文件锁（`/var/root/com.ycwl.Lyrics.hud.lock`，flock LOCK_EX｜LOCK_NB，拿不到就退出）；PID 写失败记日志并退出。
  3. `TLDHUDDaemon.plist`：ThrottleInterval 5→15 秒。
  4. `TLDHUDMainApplicationDelegate.mm`：窗口托管安全检查——先验私有接口在不在（`_contextId`／`registerWindowWithContextID:atLevel:`），contextId 为 0 藏窗返回 NO，`@try`／`@catch` 包注册，日志写明注册成功≠可见（visibility unverified）。
  5. `TLDHUDDaemonMain.mm`：HID 安全检查——窗口从 delegate 取（不再 dispatch_once 永久缓存），判 hidden／rootVC；坐标先验 isfinite；未知相位拒绝（不再默认 Ended）；pointerId 越界（>98）直接拒绝（不再夹取）；AX 类先验 respondsToSelector；药丸区域限制保留。
  6. 崩溃诊断日志：心跳、单实例锁、托管检查、HID 检查的失败都记日志行。
  - 另有 SettingsView.swift、PlaybackDashboardView.swift（异步状态查询：refreshHUDStatus 走后台队列＋代次守卫，不堵主线程）、LyricStore.swift、两个 Info.plist、project.pbxproj、build.yml、TLDHUDVersion.h 的改动。
- 合并纪律：
  - LyricStore.swift 与卡拉OK 2.0.6 同文件重叠（缓存键 v2＋诊断日志 vs 它的版本标记），以 aebd725 为基线手工并，缓存键 v2 与诊断日志保留，不得覆盖。
  - project.pbxproj 除版本行外逐行核，不能整文件覆盖。
  - 它的 SettingsView.swift 改动在**死页面**里（SettingsView 从未实例化，见 2.0.1 导航根因），记为**无效改动**，不要假装它生效。
  - 它的 check_2.0.6.py 不直接取用，另写 check_2.0.7.py（版本断言＋RUN 文档计入预期列表，吸取 2.0.4 自检漏算 RUN 文档得 415 PASS／1 FAIL 的教训）。
  - ChatGPT 原始记录存档在 `hidden_files/RUN_2.0.6-ChatGPT.md` 与 `hidden_files/BUILD35_REGRESSION_ON_BUILD36-ChatGPT.txt`（不进仓库提交）。
  - ChatGPT 自认未解决（不在本版）：心跳超时自动监控及有限次数重启、非 launchd 直接启动模式的自动恢复、跨进程启动与停止事务保护、手指拖出药丸区域后的触摸取消处理（本版拖动闩锁的安全网已覆盖门丢弃时注 Cancelled，见 §3）、完整崩溃报告自动符号化、私有窗口托管接口的真机相容性。

## 3. 拖动修顺：根因与修法

- 诊断报告：`hidden_files/REPORT_2.0.7_DRAG_DIAGNOSIS.md`（全文亲读）。
- 真机事实：2.0.5 直接拖已通（Lee 2026-11-28 18:27「药丸可以走了」），但生涩难滑。
- 根因排序：
  1. **主因——每事件按药丸当前矩形重算 hitTest，无拖动闩锁**：回调是静态 C 函数（DaemonMain.mm），不知道有没有拖动在进行；药丸永远比手指慢一整条管线，手指一快就滑出矩形、Moved 被丢、拖动卡死；TrollSpeed 原版 `_HUDEventCallback` 没有任何药丸门。
  2. **次要——TSEventFetcher 丢 Began 后第一个 Moved**（TrollSpeed 原版逻辑）。
  3. 加重——药丸可抓区域小且随歌词变。
  4. 潜伏 bug——手指在药丸外面抬起时 Ended 被门丢掉，`_dragging` 永久 YES（滑块失效＋半透明＋不保存）。
  5. pan 手势配置已排除。
- 修法（按优先级）：
  1. **拖动闩锁（必做）**：Began 注入成功后记 `activeDragPointerId`，同一 pointerId 的后续 Moved／Ended／Cancelled 跳过两道矩形门直接注入；未知相位或重复 Began 时先注入一次 UITouchPhaseCancelled 再清闩锁；门丢弃拖动中事件时改为注入一次 Cancelled（同时修掉 `_dragging` 永久 YES 的潜伏 bug）；拖动注入计数加节流日志（每 50 次一行 `hid: drag inject count`），否则真机难判断门有没有误杀。
  2. **Began 后第一个 Moved 不再丢弃**（TSEventFetcher.mm：删掉 early return，改为先 stationarify 再应用本次移动；改动需真机验证）。
  3. **两处矩形比对外扩约 20pt**（DaemonMain Gate 2 与 MainWindow hitTest 一致）。
  4. **`_dragging` 看门狗保险**：Began／Changed 更新 `_lastDragChangeTime`，onTimerTick 里 5 秒无 Changed 强制收尾（清 `_dragging`、alpha 回 1.0、保存位置、记 `hud: pill drag watchdog reset`），放在滑块重应用之前。
  5. **pan 限单指**（minimum／maximumNumberOfTouches = 1）。
- **重叠处理**：ChatGPT 的 HID 安全检查与拖动闩锁动同一个回调 `TLDHIDEventCallback`，两处合在一起改完再编，没有各改各的再覆盖。安全门仍在：药丸外触摸照常丢弃（门逻辑未删），注入只发给药丸窗口。

## 4. 歌词搜索放宽回退：根因与修法

- 真机事实（Lee 2026-11-28 19:00–19:02 守护进程日志＋奴才亲查 LRCLIB）：
  - 2.0.6 新守护进程已跑起来（19:01:52 hud: start pid 33840 version 2.0.6 build 36，touch pipeline installed），新日志格式在位，但晴天仍是「(0 lines, karaoke 0 words)」。
  - 0 行不是解析器坏：解析器坏会是行数>0、词数=0；0 行说明搜索／匹配根本没拿到歌词。
  - 根因是歌手对不上：报上来的歌手是「哇欣」（翻唱）。奴才亲查 LRCLIB 实测：track=晴天＋artist=哇欣→[]（空）；track=晴天＋artist=周杰伦→有结果且 hasWordSync=true；track=晴天（杰伦）＋artist=哇欣→[]；只拿歌名晴天搜→20 条，全是周杰伦／Jay Chou。LRCLIB 里《晴天》只有周杰伦的版本。
  - 另：19:00:20–21 相邻两秒歌名歌手来回跳（「哇欣 — 晴天（杰伦）」↔「晴天（杰伦） — 哇欣」），身份不稳也加重了匹配失败。
- 修法：
  1. **搜索阶梯**（`LyricMatcher.searchAttempts`，纯函数）：由严到松、去重——①歌名＋歌手 → ②去括号歌名＋歌手 → ③去括号歌名（不带歌手） → ④原歌名（不带歌手）；某一组返回空才试下一组，第一组有结果就停，不多发请求。404 当空结果继续阶梯，不当失败；429／5xx 等真错误直接抛，不白白重试。
  2. **括号剥离**（`LyricMatcher.stripBracketQualifier`，纯函数）：「晴天（杰伦）」→「晴天」，中英文括号都处理，多组都删；括号不成对、或删完为空时返回原串，不动。
  3. **只按歌名搜时不带 artist_name 参数**（`LRCLibClient.search(track:artist:)` 新重载）：LRCLIB 收到空 artist_name 仍会按歌手过滤，不带该参数才真正是「只按歌名搜」；旧 `search(track: MusicTrack)` 委托给新重载，行为不变。
  4. **字段互换防抖**（`LyricMatcher.isSwappedPair`，纯函数）：换歌分支先判相邻两次 poll 两字段是否正好互换，是则当同一首歌，不重置、不重搜，落到同歌分支继续同步，记一行 `歌名歌手互换防抖` 诊断日志。只认「相邻两次正好互换」：稳定换边后仍会走一次换歌分支（只一次），不硬编。
  5. **诊断日志**：每级记一行搜索条件＋返回条数（`歌词搜索：第N次 track=… artist=…（返回 N 条）`）；成功日志带命中级数（`第N次搜索命中`）；无结果日志带已试组数。回退有没有发生、卡在哪一级，真机只看日志就能判。
  6. **匹配分**：核实过——`bestMatch` 本来就没有最低分数线（返回最高分候选，无阈值门），所以「放宽匹配分」不适用，无分可放；回退只在搜索层。
- 约束：回退只改搜索／匹配层，不动 lyricsfile 解析、不动缓存键 v2、不动激活。
- 单元断言：EngineTests/main.swift 加了晴天／哇欣翻唱回退断言（阶梯 4 级、去括号、无歌手时 1 级）与互换防抖断言，CI 的 swiftc 引擎测试里跑（LyricMatcher.swift 已在 CI 文件列表里，无需改 build.yml）。

## 5. 自检与验包

- check_2.0.7.py：**586 PASS／0 FAIL／12 OPEN**（RUN 文档提交后复核通过；12 OPEN 全是需 macOS／真机的待验证项，见脚本末尾）。
- verify_2.0.7.py：**221 PASS／0 FAIL**（`hidden_files/verify_2.0.7.py`）。
  - App 2.0.7／build 37、thin arm64、daemon 在包内；dSYM UUID 与三二进制一致（App `9713c946…`、Widget `58bbc4b0…`、daemon `1e5264cb…`）；逃逸检查点 2 个；entitlements 与 build 36 逐项零差异（三二进制：源码 vs 二进制一致，build 36 基线 vs build 37 一致）；二进制含 lyricsfile、拖动闩锁（`hid: drag latch set/cleared`、`hid: drag inject count`）、心跳（`hud: heartbeat pid=`）、搜索回退诊断日志（`歌词搜索：第`、`歌名歌手互换防抖`）。
  - 验包中发现并已解释的三处（不是产品问题）：
    1. `searchAttempts`／`stripBracketQualifier`／`isSwappedPair` 三个 Swift static func 在二进制里扫不到——小纯函数被 whole-module 优化内联进 loadLyrics／换歌分支，无符号名（与 2.0.6 的 currentLyricAndElapsed 同一效应）；函数在位由 check_2.0.7.py §21 源码断言保证，行为由 CI 引擎测试保证（EngineTests 直接调它们）。
    2. Helper 三行日志（`rewriting daemon plist…`／`launchctl unload (best-effort…`／`daemon started after launchctl load (3s check)`）在 build 36 的 daemon 二进制里有、build 37 的 daemon 里没有——ChatGPT 把 SpringBoard 回调里的 `TLDHUDSetEnabled(YES)` 同步重拉改成退出等 launchd 恢复后，daemon 里再没有 Helper SetEnabled 路径的调用方，链接器 dead-strip 掉了；函数本体仍在 App 二进制里（App 调 TLDHUDSetEnabled），断言已改到 App 侧。
    3. `hud: window registered` 已不在——ChatGPT 的托管安全检查重写了 MainApplicationDelegate 的注册代码，改记 `hud: registration requested contextId=…`；断言已更新。
  - 另：capstone 模块又不见了（老毛病），验包前 `pip3 install --break-system-packages capstone` 重装后逃逸检查正常。
- `lyric.cache|v2|` 是 small-string immediate，字节扫不到（2.0.6 已证实三二进制全是 -1），由源码级断言保证，不作二进制断言。

## 6. 真机测试步骤（给 Lee）

**拖动修顺：**
1. 慢拖药丸：跟手走，不卡。
2. 快拖甩动：手指快过药丸也不丢手，松手位置留住。
3. 拖出药丸区再抬手：手势正常结束，药丸不半透明残留，滑块仍能用。
4. 拖动中切歌：药丸尺寸变化不中断拖动。
5. 点药丸外面、划别的 App：完全不受影响（药丸外触摸不被吞——安全重点）。
6. 日志里找节流行：`hid: drag latch set`、`hid: drag inject count`（每 50 次一行）、`hid: drag latch cleared`。

**ChatGPT 稳定性：**
7. HUD 启用／停用照常；心跳日志每 10 秒一行（`hud: heartbeat pid=…`）。
8. SpringBoard 重启（或 respring）后守护进程恢复，不用手动重启用。
9. 其余回归与 2.0.6 清单一致（激活、卡拉OK、颜色／透明度／字号、藏行、开关）。

**搜索回退：**
10. 放翻唱《晴天》（哇欣）：药丸应出歌词（以前是 0 行）；日志里找 `歌词搜索：第3次 track=晴天 artist=（无）（返回 20 条）` 左右的字样（第几次命中以实际为准，看日志）。
11. 放带括号的歌名（如「晴天（杰伦）」）：同样应出歌词。
12. 歌名歌手来回跳的歌：不应每两秒重搜一次，日志里不应频繁出现「检测到新歌曲」，偶尔一行 `歌名歌手互换防抖` 是正常的。
13. 正常歌（歌手对得上）：仍一次命中，无多余请求（日志里只有第 1 次）。

## 7. 未动与未决

- 未动：激活／Keychain、FrontBoard 老路、锁屏歌词、entitlements、卡拉OK接线（lyricsfile 解析、缓存键 v2）、拖动手势本体（2.0.5 的 pan 逻辑未动）。
- 未决：ChatGPT 自认未解决的五项（见 §2）不在本版；自检 12 OPEN 全是真机／macOS 待验证项，等 Lee（见 §6）。

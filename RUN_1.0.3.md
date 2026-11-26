# TrollLyricsDesk 1.0.3 — run log

1.0.2 cycle is in RUN_1.0.2.md (1.0.2 build 15 built + verified 2026-11-26, run 45752565991).
1.0.3 = 1.0.2 + server-verified activation, build 16. The whole App asks for a
code on first launch: POST https://guhailong-repo.pages.dev/api/verify
(code trimmed + uppercased first); a valid reply writes tld.activated=true and
tld.activationType=master/code into the App Group, then the App goes straight
to the main UI. Wrong code → 「激活码不正确」; no network / server unreachable
→ 「需要联网激活」; neither lets the user in. Unactivated: main UI is a
full-screen activation page, the floating lyric window stays hidden, the widget
shows 「请先在 App 内激活」. No code value exists anywhere in the App source,
the repo, or the logs — the code table lives only on the server. Lockscreen
code (Live Activities + lock-screen widget) untouched; MinOS 15.0 untouched.
Branch v1.0.1, worktree `~/workspace/trolllyricsdesk-1.0.1`, local HEAD 0e1e014.

## 推送（2026-11-26 12:09–12:14 CST）

远端 v1.0.1 从 7e39edf 起，gh_push.py 逐笔推（每笔推前先 check，均为
fast_forward_one_commit），两笔全上，远端终为 0e1e014：

- 0f96ffd（补 RUN_1.0.2.md：1.0.2 新线 run 45752565991 成功记录——上个周期
  留下的未提交修改，先单独提交推送；其 run 45753433786 也是 success，中间 run，不管）
- 0e1e014（1.0.3 build 16：首次打开要激活码，服务器验证 POST /api/verify）

本地自检 `check_1.0.3.py`：**174 PASS、FAILED: none、OPEN 26**（提交后重跑才算数；
提交前红线 diff 五项必然是空——HEAD 里还没有改动）。

接口预检（实现前，2026-11-26，没用任何真码）：假码（全零测试码）
→ `{"valid":false}`；空码 → HTTP 400。服务端活着，错码路径正常。

## run 45753959179 — head 0e1e014 — 2026-11-26 12:16 CST — SUCCESS

- attempt 1 一次上机成功，无池子取消。轮询（读 `status_field`／`conclusion`）：
  poll 1 `in_progress`（12:15），poll 2 `completed`／`success`（12:16）。
- Artifact：id 15086532985，名「桌面歌词-1.0.3」，zip 1,607,394 B。
- IPA：**桌面歌词-1.0.3.ipa，1,609,075 B，SHA256 `cc0a37733d948fc30afa0f2bc1ce358feef3b904ca55671a066ca4793cf2b68f`**。
  存 `~/workspace/trolllyricsdesk-1.0.1/hidden_files/artifact-45753959179/`
  （artifact.zip＋IPA＋unpacked/），另拷一份到
  `~/workspace/your_files/桌面歌词-1.0.3.ipa`（SHA 一致）。

## 验包（全过，`hidden_files/verify_1.0.3.py`：41 PASS、FAILED: none）

- App：1.0.3／build 16、显示名「桌面歌词」、包名 com.hailong.TrollLyricsDesk2、
  MinOS 15.0、`NSSupportsLiveActivities=true`
- Widget：1.0.3／build 16、MinOS 15.0，扩展点 com.apple.widgetkit-extension；
  二进制含 `accessoryRectangular`（×1）＋`ActivityConfiguration`（×3）；
  App 二进制也含 `ActivityConfiguration`（×6）
- 架构：Mach-O 64-bit arm64，两二进制均为 arm64（subtype 0）
- 签名（zsign）：两二进制均含 LC_CODE_SIGNATURE；IPA 里没有 _CodeSignature
  目录（zsign 把签名嵌进二进制，与已验过的 1.0.1／1.0.2 一致）
- 弱链接（本机无 otool，用 `~/workspace/trolllyricsdesk/hidden_files/macho_inspect.py`
  核实，弱链接 cmd 0x80000018 含 LC_REQ_DYLD 位）：App 与 Widget Extension
  两二进制的 ActivityKit 均为 **LC_LOAD_WEAK_DYLIB**
- 激活串在位：App 二进制含 `api/verify`（×1）、`tld.activated`（×1）、
  `tld.activationType`（×1）、「激活码不正确」（×1）、「需要联网激活」（×1）；
  Widget 二进制含「请先在 App 内激活」（×1）
- 小组件 `tld.activated` 字面量说明：Widget 二进制里搜不到 `tld.activated`
  这串字节，不是功能缺失——Swift 把 13 字符的 ASCII 键以内联小字符串
  （small string，塞进 16 字节 String 值里）直接编进指令流，不留 __cstring
  字节。门本身在位有三证：占位文案（×1）＋`ActivationStore` 类型元数据＋
  `boolForKey:` 选择子（×1，即 `isActivated` 读标记的那次调用）；
  `UserDefaults` 引用（×2）。App 二进制里同一串（×1）是因为
  `markActivated`／`@AppStorage` 那几处要桥接成 NSString，字面量才留下来。
  Widget 的 `api/verify` 字面量同样是 0（同理，只在 App 里留着，×1）。
- 无码值：12 个码逐值扫两二进制，命中 0（只计数、不打印码值）
- 无旧 invite 串：`tg://join?invite=`（×0）、`https://t.me/+I-I8aw7HUAw1NGY9`（×0），
  两二进制皆然；Telegram 新行（`tg://resolve?domain=Guhailon`）在 1.0.2 已验
- 无 BackBoard（×0）、无 TLHUDApplication（×0）、无 `-hud`（×0）、
  无 dynamic_lookup（×0），两二进制皆然

## 实现改了哪些文件（0e1e014，12 个文件）

- `App/ActivationView.swift`（新文件）：`ActivationGateView`（@AppStorage 读
  App Group 标记，未激活显示激活页，否则主界面）、`ActivationVerifier.verify`
  （码 trim＋大写后 POST /api/verify，`URLSession.shared.data(for:)`，
  iOS 15.0+；码不对抛 wrongCode，没网／非 200／解不出抛 needsNetwork）、
  `ActivationView`（输码框＋激活按钮，全屏，背景共用 AppBackgroundView；
  成功写标记＋`WidgetCenter.reloadAllTimelines()`；日志只记成功／码不正确／
  网络失败，绝不记码值）
- `Lyrics/LyricStore.swift`：只加 `ActivationStore`（接口地址、键
  `tld.activated`／`tld.activationType`、`isActivated`／`activationType`／
  `markActivated(type:)`）；本文件同时在 App 与 Widget 两个 target 里，
  所以只放 Foundation 层面的键与读写
- `App/TrollLyricsDeskApp.swift`：`makeRootViewController` 改包
  `ActivationGateView { PlaybackDashboardView() }`，environmentObject 照旧透传
- `Overlay/FloatingLyricViewController.swift`：`applyVisibility` 加
  `|| !ActivationStore.isActivated`，未激活悬浮窗隐藏；0.25s 定时刷新，
  激活后自动恢复，不用重启
- `TrollLyricsWidget/WidgetView.swift`：body 顶层先判激活，未激活显示
  「请先在 App 内激活」占位（主屏幕／锁屏两种 family 都走这里）
- `TrollLyricsDesk.xcodeproj/project.pbxproj`：新文件四处注册（PBXBuildFile＋
  PBXFileReference＋App 组 children＋App Sources）＋ MARKETING_VERSION 四处 1.0.3
- `TrollLyricsDesk/Info.plist`、`TrollLyricsWidget/Info.plist`：1.0.3／build 16
- `.github/workflows/build.yml`：产物名桌面歌词-1.0.3.ipa
- `README.md`、`BUILD_NOTES.md`：1.0.3 章节
- `check_1.0.3.py`：新线自检（旧线文件已覆盖重写；174 PASS、FAILED: none、OPEN 26；
  红线锚点固定基点 7e39edf，`git diff 7e39edf HEAD -- <路径>`；码值逐值扫描读
  worker 的码表，只计数不打印）
- 锁屏文件（LiveActivity／LyricsLiveActivityController／PlaybackCoordinator／
  Widget 锁屏分支）一字未动；检测引擎照常在启动时自动跟随（激活前也在跑，
  但主界面／悬浮窗／小组件三处都不显示歌词，激活后即时恢复，不用重启）

## 待真机验（OPEN 26，自检原样）

1.0.3 新增六件（各件都要在真机上点一遍）：

- 首次打开全屏激活页：全新安装（或清掉 App Group 后）第一次打开全屏激活页，
  不进主界面；输对码后直接进主界面，不用重启；杀掉重开直接进主界面，不再要码
- 码不对／没网：输错码提示「激活码不正确」，仍在激活页；断网（飞行模式）点激活
  提示「需要联网激活」，仍在激活页；两种情况都不放行
- 悬浮窗未激活隐藏：未激活时放音乐悬浮窗也不出歌词；激活后 0.25s 内自动出现，
  不用重启
- 小组件占位：未激活时主屏幕小组件和锁屏小组件都显示「请先在 App 内激活」，
  不显示歌词；激活后小组件恢复正常内容（时间轴已刷新）
- master／code 两类码：两类码都要有人在真机上试过：master 码与普通码各至少一次，
  激活后类型记录正确
- 激活标记存在 App Group，卸载重装要重新激活：iOS 删 App 时 App Group 数据一般
  随之清除，重装后应重新要码；真机上验证一次

1.0.2 结转（未变）：Telegram 行点开进频道、日志复制／清除、背景更换、
悬浮窗固定位置、提示文字移到界面＋标题居中。

1.0.1 结转（未变）：灵动岛三态、锁屏横幅跟词、常亮显示（15 Pro）、iPhone 11
只有横幅＋小组件、锁屏小组件添加与延迟、滑掉横幅后开关同步、暂停提示、取色、
浅色背景白色清不清晰、同曲进度跳转（独立修复，未做）、Activity 节流、
8 小时到期重开、横幅与展开态两套布局（已知出入，非编译错）。

- Deploy NOT approved — separate approval. No channel post (paused).

# RUN_2.0.6.md — TrollLyricsDesk 2.0.6 / build 36（卡拉OK修复）

- 分支：`v2.0.6`（新建，从 2.0.5 产品提交 `643037a` 建；远端 ref 用 git-data API POST 建，201；不动 hid-touch、v2.0.4、main）
- 产品提交：`55afea9`（`55afea944c2568b4d2a2ae10e435c11b13b1b483`）＋修复笔 `64a6a7b`（`64a6a7b5838bd6db455fa6a400d2124f95e2e245`，见 §6a）＋`aebd725`（`aebd725c7b0eb1e6a97def868822467d65d2eabe`，见 §6a）
- Actions run：`46136838949`，head `aebd725`，`completed` / `success`（轮询第 3 轮即成功，约 3 分钟；job Build success，14 步全跑；无池子取消）
- 首跑 run `46134758976`（head `55afea9`）failure（第 4 步引擎回归测试，见 §6a），第二跑 run `46135798827`（head `64a6a7b`）failure（第 6 步 archive，见 §6a）；产物以第三跑为准。
- 时间：2026-11-28 UTC
- 推送方式：git-data API POST 建 ref（201，在 `643037a` 上）→ `gh_push.py check`（fast_forward_one_commit）→ `gh_push.py push`。建 ref 顺带触发父提交在新分支上的 run（head `643037a`，无害；与真正的 run 按 head SHA 区分）。
- 本文档提交：见本仓库 `v2.0.6` 分支 RUN 提交（单独一笔，在产品提交之后）。

## 1. 版本 2.0.6 / build 36

`LyricStore.versionTag` = `build 36（2.0.6）`；两处 Info.plist（sed 精确改 CFBundleVersion 行＋ShortVersionString 行，未用 plistlib 重写）、pbxproj（MARKETING_VERSION ×6、CURRENT_PROJECT_VERSION ×6）、build.yml（产物名 2.0.6）、TLDHUDVersion.h、SettingsView、PiPLyricsRenderer、HUD fallback 药丸文字、诊断标题 `诊断（2.0.6）` 同步到 2.0.6。

## 2. 根因（审计结论，钉死）

2.0.4 的卡拉OK没效果：字段错配——代码只读 LRCLIB 的 syncedLyrics（只有行级时间戳），逐字数据在 lyricsfile 字段（YAML，每行 words 数组带 start_ms）；2.0.4 的逐字模型期望 enhanced-LRC 内联 `<mm:ss.xx>` 标记，在 syncedLyrics 里永远找不到。开关接线、解析器、药丸与应用内两条渲染链都已核过是对的。另两点审计发现：①缓存键无版本号，老歌缓存里的行 words 永远 nil；②歌卡 normalize 门只去空格，偏窄。

LRCLIB lyricsfile 形状已用公开文档核实：YAML，`version: "1.0"`／`metadata:`／`lines:`（`- text:`／`start_ms:`／`end_ms:`／`words:` 子列表，每词 `text:`／`start_ms:`／`end_ms:`）＋行级 `plain: |` 字面块；search／get 均返回该字段，旧实例可能不发，作 optional 处理。

## 3. 四项修复

### 3a. P0——读 lyricsfile 字段

- `LRCLibClient.swift`：`LRCLyricsRecord` 增加 `lyricsfile: String?` 及可选 `hasWordSync: Bool?`（旧记录缺失时解码为 nil）。
- `LyricParser.swift` 新增 `LyricsFileParser`（手写最小 YAML 解析，零新依赖）：只取 `lines[].text`／`start_ms`／`words[].text`／`words[].start_ms`；`plain: |` 字面块有防护（块内行不被当成行／词项）；字段缺失或解析失败静默返回空，调用方退回行级，绝不崩溃、绝不拦门。算法先用 Python 镜像验证过 23 项（两种缩进风格、引号／冒号文本、`words: []`、脏输入、plain 块陷阱）。
- `PlaybackCoordinator.loadLyrics`：行级时间戳仍从 syncedLyrics 来；有 lyricsfile 时 `mergingWordSync` 把词时间（`start_ms / 1000`）映射成 `LyricLine.words`（行数一致按下标，不一致按归一化行文本对齐）；只有 lyricsfile、没有 syncedLyrics 时 `linesFromLyricsFile` 单独建行（行时间 = `start_ms / 1000`）。lyricsfile 是 YAML，绝不喂给 `LyricParser.parse`。
- `LyricMatcher`：候选放宽为 syncedLyrics 或 lyricsfile 任一在位；打分优先选有 lyricsfile 的候选（+50；只有 hasWordSync 标志、无文件时 +10），否则同一首歌多个版本时可能选中无逐字的记录。

### 3b. P1——诊断日志

- `loadLyrics` 解析后记一行：`歌词匹配成功：<title>（<N> 行，逐字 <M> 行，共 <W> 词）`（M、W 从解析结果取）；旧 plain 成功行已撤，避免日志里两行成功自相矛盾。
- 本地缓存命中也记逐字计数（`本地歌词命中：<title>（<N> 行，逐字 <M> 行，共 <W> 词）`）——重播旧歌走缓存不联网，这是唯一能自证缓存里逐字在不在的日志。
- 守护进程换歌行追加当前行词数：`hud: lyrics now <track> — <artist> (<N> lines, karaoke <W> words)`（`TLDHUDRootViewController.mm`）。

### 3c. P1——缓存键版本化

`LyricStore.cacheKey` 改成 `lyric.cache|v2|…`，旧缓存一次性失效重取。

### 3d. P2——歌卡 normalize 门

`PlaybackDashboardView` 歌卡逐字门复用 `LyricMatcher.normalize`（字母数字归一化；`LyricMatcher.normalize` 去 private）；旧只去空格的闭包已撤。药丸与 LC 应用内区没有这道门，不动它们。

## 4. 未动

其余 2.0.5 内容（HID 注入管线、滑块、卡拉OK开关、20 处兼容）原样保留；激活／Keychain 未动；FrontBoard 老路仍停用；锁屏歌词未恢复；码值扫描 0 命中（验包见 §6）。

## 5. 自检

`check_2.0.6.py`（由 `check_2.0.5.py` 改版：版本断言 2.0.6／36、BASE 改 `643037a`、diff 集改 18 个文件、提交顺序改四笔、§19 卡拉OK四项新断言＋两道回归门）：

- 提交前：518 PASS / 1 FAIL（提交顺序断言，RUN 文档未提交时正常——当时只有三笔，缺 RUN 笔）。
- 提交后复跑：**519 PASS / 0 FAIL** / 9 OPEN（全是真机待测项；比提交前多 1 项是通过的提交顺序断言本身）。

## 6. 构建与验包

- run `46136838949` success；产物：
  - IPA：`~/workspace/your_files/桌面歌詞-2.0.6-newbase.ipa`，**1,759,198 B**，SHA256 `66e70f210dd4fb1054c5e0b22ce02b589ad4e5489cd27bd0c8e48027d2228a2f`
  - dSYM：`~/workspace/your_files/桌面歌词-2.0.6-newbase-dSYM.zip`，**2,759,218 B**，SHA256 `7fa32a8d17371707e84df7339b99843053ab0ff522c8fad33faa1808442c9aaa`
  - 注意：GitHub artifact 下载下来是外层 zip（内含同名文件），已解开取内层真文件；上面尺寸／SHA 都是内层真文件的。外层 zip 保留为 `桌面歌词-2.0.6-artifact.zip`／`桌面歌词-2.0.6-dSYM-artifact.zip`（`hidden_files/artifact-2.0.6/`）。
- `hidden_files/verify_2.0.6.py`：**205 PASS / 0 FAIL**（exit 0，日志 `hidden_files/verify_2.0.6.log`）。要点：
  - bundle id `com.ycwl.Lyrics`，版本 2.0.6 / build 36（App＋Widget Info.plist），MinOS 15.0。
  - thin arm64 ×3（App／Widget／daemon，无 arm64e 混装）。
  - dSYM UUID 与二进制一致 ×3。
  - entitlements 与 build 35 比对：零差异（这次不改权限）。
  - 逃逸检查点：App 仍为 **2 个** call sites（0x44A5C 崩点没回来）。daemon 无 `swift_isEscapingClosureAtFileLocation`。
  - 新字串在位：`lyricsfile`（App 二进制）；缓存键 `lyric.cache|v2|` 不作二进制断言——插值字串首段 15 字节，Swift Release 下压成 small-string immediate，字节扫描不到（实测三二进制全是 -1），键本身由源码级断言保证（check_2.0.6.py §19 精确行）。
  - 旧版字串不在位：`build 35`、`桌面歌詞 2.0.5`、`悬浮测试 · 桌面歌词 2.0.5`。裸 `2.0.5` 只剩 daemon 签名 entitlements blob 里注释中的两处（"2.0.5 (Lee approved the full HID touch port…"，批注 hid.* 键是 2.0.5 时批准的，与版本号无关），验包已断言两处都在 daemon 且附近都有 "Lee approved"。
  - 码值扫描 `TLD-XXXX-XXXX-XXXX`：0 命中。
  - dSYM UUID：App `68bfcfbb9e333ab7bffea8943ddb06b0`、Widget `58bbc4b012523376a0b777abc5b9604d`、daemon `271688851a103773a90dab672294000e`，三二进制一致。

### 6a. 两次构建失败与修法（真失败，非池子取消）

1. **run 46134758976（head 55afea9），第 4 步 Engine regression tests failure。** 日志：`LyricParser.swift:223:28: error: cannot find 'LyricMatcher' in scope`（×2）。根因：我的 `mergingWordSync` 行对齐调了 `LyricMatcher.normalize`，但 CI 引擎测试的 swiftc 列表只编 `LyricParser.swift`，不含 `LyricMatcher.swift`。修法（`64a6a7b`）：swiftc 列表补 `PlaybackEngine/LyricMatcher.swift`＋`Lyrics/LRCLibClient.swift`（Matcher 依赖的 `LRCLyricsRecord` 在后者）；`EngineTests/main.swift` 追加 2.0.6 回归断言（lyricsfile 解析＋合并＋脏输入），并把末尾打印从 Build 34 改成 Build 36。
2. **run 46135798827（head 64a6a7b），第 6 步 Archive (unsigned) failure。** 日志：同一错误 `LyricParser.swift:223: cannot find 'LyricMatcher' in scope`——这次是 Xcode archive 编 Widget：`LyricParser.swift` 在 App＋Widget 两个 target 的 Sources 里，`LyricMatcher.swift` 只在 App 里。修法（`aebd725`）：`LyricsFileParser` 自带一份同规则归一化（小写＋只留字母数字），不再引 `LyricMatcher`；歌卡那道门仍复用 `LyricMatcher.normalize`（App target 才有它，不受影响）。check_2.0.6.py §19 加两道回归门（`LyricParser.swift` 不引 `LyricMatcher`、自带归一化在位）。
3. 轮询脚本本身也有两个 bug（与构建无关）：第一次把 gh_api.py `runs` 输出的键当成 `workflow_runs`（实为 `runs`），12 轮空转超时；第二次读 `status`（HTTP 200 恒值）而不是 `status_field`——正是 AGENTS.md 2026-11-23 那条实锤教训重演。两次都已修（`runs` 键＋`status_field`），第三次轮询第 3 轮即报 success。

## 7. 给 Lee 的真机测试清单

1. 覆盖安装本 IPA（免激活应仍通过，同 2.0.5/build 35 行为），启用 HUD 守护进程。
2. 卡拉OK（本次主修）：放一首有逐字词的歌，药丸当前行逐字亮（已唱金色、未唱灰色）；主页面歌卡大字那行同样逐字亮。
3. 日志自证：守护进程日志找 `hud: lyrics now … karaoke N words`（N > 0 说明逐字已进快照）；主 App 日志找 `歌词匹配成功：…（N 行，逐字 M 行，共 W 词）`（M、W > 0 说明解析拿到了逐字）。
4. 若逐字仍不亮：先看上面两行日志——两行都是 0 是服务端这首歌没逐字数据／匹配到了无逐字版本；App 行有数、药丸行是 0 是快照／守护进程侧问题；两行都有数还不亮才是渲染问题。把两行日志发回。
5. 其余回归与 2.0.5 清单一致（药丸拖动、药丸外不干扰、滑块定位、颜色／透明度／字号、固定位置、10 次锁解、30 分钟后台）。

## 8. 未决／待 Lee

- 以上 5 项真机测试等 Lee。
- 逐字数据依赖 LRCLIB 该歌曲记录带 lyricsfile：没逐字词的歌（M、W 均为 0）退回整行高亮，是数据源问题，不是本版坏的。

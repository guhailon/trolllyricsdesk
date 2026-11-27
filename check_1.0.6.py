#!/usr/bin/env python3
"""Verify TrollLyricsDesk 1.0.6 build 26 (前台复核兜底):

base = newbase HEAD 4f43991 (1.0.5 源码，build 19)
  + build 21（2026-11-27 02:18 令，只修最可疑一处——启动时重建竞态）：
    1.0.6 build 20 在 LC 机（硬件 iPhone 13 Pro，iOS 27.0.1）上进主页面就闪退，
    1.0.5 同台不闪；皇上 02:19 证实崩的时机是「主页面立刻闪」。
    病根：DidBecomeActive（主页面出现时触发）或 2 秒看门狗在悬浮场景
    「已创建、未连上」的窗口里调 rebuild，rebuild 对正在连接的会话
    请求 requestSceneSessionDestruction，和 UIKit 连接流程撞车。
    修法：新锚点 floatingSceneEverConnected（创建时清 NO，willConnectToSession
    跑过才置 YES）；rebuild 只有旧场景曾经连上才销毁，否则跳过销毁、
    只摘 binder＋藏窗口（走 1.0.5 的做法）；触发侧（DidBecomeActive／
    2 秒看门狗）在连接窗口里跳过这次恢复。1.0.6 其余全部不动，
    不修 isPlaying 探针（#2），不加新功能。
  + build 21 第二处（皇上 2026-11-27 02:27 定，两个都修）：
    SecTaskCopyValueForEntitlement 三参数修——CopyFn 由 2 参数改 3 参数
    （task、key、CFErrorRef *error），调用补 nil；2 参数版是真隐患
    （哪个键查不到就真崩），但 7 个键在 entitlements 里全都有、查都会成功，
    且它跑在主页面出现之前，所以这次「主页面立刻闪」很可能不是它。
  + build 24（2026-11-27 10:20 令，巨魔主线修复版——LC 宿主研究暂停，
    巨魔版 iPhone 11 是正式开发主线；皇上 10:22 定不上源，不部署到越狱源）：
    只做五件——(1) LC 环境识别修复：LC_HOME_PATH 环境变量排第一
    （旧统一版信号一，commit 893f066）＋包路径 /Documents/Applications/
    （旧线信号二），检测时把进程名／Home／bundle／argv[0]／各信号值写进日志；
    (2) 诊断日志版本标记：写死的 "build 22" 改走 LyricStore.versionTag
    统一常量（build 24），TLDSAppDelegate.m:784 运行时字串里的 "build 21"
    也去掉；(3) dSYM：build.yml 同时上传 dSYM 产物（与 IPA 同一个 run）；
    (4) 完整诊断日志保留：OverlayDiagnostics.logSummary() 接到
    setRunMode（全树无调用者是 1.0.5 的教训重演）；(5) 权限不足安全降级：
    只审计，确有真实 trap 风险才最小修法——审计结论是无真实风险处，
    不改代码；@escaping 修法不动，逃逸检查点保持 2 个。
  + 皇上 10 项（2026-11-26 22:59 令）：
    1. RuntimeEnvironment 重写：禁止「非 LC 就当 TrollStore」；
       TrollStore 必须用正面证据判（EffectiveEntitlements 实测）。
    2. 三项判定分离：安装环境／实际权限／显示能力各自独立判定、各自记日志；
       托管复核只定显示能力，禁止它直接改安装环境类型。
    3. PlaybackCoordinator.start() 幂等：整个会话只留一个有效检测任务、
       一个轮询定时器（真机日志里一次启动跑了 12 次）。
    4. MediaRemote 诊断再分细：无音乐／空数据 info=nil／调用超时／权限受限／
       数据解析失败各有各的日志行和诊断页状态；isPlaying 探针区分
       「没放歌」与「放着歌还读不到（P0）」——23:24 在 LC 机上坐实：
       iPhone 18 Pro Max／iOS 27.0.1／LiveContainer，QQ 音乐在播，
       GetNowPlayingInfo 回调一次、info=nil。
    5. 进程实际有效 entitlements（SecTask 实测＋沙盒外写探测，
       不得只看 IPA 声明）；LC 客人继承不到宿主没有的权限。
    6. 悬浮窗可见性误判修正：Context ID 未知记「未知」，不进判定；
       结论改「托管结构检查通过；实际屏幕可见性未确认」，
       不再用「已确认可见」盖过去。
    7. 激活前后悬浮窗状态检查（各记一次快照，激活成功不应丢窗）。
    8. LC 后台运行及进程终止原因（系统杀／宿主杀／自己退，查不到写「原因未知」；
       23:23 重测：进程后台只活约 3 分钟就被终止）。
    9. PiP 独立验证：固定文字段与实时歌词段分开验，各有各的状态。
    10. 保留：巨魔原生悬浮歌词、激活接口 POST /api/verify 不变、
        逐歌偏移、Engine Fix 全部修复。
  + ChatGPT 1.0.6 ZIP 选择性并入（皇上 23:18 批准）：
    MediaRemote 签名修正（GetNowPlayingInfo 回调改 block、
    注册改只收队列——1.0.5 的假回调系统根本不调，可能是 LC 里 info=nil
    的直接原因）、start() 幂等、native-candidate、可见性收紧、
    诊断页诚实文案、版本 1.0.6／build 20。
    不在 ZIP 里的继续按 10 项做：14:59:44 第二个悬浮窗（重建先销毁旧窗）、
    LC 实际有效权限测量（第 5 项）、后台保活专项、PiP 渲染优化（第 8／9 项）。
  + build 25（2026-11-27 14:30 令，皇上点选「做 build 25：启动＋回前台重建兜底」）：
    只修悬浮窗一定回来——(1) Shell 回调没来、场景一次都没建过时，2 秒看门狗／
    回到前台直接建一次（与回调同款入口；回调晚到时有守卫，不建第二个窗；
    启动 2 秒内不抢建，给回调先到的机会）；(2) 场景建了 10 秒还没连上判卡住，
    不再无限跳过，走重建（rebuild 本身对未连上的场景跳过销毁，不撞车）；
    #1 守卫（连接窗口内跳过）不动，解锁重建原样不动，保活不动，@escaping 不动，
    逃逸检查点保持 2 个。版本 1.0.6／build 25。
  + build 26（2026-11-27 15:14 令，皇上点选「直接修，加兜底复核」）：
    只加前台复核兜底——build 25 真机验：①冷启动退主屏幕有窗、③锁屏久一点→
    解锁→打开一次 App 窗回来，②锁屏→解锁主屏幕没窗；15:04 日志坐实解锁重建
    跑了（15:04:30「锁屏恢复：完整重建悬浮场景」），但重建是在后台跑的，
    窗只有打开 App 主页面（回前台）才回来。修法：回前台 1.5 秒后验悬浮窗真在
    不在（窗口非空／isHidden=NO／alpha>0／windowScene 非空／视图已挂上），
    在就记「在，不动」，不在就走现成的 rebuildFloatingOverlay（触发：
    foreground-verify）；场景刚建好还在连接时不到 2 秒不判「不在」（最多再排
    一次），10 秒卡住线复用 build 25；重建 3 秒节流内被拦住时 3.5 秒后再验一次；
    解锁重建、看门狗、build 25 启动兜底、#1 守卫、保活、@escaping 全不动，
    逃逸检查点保持 2 个。版本 1.0.6／build 26。
  + 版本 1.0.6, build 26, 包名 com.ycwl.Lyrics；不加权限、不加 TCP 桥／
    独立客户端／双 IPA；不恢复锁屏歌词；不修改现有 UI。
  + 1.0.5 的功能（五件／激活／三档／三渲染器／PiP 实验／Engine Fix／
    同步修正）全部保留，只做加法诊断与判定分离。

FAILED: none is the goal. OPEN items are recorded, not failures:
things that cannot be verified on Linux (macOS compile, device) or that
need Lee's device test.

Red-line anchor: BASE = 4f43991 (1.0.5 source). git diff BASE..HEAD
must touch only the allow-listed files; LyricStore 同步修正与逐歌偏移
代码的删行不得含同步修正符号（1.0.6 的 LyricStore 有结构改动，
不再要求零删行，只要求同步修正符号一字未动）。
"""
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
BASE = "4f43991"
fails = []
opens = []


def check(name, ok, detail=""):
    print(f"{'PASS' if ok else 'FAIL'}  {name}  {detail}")
    if not ok:
        fails.append(name)


def open_item(name, detail=""):
    print(f"OPEN  {name}  {detail}")
    opens.append(name)


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def git_out(args):
    return subprocess.check_output(
        ["git"] + args, cwd=ROOT, text=True)


def pbx_sources_files(pbx_text, phase_id):
    m = re.search(re.escape(phase_id)
                  + r" /\* PBXSourcesBuildPhase \*/ = \{(.*?)\n\t\t\};",
                  pbx_text, re.S)
    if not m:
        return []
    out = []
    for bf in re.findall(r"([0-9A-F]{24})", m.group(1)):
        fm = re.search(re.escape(bf)
                       + r" /\* [^*]*\*/ = \{\s*isa = PBXBuildFile;"
                       + r"\s*fileRef = ([0-9A-F]{24})",
                       pbx_text)
        if not fm:
            continue
        fr = fm.group(1)
        rm = re.search(re.escape(fr)
                       + r" /\* [^*]*\*/ = \{\s*isa = PBXFileReference;"
                       + r"\s*lastKnownFileType = [^;]+;"
                       + r"\s*name = \"?([^\n\";]+)\"?;",
                       pbx_text)
        out.append(rm.group(1).strip().strip('"') if rm else fr)
    return out


def pbx_resolved_files(pbx_text):
    objs = {}
    cur = None
    for ln in pbx_text.split("\n"):
        m = re.match(r"\t\t([0-9A-F]{24}) /\* (.*?) \*/ = \{$", ln)
        if m:
            cur = {"id": m.group(1), "children": [], "path": None}
            objs[m.group(1)] = cur
            continue
        if cur is not None:
            m2 = re.match(r"\t\t\tisa = (\w+);", ln)
            if m2:
                cur["isa"] = m2.group(1)
            m3 = re.match(r'\t\t\tpath = "?([^";]+)"?;', ln)
            if m3:
                cur["path"] = m3.group(1)
            if re.match(r"\t\t\tchildren = \(", ln):
                cur["in_children"] = True
                cur["children"] += re.findall(r"[0-9A-F]{24}", ln.split("(", 1)[1])
                if ");" in ln:
                    cur["in_children"] = False
                continue
            if cur.get("in_children"):
                cur["children"] += re.findall(r"[0-9A-F]{24}", ln)
                if ");" in ln:
                    cur["in_children"] = False
                continue
            if ln.strip() == "};":
                cur = None
    main_group = None
    for ln in pbx_text.split("\n"):
        m = re.match(r"\t\t\tmainGroup = ([0-9A-F]{24});", ln)
        if m:
            main_group = m.group(1)
            break
    resolved = []

    def walk(gid, prefix):
        g = objs.get(gid)
        if not g:
            return
        base = os.path.join(prefix, g["path"]) if g.get("path") else prefix
        for c in g.get("children", []):
            o = objs.get(c)
            if not o:
                continue
            if o.get("isa") == "PBXGroup":
                walk(c, base)
            elif o.get("isa") == "PBXFileReference" and o.get("path"):
                if re.search(r"\.(swift|plist|entitlements|xcassets)$", o["path"]):
                    resolved.append(os.path.join(base, o["path"]))

    if main_group:
        walk(main_group, "")
    return resolved


print("== 1. 新文件 ==")
for rel in ["App/ActivationView.swift"]:
    check(f"exists: {rel}", os.path.exists(os.path.join(ROOT, rel)))
# 1.0.5 锁屏已取消（皇上 2026-11-26 21:46 令）：两个锁屏文件必须不在
for rel in ["LiveActivity/LyricsLiveActivity.swift",
            "PlaybackEngine/LyricsLiveActivityController.swift"]:
    check(f"removed: {rel} 不在（锁屏已取消）",
          not os.path.exists(os.path.join(ROOT, rel)))

print("\n== 2. 版本 / 包名 / MinOS ==")
for rel in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]:
    pl = plistlib.loads(open(os.path.join(ROOT, rel), "rb").read())
    check(f"{rel}: version 1.0.6", pl.get("CFBundleShortVersionString") == "1.0.6",
          str(pl.get("CFBundleShortVersionString")))
    check(f"{rel}: build 28", pl.get("CFBundleVersion") == "28",
          str(pl.get("CFBundleVersion")))
    check(f"{rel}: min OS 15.0", pl.get("MinimumOSVersion") == "15.0",
          str(pl.get("MinimumOSVersion")))
app_pl = plistlib.loads(open(
    os.path.join(ROOT, "TrollLyricsDesk/Info.plist"), "rb").read())
check("app Info.plist: bundle id com.ycwl.Lyrics",
      app_pl.get("CFBundleIdentifier") == "com.ycwl.Lyrics")
check("app Info.plist: display name 桌面歌词",
      app_pl.get("CFBundleDisplayName") == "桌面歌词")
check("app Info.plist: NSSupportsLiveActivities 不在（锁屏已取消）",
      "NSSupportsLiveActivities" not in app_pl)
check("app Info.plist: no TLDSLiveActivities key / no TLDSLiveContainer=true",
      app_pl.get("TLDSLiveContainer") is not True)
check("widget Info.plist: no TLDSLiveContainer=true",
      plistlib.loads(open(os.path.join(ROOT, "TrollLyricsWidget/Info.plist"),
                          "rb").read()).get("TLDSLiveContainer") is not True)

print("\n== 3. 底子同步修正（保新底子，Universal 全缺的那些）在位 ==")
ls = read("Lyrics/LyricStore.swift")
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
for s in ["timeOffset", "offsetKeyPrefix", "stableSongIdentity",
          "artistCarriesLyric", "songIdentityParts"]:
    check(f"LyricStore: {s} 在位", s in ls)
check("LyricStore: noMusicKey 在位", "noMusicKey" in ls)
check("LyricStore: floatingEnabledChanged 在位", "floatingEnabledChanged" in ls)
for s in ["noMusicKey", "isDisplayEquivalent", "syncLiveLyricsAndProgress"]:
    check(f"PlaybackCoordinator: {s} 在位", s in pc)
check("PlaybackCoordinator: state = newState 仍在（节流赋值未被 Universal 覆盖）",
      "state = newState" in pc)
td = read("Overlay/TLDSAppDelegate.m")
check("TLDSAppDelegate: 锁屏重建回调 needsRebuildOnUnlock 在位",
      "needsRebuildOnUnlock" in td)
check("TLDSAppDelegate: isProtectedDataAvailable 解锁轮询在位",
      "isProtectedDataAvailable" in td)
sd = read("Overlay/TLDSSceneDelegate.m")
check("TLDSSceneDelegate: hasPrefix 匹配悬浮 scene（保新底子）",
      'hasPrefix:@"TLDSFloatingLyric"' in sd)

print("\n== 4. 激活 ==")
av = read("App/ActivationView.swift")
check("ActivationView: ActivationGateView + ActivationVerifier.verify",
      "struct ActivationGateView" in av and "static func verify(code:" in av)
check("ActivationView: wrong code -> 激活码不正确",
      "激活码不正确" in av)
check("ActivationView: no network -> 需要联网激活",
      "需要联网激活" in av)
check("ActivationStore: verify URL + keys tld.activated / tld.activationType",
      "https://guhailong-repo.pages.dev/api/verify" in ls
      and '"tld.activated"' in ls and '"tld.activationType"' in ls)
check("ActivationStore: isActivated + markActivated",
      "static var isActivated" in ls and "static func markActivated" in ls)
ta = read("App/TrollLyricsDeskApp.swift")
check("TrollLyricsDeskApp: 根视图包 ActivationGateView",
      "ActivationGateView {" in ta)
fl = read("Overlay/FloatingLyricViewController.swift")
check("FloatingLyricViewController: 未激活时悬浮窗隐藏",
      "view.isHidden = !floatingEnabled || !ActivationStore.isActivated" in fl)
wv = read("TrollLyricsWidget/WidgetView.swift")
check("WidgetView: 未激活占位「请先在 App 内激活」",
      "请先在 App 内激活" in wv and "notActivatedView" in wv)

print("\n== 5. 五件 ==")
about = read("App/AboutView.swift")
check("AboutView: Telegram 标签 @Guhailon",
      '"@Guhailon"' in about)
check("AboutView: tg://resolve?domain=Guhailon, 退回 https://t.me/Guhailon",
      '"tg://resolve?domain=Guhailon"' in about
      and '"https://t.me/Guhailon"' in about)
check("AboutView: 无旧邀请链接、无 @seadragonjb",
      "tg://join?invite=" not in about and "I-I8aw7HUAw1NGY9" not in about
      and "@seadragonjb" not in about)
lv = read("App/LogView.swift")
check("LogView: 复制按钮 + copiedFeedback（清理不动）",
      "copiedFeedback" in lv
      and "UIPasteboard.general.string = LyricLogger.read()" in lv
      and '"已复制"' in lv and "asyncAfter" in lv)
check("LogView: 现有清理仍在（clearLogs / 清理日志）",
      "clearLogs()" in lv and "清理日志" in lv)
cv = read("App/ContentView.swift")
check("AppBackgroundView 在 ContentView.swift（无新文件）",
      "struct AppBackgroundView: View" in cv)
check("AppBackgroundView: 三个键（走 LyricStore.defaults）",
      '"animeBackgroundEnabled"' in cv and '"backgroundOpacity"' in cv
      and '"selectedBackgroundData"' in cv
      and cv.count('store: LyricStore.defaults') >= 3)
check("AppBackgroundView: 关->纯黑；有图 scaledToFill，透明度 1-backgroundOpacity",
      "Color.black" in cv and "if animeBackgroundEnabled" in cv
      and "UIImage(data: selectedBackgroundData)" in cv
      and ".scaledToFill()" in cv
      and ".opacity(1 - backgroundOpacity)" in cv)
check("AppBackgroundView: 无图->原渐变",
      "Color.purple.opacity(0.8)" in cv and "Color.blue.opacity(0.5)" in cv)
check("四处用 AppBackgroundView（SettingsHub／Content／About／Dashboard）",
      cv.count("AppBackgroundView()") == 2
      and "AppBackgroundView()" in about
      and "AppBackgroundView()" in read("App/PlaybackDashboardView.swift"))
check("四处根渐变已替掉（AppBackgroundView 外无写死渐变）",
      cv.count("LinearGradient(") == 1
      and "LinearGradient(" not in about
      and "LinearGradient(" not in read("App/PlaybackDashboardView.swift"))
pd = read("App/PlaybackDashboardView.swift")
check("Dashboard: positionLocked 键（App Group，默认 false）",
      '"floatingLyric.positionLocked"' in pd
      and "private var positionLocked = false" in pd)
check("Dashboard: Toggle 固定悬浮窗位置在显示开关下、取色器上",
      '"固定悬浮窗位置"' in pd
      and pd.index('"固定悬浮窗位置"') > pd.index('"显示悬浮歌词窗"')
      and pd.index('"固定悬浮窗位置"') < pd.index('"悬浮窗歌词颜色"'))
check("Dashboard: 提示行跟锁走（悬浮窗口 · 已固定／长按拖动 · 双击隐藏）",
      '"悬浮窗口 · 已固定 · 双击隐藏"' in pd
      and '"悬浮窗口 · 长按拖动 · 双击隐藏"' in pd)
check("Dashboard: 标题居中（ZStack topTrailing＋frame maxWidth center，齿轮仍右上）",
      "ZStack(alignment: .topTrailing)" in pd
      and '.frame(maxWidth: .infinity, alignment: .center)' in pd
      and '"桌面歌词"' in pd and ".padding(.top, 80)" in pd)
check("FloatingLyricViewController: positionLockedKey + handlePan guard",
      '"floatingLyric.positionLocked"' in fl
      and "guard !positionLocked else { return }" in fl)
check("FloatingLyricViewController: 无 hintLabel（新底子本来就没有）",
      "hintLabel" not in fl)
check("FloatingLyricViewController: save/restore 位置未动",
      "private func savePosition(center: CGPoint)" in fl
      and "private func restorePosition()" in fl)

print("\n== 6. 锁屏已取消（皇上 2026-11-26 21:46 令，真机从未证实可用） ==")
check("锁屏文件不在：LiveActivity/LyricsLiveActivity.swift",
      not os.path.exists(os.path.join(ROOT, "LiveActivity/LyricsLiveActivity.swift")))
check("锁屏文件不在：PlaybackEngine/LyricsLiveActivityController.swift",
      not os.path.exists(os.path.join(ROOT, "PlaybackEngine/LyricsLiveActivityController.swift")))
check("coordinator: LiveLyricKey／lastLiveState／lastLiveActivityID 不在",
      "LiveLyricKey" not in pc and "lastLiveState" not in pc
      and "lastLiveActivityID" not in pc)
check("coordinator: publishLiveLyrics／isRunning／ensureRunning 不在",
      "publishLiveLyrics" not in pc and "isRunning" not in pc
      and "ensureRunning" not in pc)
check("coordinator: 同步修正还在（删锁屏没碰同步）",
      "syncLiveLyricsAndProgress" in pc and "isDisplayEquivalent" in pc
      and "noMusicKey" in pc)
check("ContentView: 锁屏歌词区不在（标题／开关／宿主文案／小组件提示全删）",
      '"锁屏歌词"' not in cv and '"开启锁屏歌词"' not in cv
      and '"停止锁屏歌词"' not in cv
      and "LiveContainer 模式不支持锁屏歌词和小组件" not in cv
      and "LiveActivitySectionView" not in cv
      and "锁屏小组件：长按锁屏" not in cv)
wg = read("TrollLyricsWidget/TrollLyricsWidget.swift")
check("widget: accessoryRectangular 不在（只留 systemSmall／systemMedium）",
      ".accessoryRectangular" not in wg
      and ".systemSmall" in wg and ".systemMedium" in wg)
check("WidgetView: 锁屏分支／lockScreenView／nextLyricText 不在",
      "family == .accessoryRectangular" not in wv
      and "lockScreenView" not in wv and "nextLyricText" not in wv)
wb = read("TrollLyricsWidget/TrollLyricsWidgetBundle.swift")
check("WidgetBundle: LyricsLiveActivity 不再注册",
      "LyricsLiveActivity()" not in wb)

print("\n== 7. Universal 兼容层 ==")
check("LyricStore: isLiveContainer（三路：plist 键／路径／LCAppDelegate）",
      "static var isLiveContainer: Bool" in ls
      and '"TLDSLiveContainer"' in ls
      and '"livecontainer"' in ls and '"/lcapps/"' in ls
      and 'NSClassFromString("LCAppDelegate")' in ls)
check("LyricStore: defaults 三元（宿主走 .standard）",
      "isLiveContainer ? .standard : UserDefaults(suiteName: groupID)" in ls)
check("TrollLyricsDeskApp: @objc isHosted() + 保活宿主时不启动",
      "@objc func isHosted() -> Bool { LyricStore.isLiveContainer }" in ta
      and "if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }" in ta)
check("TLDSAppDelegate: 四分支启动判定（巨魔定档不复核／宿主待探测／普通签名直接兼容／未知 native-candidate）",
      "TLDSInstallNativeWindowFix" in td
      and 'setRunMode:@"trollstore"' in td
      and 'setRunMode:@"native-candidate"' in td
      and "self.modeDecided = YES;" in td
      and "self.shouldVerify = NO;" in td
      and "self.shouldVerify = YES;" in td
      and "TLDSInstallNativeWindowFix();" in td
      and "[self startFloatingOverlay];" in td)
check("TLDSSceneDelegate: 宿主只在已判兼容时强制 isMain = YES; isFloating = NO（1.0.5 三档）",
      "if ([[TLDSRuntime shared] isHosted] && appDelegate.compatMode)" in sd
      and "isMain = YES;" in sd and "isFloating = NO;" in sd)
check("Dashboard: 宿主显示「LiveContainer · 应用内歌词模式」+ 0.25s TimelineView",
      "LiveContainer · 应用内歌词模式" in pd
      and "TimelineView(.periodic(from: .now, by: 0.25))" in pd)
n_guarded = 0
for rel in ["PlaybackEngine/PlaybackCoordinator.swift",
            "App/LyricsSearchView.swift", "App/ContentView.swift",
            "App/SettingsView.swift", "App/ActivationView.swift"]:
    t = read(rel)
    n_guarded += t.count(
        "if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }")
check("5 处 WidgetCenter.reloadAllTimelines() 全部加宿主 guard（共 10 处调用点）",
      n_guarded == 10, f"guarded={n_guarded}")
all_swift = ""
for dirpath, _, filenames in os.walk(ROOT):
    if ".git" in dirpath or "hidden_files" in dirpath:
        continue
    for fn in filenames:
        if fn.endswith(".swift"):
            all_swift += open(os.path.join(dirpath, fn),
                              encoding="utf-8").read() + "\n"
check("无 TCP 桥 / 独立客户端 / 双 IPA 痕迹",
      "38473" not in all_swift and "DualProcessBridge" not in all_swift
      and "TLDSLiveContainer" not in read("TrollLyricsDesk/Info.plist")
      and "build-livecontainer" not in all_swift.lower())

print("\n== 8. pbxproj ==")
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("pbxproj: LiveActivity 组不在（锁屏已取消）",
      'name = "LiveActivity"' not in pbx and "LyricsLiveActivity" not in pbx)
app_sources = pbx_sources_files(pbx, "4821909E9BF9E73E471FEA84")
check("pbxproj: 锁屏两文件不在 App Sources，只留 ActivationView.swift",
      "ActivationView.swift" in app_sources
      and "LyricsLiveActivity.swift" not in app_sources
      and "LyricsLiveActivityController.swift" not in app_sources,
      str(app_sources))
check("pbxproj: EffectiveEntitlements.swift 进 App Sources（1.0.6 第 5 项新文件）",
      "EffectiveEntitlements.swift" in app_sources, str(app_sources))
widget_sources = pbx_sources_files(pbx, "37A859133C5B7A49CE597D35")
check("pbxproj: LyricsLiveActivity.swift 不在 Widget Sources",
      "LyricsLiveActivity.swift" not in widget_sources, str(widget_sources))
check("pbxproj: ActivityKit 弱链接 0 处（锁屏已取消，无强链接）",
      pbx.count('"-weak_framework"') == 0 and pbx.count('"ActivityKit"') == 0
      and "ActivityKit.framework" not in pbx,
      f"weak={pbx.count(chr(34) + '-weak_framework' + chr(34))}")
check("pbxproj: .tbd 直链 4 条未动（Debug＋Release 各一份，共 8 行）",
      pbx.count("FrontBoard.tbd") == 2
      and pbx.count("FrontBoardServices.tbd") == 2
      and pbx.count("RunningBoardServices.tbd") == 2
      and pbx.count("AppleAccount.tbd") == 2)
check("pbxproj: MARKETING_VERSION 1.0.6（4 处），MinOS 15.0",
      pbx.count("MARKETING_VERSION = 1.0.6;") == 4
      and "IPHONEOS_DEPLOYMENT_TARGET = 16.0" not in pbx)
check("pbxproj: CURRENT_PROJECT_VERSION 28（4 处）",
      pbx.count("CURRENT_PROJECT_VERSION = 28;") == 4,
      f"count={pbx.count('CURRENT_PROJECT_VERSION = 28;')}")
check("pbxproj: 包名 com.ycwl.Lyrics（App 2 处）＋ Widget 后缀",
      pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.ycwl.Lyrics;") == 2
      and pbx.count("PRODUCT_BUNDLE_IDENTIFIER = com.ycwl.Lyrics.TrollLyricsWidget;") == 2)
_resolved = pbx_resolved_files(pbx)
for f in ["App/ActivationView.swift"]:
    check(f"pbxproj: resolves {f}", f in _resolved)
missing = [r for r in _resolved if not os.path.exists(os.path.join(ROOT, r))]
check("pbxproj: 所有引用文件都在磁盘上", not missing, str(missing))
obj_ids = set(re.findall(r"\t\t([0-9A-F]{24}) /\* \w+ \*/ = \{", pbx))
dangling = [fr for fr in re.findall(r"fileRef = ([0-9A-F]{24});", pbx)
            if fr not in obj_ids]
check("pbxproj: 无悬空 fileRef", not dangling, str(dangling))
check("pbxproj: 括号平衡",
      pbx.count("{") == pbx.count("}") and pbx.count("(") == pbx.count(")"))

print("\n== 9. 红线 ==")
for bad in ["TLHUD", "TLHUDApplication", "dynamic_lookup",
            "38473", "DualProcessBridge"]:
    check(f"全树无 {bad!r}", bad not in all_swift
          and bad not in pbx
          and bad not in read(".github/workflows/build.yml"))
check("全树无 BackBoard 实现（只允许 EntitlementDiagnostics 对照表提一次名字）",
      all_swift.count("BackBoard") == 1
      and "BackBoard" in read("Compatibility/EntitlementDiagnostics.swift")
      and "BackBoard" not in pbx
      and "BackBoard" not in read(".github/workflows/build.yml"))
tracked = git_out(["ls-files"]).splitlines()
check("build/ 不在仓库里", not [f for f in tracked if f.startswith("build/")])
check("hidden_files/ 不在仓库里",
      not [f for f in tracked if f.startswith("hidden_files/")])
check("无 *.ipa / *.tipa 进仓库",
      not [f for f in tracked if f.endswith(".ipa") or f.endswith(".tipa")])
core_mr_changed = git_out(["diff", "--name-only", BASE, "HEAD", "--",
                             "Core/", "MusicProviders/"]).splitlines()
check("Core/ 一字未动；MusicProviders/ 只动 MediaRemoteAdapter.swift（1.0.6 第 4 项）",
      "Core/MediaRemoteBridge.swift" not in core_mr_changed
      and sorted(core_mr_changed) == sorted([
          "MusicProviders/MediaRemoteAdapter.swift"]),
      str(core_mr_changed))
changed = git_out(["diff", "--name-only", BASE, "HEAD"]).splitlines()
allowed = {
    "App/ActivationView.swift",
    "App/SettingsView.swift", "App/TrollLyricsDeskApp.swift",
    "Compatibility/EffectiveEntitlements.swift",
    "Compatibility/EntitlementDiagnostics.swift",
    "Compatibility/RuntimeCapabilities.swift",
    "Compatibility/RuntimeEnvironment.swift",
    "Diagnostics/DiagnosticsView.swift",
    "Diagnostics/MediaRemoteDiagnostics.swift",
    "Diagnostics/OverlayDiagnostics.swift",
    "Lyrics/LyricStore.swift",
    "MusicProviders/MediaRemoteAdapter.swift",
    "Overlay/FloatingLyricViewController.swift",
    "Overlay/TLDSAppDelegate.h", "Overlay/TLDSAppDelegate.m",
    "Overlay/TLDSSceneDelegate.m",
    "PlaybackEngine/PlaybackCoordinator.swift",
    "Renderer/InAppLyricsRenderer.swift",
    "Renderer/LyricsRenderer.swift",
    "Renderer/NativeHUDRenderer.swift",
    "Renderer/PiPFrameRenderer.swift",
    "Renderer/PiPLyricsRenderer.swift",
    "TrollLyricsDesk.xcodeproj/project.pbxproj",
    "TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist",
    ".github/workflows/build.yml",
    "check_1.0.6.py", "RUN_1.0.6.md",
}
extra = [f for f in changed if f not in allowed]
check(f"红线 diff {BASE}..HEAD 只动允许文件", not extra, str(extra))
overlay_changed = [f for f in changed if f.startswith("Overlay/")]
check("Overlay/ 只动四处（FloatingLyric／AppDelegate.h+.m／SceneDelegate）",
      sorted(overlay_changed) == sorted([
          "Overlay/FloatingLyricViewController.swift",
          "Overlay/TLDSAppDelegate.h", "Overlay/TLDSAppDelegate.m",
          "Overlay/TLDSSceneDelegate.m"]),
      str(overlay_changed))
for rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
            "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    head = git_out(["show", f"{BASE}:{rel}"])
    check(f"{rel}: 与底子一字未动（零新增权限）", read(rel) == head)
for f in ["App/ActivationView.swift", "App/ContentView.swift",
          "App/PlaybackDashboardView.swift", "Lyrics/LyricStore.swift",
          "Lyrics/LyricParser.swift", "MusicProviders/MediaRemoteAdapter.swift",
          "PlaybackEngine/PlaybackCoordinator.swift",
          "TrollLyricsWidget/WidgetView.swift"]:
    t = read(f)
    check(f"{f}: 花括号平衡", t.count("{") == t.count("}"),
          f"{{={t.count(chr(123))} }}={t.count(chr(125))}")
build_yml = read(".github/workflows/build.yml")
check("build.yml: 产物已升 桌面歌词-1.0.6.ipa（一个 workflow）",
      "桌面歌词-1.0.6.ipa" in build_yml
      and "桌面歌词-1.0.5" not in build_yml
      and "name: Build" in build_yml)


print("\n== 11. 1.0.5 诊断（7 项＋三档模式） ==")
bridge = read("Core/MediaRemoteBridge.swift")
mrd = read("Diagnostics/MediaRemoteDiagnostics.swift")
check("MediaRemoteBridge: 调 recordDlopen／recordDlsym 上报（记录集中在 Diagnostics）",
      "recordDlopen" in bridge and "recordDlsym" in bridge
      and "lastDLError" in bridge)
check("MediaRemoteDiagnostics: dlopen／dlsym 日志行（成功／失败＋原因，只记一次）",
      "dlopen 成功" in mrd and "dlopen 失败" in mrd
      and "dlsym" in mrd and "loggedSymbols" in mrd
      and "summaryLine" in mrd)
mra = read("MusicProviders/MediaRemoteAdapter.swift")
check("MediaRemoteAdapter: 注册 NowPlaying 通知（真签名 typealias）",
      "MRMediaRemoteRegisterForNowPlayingNotificationsFn" in mra
      and "registerForNowPlayingNotifications" in mra
      and 'bridge.symbol(MediaRemoteSymbols.registerForNowPlayingNotifications)' in mra)
check("MediaRemoteAdapter: 调 recordRegistration／recordInfoCallback（通知回调路径已删，见下）",
      "recordRegistration" in mra
      and "recordInfoCallback" in mra)
check("MediaRemoteAdapter: 不再调 recordNotificationFire（1.0.6：1.0.5 的假回调已删——注册只收队列，系统不回调块；notificationFireCount 正常是 0，不是故障）",
      "recordNotificationFire" not in mra)
check("MediaRemoteDiagnostics: 回调触发记第一次＋每 50 次；info 有无只在切换时记（通知回调函数仍在，供记录；Adapter 已不再调它）",
      "NowPlaying 通知回调已触发" in mrd and "% 50 == 0" in mrd
      and "GetNowPlayingInfo 回调已触发" in mrd
      and "lastInfoWasNil" in mrd)
check("MediaRemoteAdapter: 四符号仍按现有代码用（GetNowPlayingInfo／IsPlaying／Register／DisplayID 不增不减）",
      "MediaRemoteSymbols.getNowPlayingInfo" in mra
      and "MediaRemoteSymbols.registerForNowPlayingNotifications" in mra)
fl = read("Overlay/FloatingLyricViewController.swift")
check("强制测试文字：开关分支在 refresh() 最前（不依赖音乐／歌词）",
      "LyricStore.isTestTextEnabled" in fl
      and "apply(text: LyricStore.testText(), fontSize: 23, opacity: 1.0)" in fl)
check("强制测试文字：关后回到正常歌词（lastTestHiddenState 清零，不残留）",
      "lastTestHiddenState = nil" in fl)
check("悬浮窗控制器：初始化计数（第 N 次＋多次警告）",
      "initCount" in fl and "悬浮窗控制器初始化第" in fl)
check("LyricStore: 测试文字键＋开关＋testText()（固定文案＋时间戳）",
      '"floatingLyric.testTextEnabled"' in ls
      and "static var isTestTextEnabled" in ls
      and "static func testText() -> String" in ls
      and '"悬浮测试 · 桌面歌词 1.0.6 · \\(fmt.string(from: Date()))"' in ls)
check("LyricStore: 三档模式键＋中文描述（三档全列）",
      '"tlds.runMode"' in ls and '"tlds.runModeReason"' in ls
      and "static var runModeDescription" in ls
      and "巨魔原生模式" in ls and "增强宿主模式" in ls
      and "普通签名兼容模式" in ls)
td = read("Overlay/TLDSAppDelegate.m")
check("AppDelegate: 启动／Overlay／scene 计数（第 N 次）",
      "TLDSLaunchCount" in td and "TLDSStartFloatingOverlayCalls" in td
      and "TLDSCreateFloatingSceneCalls" in td
      and "App 启动第" in td)
check("AppDelegate: 一次性守卫（Shell 已初始化／NativeWindowFix 已安装，跳过）",
      "Shell 已初始化，跳过" in td and "NativeWindowFix 已安装，跳过" in td)
check("AppDelegate: 三档判定入口（巨魔定档／宿主待探测＋尝试创建）",
      'setRunMode:@"trollstore"' in td
      and 'setRunMode:@"probing"' in td
      and "待探测" in td)
check("AppDelegate: 托管复核 verifyFloatingVisibility（逐项＋新结论行，不再写「已确认可见」）",
      "verifyFloatingVisibility" in td
      and "托管复核：场景对象" in td and "托管复核：binder 收录场景" in td
      and "托管复核：悬浮窗口" in td and "托管复核：Context ID" in td
      and "托管结构检查通过；实际屏幕可见性未确认" in td
      and "托管复核结论：未确认可见" in td
      and "托管复核结论：已确认可见" not in td)
check("AppDelegate: 降级普通签名兼容（摘场景＋藏窗口＋不再重建）",
      "downgradeToCompatModeWithReasons" in td
      and 'setRunMode:@"compat"' in td
      and 'setRunMode:@"enhanced-host"' in td
      and "普通签名兼容模式，跳过悬浮窗恢复" in td)
check("AppDelegate: 后台挂起／恢复日志（进入后台／失去前台／回到前台／终止）",
      "tlds_logDidEnterBackground" in td and "tlds_logWillResignActive" in td
      and "tlds_logDidBecomeActive" in td and "tlds_logWillTerminate" in td)
check("AppDelegate: 创建成功≠可见（创建日志写明等复核，不当成功）",
      "创建成功≠可见，等复核" in td)
sd = read("Overlay/TLDSSceneDelegate.m")
check("SceneDelegate: 宿主不再一律强制主界面（只在已判兼容时强制）",
      "appDelegate.compatMode" in sd
      and "if ([[TLDSRuntime shared] isHosted] && appDelegate.compatMode)" in sd)
check("SceneDelegate: 场景连接计数＋窗口诊断（层级／透明度／隐藏／frame）",
      "TLDSMainSceneConnectCount" in sd and "TLDSFloatingSceneConnectCount" in sd
      and "windowLevel=%.0f" in sd and "isHidden=%@" in sd)
check("SceneDelegate: 场景生命周期日志（前台／后台四回调）",
      "sceneDidBecomeActive" in sd and "sceneWillResignActive" in sd
      and "sceneDidEnterBackground" in sd and "sceneWillEnterForeground" in sd)
ta = read("App/TrollLyricsDeskApp.swift")
check("TLDSRuntime: setRunMode／runModeString（ObjC 侧写判定结果）",
      "@objc func setRunMode(_ mode: String, reason: String)" in ta
      and "@objc func runModeString() -> String" in ta)
check("TLDSRuntime: start() 重复调用记跳过（不建第二个引擎）",
      "startCallCount" in ta and "已启动，跳过" in ta)
sv = read("App/SettingsView.swift")
check("SettingsView: 诊断区（强制测试开关＋运行模式行，写明测试用）",
      "强制悬浮测试文字（测试用）" in sv
      and "LyricStore.isTestTextEnabled" in sv
      and "运行模式" in sv and "runModeDescription" in sv)
pd = read("App/PlaybackDashboardView.swift")
check("Dashboard: 宿主应用内歌词区走 InAppLyricsRenderer.currentDisplayText",
      "InAppLyricsRenderer.currentDisplayText(at: context.date)" in pd)
check("InAppLyricsRenderer: 测试开关开时显示测试文字（注明非悬浮窗），关时显示当前行",
      "LyricStore.isTestTextEnabled" in read("Renderer/InAppLyricsRenderer.swift")
      and "应用内显示，非悬浮窗" in read("Renderer/InAppLyricsRenderer.swift")
      and "static func currentDisplayText(at date: Date) -> String" in read("Renderer/InAppLyricsRenderer.swift"))
check("PlaybackCoordinator: 检测引擎启动计数（第 N 次）",
      "startCount" in pc and "检测引擎启动第" in pc)
all_src = all_swift + read("Overlay/TLDSAppDelegate.m") + read("Overlay/TLDSSceneDelegate.m")
pip = read("Renderer/PiPLyricsRenderer.swift")
pipf = read("Renderer/PiPFrameRenderer.swift")
check("PiP 实验引擎在位：AVPictureInPictureController＋delegate 回调判定",
      "AVPictureInPictureController" in pip
      and "pictureInPictureControllerDidStartPictureInPicture" in pip
      and "failedToStartPictureInPictureWithError" in pip
      and "isPictureInPictureSupported" in pip)
check("PiP 实验引擎：先固定测试文字、再接实时歌词（两段都在）",
      "func startTestText()" in pip and "func startLiveLyrics()" in pip
      and "悬浮测试 · 桌面歌词 1.0.6" in pip)
check("PiP 实验标记在位（协议 isExperimental＋文案「实验」，不得报成已实现）",
      "isExperimental" in pip and "var isExperimental: Bool { true }" in pip
      and "（实验）" in pip)
check("PiP 画面层在位：文字画成视频段（AVAssetWriter＋H.264＋黑底白字）",
      "AVAssetWriter" in pipf and "AVVideoCodecType.h264" in pipf
      and "static func renderVideo(" in pipf)
check("无 ChatGPT 树的错文件（OverlayEngine.swift／LyricsSyncEngine.swift／OverlayMode.swift 不建）",
      not os.path.exists(os.path.join(ROOT, "Renderer/OverlayEngine.swift"))
      and not os.path.exists(os.path.join(ROOT, "Core/LyricsSyncEngine.swift"))
      and not os.path.exists(os.path.join(ROOT, "Compatibility/OverlayMode.swift"))
      and "OverlayEngine" not in all_src
      and "LyricsSyncEngine" not in all_src)
diff_ls = git_out(["diff", BASE, "HEAD", "--", "Lyrics/LyricStore.swift"])
removed_ls = [ln for ln in diff_ls.splitlines()
              if ln.startswith("-") and not ln.startswith("---")]
sync_syms = ["timeOffset", "offsetKeyPrefix", "stableSongIdentity",
             "artistCarriesLyric", "songIdentityParts", "noMusicKey"]
bad_removed = [ln for ln in removed_ls
               if any(s in ln for s in sync_syms)]
check("红线：LyricStore 同步修正符号未被删（1.0.6 有结构改动，不再要求零删行）",
      not bad_removed, str(bad_removed[:5]))
for sym in ["timeOffset", "offsetKeyPrefix", "stableSongIdentity",
            "artistCarriesLyric", "songIdentityParts", "noMusicKey",
            "isDisplayEquivalent", "syncLiveLyricsAndProgress",
            "needsRebuildOnUnlock"]:
    src = ls if sym in ("timeOffset", "offsetKeyPrefix", "stableSongIdentity",
                        "artistCarriesLyric", "songIdentityParts", "noMusicKey") else pc
    if sym == "needsRebuildOnUnlock":
        src = td
    check(f"红线锚：{sym} 在 1.0.6 仍在位", sym in src)
for rel in ["TrollLyricsDesk/TrollLyricsDesk.entitlements",
            "TrollLyricsWidget/TrollLyricsWidget.entitlements"]:
    head = git_out(["show", f"{BASE}:{rel}"])
    check(f"{rel}: 与 4f43991 一字未动（零新增权限）", read(rel) == head)


print("\n== 12. 1.0.5 新结构（皇上的树为准） ==")
for rel in ["Compatibility/RuntimeCapabilities.swift",
            "Compatibility/RuntimeEnvironment.swift",
            "Compatibility/EntitlementDiagnostics.swift",
            "Renderer/LyricsRenderer.swift",
            "Renderer/NativeHUDRenderer.swift",
            "Renderer/PiPLyricsRenderer.swift",
            "Renderer/PiPFrameRenderer.swift",
            "Renderer/InAppLyricsRenderer.swift",
            "Diagnostics/MediaRemoteDiagnostics.swift",
            "Diagnostics/OverlayDiagnostics.swift",
            "Diagnostics/DiagnosticsView.swift"]:
    check(f"新文件在位：{rel}", os.path.exists(os.path.join(ROOT, rel)))
pbx = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
app_sources = pbx_sources_files(pbx, "4821909E9BF9E73E471FEA84")
for fn in ["RuntimeCapabilities.swift", "RuntimeEnvironment.swift",
           "EntitlementDiagnostics.swift", "LyricsRenderer.swift",
           "NativeHUDRenderer.swift", "PiPLyricsRenderer.swift",
           "PiPFrameRenderer.swift", "InAppLyricsRenderer.swift",
           "MediaRemoteDiagnostics.swift", "OverlayDiagnostics.swift",
           "DiagnosticsView.swift"]:
    check(f"pbxproj: {fn} 进 App Sources", fn in app_sources, str(app_sources))
for g in ["Compatibility", "Renderer", "Diagnostics"]:
    check(f"pbxproj: {g} 组在位", f'name = "{g}"' in pbx or f"name = {g};" in pbx)
re_ = read("Compatibility/RuntimeEnvironment.swift")
check("RuntimeEnvironment: 三档 → 引擎映射（巨魔原生／增强宿主 PiP／兼容应用内）",
      '"trollstore"' in re_ and '"enhanced-host"' in re_
      and "return .nativeHUD" in re_ and "return .pip" in re_
      and "return .inApp" in re_)
lr = read("Renderer/LyricsRenderer.swift")
check("LyricsRenderer: 统一渲染协议＋Hub（切换逻辑在此层）",
      "protocol LyricsRenderer" in lr and "isExperimental" in lr
      and "final class LyricsRendererHub" in lr
      and "currentRenderer" in lr)
check("RuntimeEnvironment: 切换阈值集中（preferredEngine＋日志）",
      "static func preferredEngine(forRunMode mode: String)" in re_
      and "logEngineSelection" in re_)
td = read("Overlay/TLDSAppDelegate.m")
check("AppDelegate: 五处定档点都记显示引擎选择（1.0.6 四分支＋降级）",
      td.count("诊断1.0.6 显示引擎：") == 5)
check("AppDelegate: 增强宿主不信任原生 HUD（写明权限受限）",
      "透明全域悬浮在此模式为权限受限" in td)
sv = read("App/SettingsView.swift")
check("SettingsView: 诊断详情入口＋PiP 实验按钮（标明实验）",
      "DiagnosticsView()" in sv
      and "开始 PiP 测试（固定文字，实验）" in sv
      and "接入实时歌词到 PiP（实验）" in sv)
dv = read("Diagnostics/DiagnosticsView.swift")
check("DiagnosticsView: 模式／MediaRemote／PiP／权限对照四区在位",
      "运行模式（三档，按实际能力）" in dv
      and "MediaRemote 音乐识别" in dv
      and "PiP 画中画歌词（实验）" in dv
      and "权限对照（声明 ≠ 可用）" in dv)
ed = read("Compatibility/EntitlementDiagnostics.swift")
check("EntitlementDiagnostics: 声明 vs 实测对照（MediaRemote／FrontBoard／平台应用／PiP）",
      "声明" in ed and "实测" in ed
      and "MediaRemote" in ed and "FrontBoard" in ed
      and "platform-application" in ed)
check("逐字歌词未现编实现（LyricWord.swift／LyricSyncEngine.swift 不存在）",
      not os.path.exists(os.path.join(ROOT, "Lyrics/LyricWord.swift"))
      and not os.path.exists(os.path.join(ROOT, "Core/LyricSyncEngine.swift"))
      and "LyricSyncEngine" not in all_swift)
check("设置里「逐字卡拉OK」选项文案保留（不删）",
      "逐字卡拉OK" in sv)

print("\n== 13. ChatGPT 审查两 bug 修复（1.0.5 范围内，皇上 22:00 令） ==")
ad = read("MusicProviders/MediaRemoteAdapter.swift")
mrd = read("Diagnostics/MediaRemoteDiagnostics.swift")
check("adapter: 暂停进度修正——rate 纳入公式（elapsed + delta * rate，duration 钳制，有限值守卫）",
      "let delta = timestamp.map { max(0, Date().timeIntervalSince($0)) } ?? 0" in ad
      and "let estimated = elapsed + delta * rate" in ad
      and "let safePosition = estimated.isFinite ? max(0, estimated) : 0" in ad
      and "$0.isFinite && $0 > 0 ? min(safePosition, $0) : safePosition" in ad
      and "Date().timeIntervalSince(timestamp) + elapsed" not in ad)
check("adapter: 请求超时 2 秒（Task.sleep 看门狗）＋缓存最长 3 秒（maxCacheAge）",
      "try? await Task.sleep(nanoseconds: 2_000_000_000)" in ad
      and "private let maxCacheAge: TimeInterval = 3" in ad
      and "Date().timeIntervalSince(cachedAt) <= maxCacheAge" in ad)
check("adapter: 请求编号 UUID＋超时复位＋旧回调丢弃",
      "private var requestID = UUID()" in ad
      and "let id = UUID()" in ad and "requestID = id" in ad
      and "guard let self, self.requestID == id, self.fetching else { return }" in ad)
check("diagnostics: recordFetchTimeout 存在（第 1 次＋每 10 次记一行，看门狗里调用）",
      "static func recordFetchTimeout()" in mrd
      and "fetchTimeoutCount" in mrd
      and "MediaRemoteDiagnostics.recordFetchTimeout()" in ad)
# 存储统一：除 LyricStore.swift 本尊（defaults 定义）外，全树不得再直接建 suite
all_swift_files = [f for f in git_out(["ls-files"]).splitlines() if f.endswith(".swift")]
bypass = [f for f in all_swift_files
          if f != "Lyrics/LyricStore.swift"
          and ("UserDefaults(suiteName:" in read(f)
               or 'suiteName: "group.com.hailong.TrollLyricsDesk"' in read(f))]
check("存储统一：Swift 侧除 LyricStore.swift 外无直接 UserDefaults(suiteName:)",
      not bypass, str(bypass))
check("存储统一：ActivationView 激活门走 LyricStore.defaults",
      "@AppStorage(ActivationStore.activatedKey, store: LyricStore.defaults)" in read("App/ActivationView.swift"))
check("存储统一：FloatingLyricViewController prefs 走 LyricStore.defaults",
      "private var prefs: UserDefaults? { LyricStore.defaults }" in read("Overlay/FloatingLyricViewController.swift"))
check("存储统一：SettingsView 7 处硬编码 group 字符串已改走 LyricStore.defaults",
      read("App/SettingsView.swift").count("store: LyricStore.defaults") == 7
      and '"group.com.hailong.TrollLyricsDesk"' not in read("App/SettingsView.swift"))
app_m = read("Overlay/TLDSAppDelegate.m")
check("存储统一：ObjC 侧改走 [TLDSRuntime sharedDefaults]（1.0.5 三处，1.0.6 七处，含退出状态读写），无 initWithSuiteName",
      app_m.count("[TLDSRuntime sharedDefaults]") >= 3
      and "initWithSuiteName" not in app_m)
check("存储统一：TLDSRuntime.sharedDefaults 存在（回 .standard 兜底）",
      "@objc static func sharedDefaults() -> UserDefaults" in read("App/TrollLyricsDeskApp.swift")
      and "LyricStore.defaults ?? .standard" in read("App/TrollLyricsDeskApp.swift"))

print("\n== 14. Engine Fix 并入（皇上 22:03 令，包为准） ==")
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
lp = read("Lyrics/LyricParser.swift")
check("coordinator: latestState 与 state 分离＋searchGeneration（UUID）",
      "private var latestState: PlaybackState?" in pc
      and "private var searchGeneration = UUID()" in pc)
check("coordinator: stop／无音乐时重置状态＋轮换代次",
      pc.count("searchGeneration = UUID()") >= 3
      and "latestState = nil" in pc)
check("coordinator: 换歌键用稳定标识 trackKey(track)，缓存优先才搜词",
      "let key = trackKey(newState.track)" in pc
      and "LyricStore.cachedLyrics(title:" in pc
      and "await loadLyrics(for: newState.track, generation: generation)" in pc)
check("coordinator: 暂停拖动进度同步（|Δposition| > 0.1）",
      "abs(previous.position - newState.position) > 0.1" in pc
      and "syncPlaybackState(newState, previous: previous)" in pc)
check("coordinator: 快照归属改稳定标识比对",
      "LyricStore.stableSongIdentity(title: snapshot.title, artist: snapshot.artist) ==" in pc)
check("coordinator: loadLyrics 带 generation 守卫（入口／取回后／出错时）",
      "for track: MusicTrack, generation: UUID" in pc
      and "guard !Task.isCancelled, generation == searchGeneration else { return }" in pc
      and "guard let current = latestState, trackKey(current.track) == trackKey(track) else {" in pc
      and "syncLyrics(lines, at: current)" in pc)
check("coordinator: syncLyrics 进度基准用 current 推算，不再重调 adapter",
      "let basePosition = current.position + (baseStatus == .playing ? max(0, Date().timeIntervalSince(current.observedAt)) : 0)" in pc
      and "let live = adapter.currentState()" not in pc)
check("coordinator: 锁屏没带回来（publishLiveLyrics／LiveLyricKey 不在）",
      "publishLiveLyrics" not in pc and "LiveLyricKey" not in pc
      and "lastLiveState" not in pc)
check("parser: 一行多时间标签＋[offset:]＋稳定排序（包的重写版）",
      "offsetPattern" in lp and "[offset:" in lp
      and "let time = max(0, minutes * 60 + seconds + fraction - offset / 1000)" in lp
      and "enumerated().sorted" in lp)
check("parser: [offset:] 只动解析出的时间，不碰 LyricStore 逐歌偏移",
      "timeOffset" not in lp and "LyricStore" not in lp)
check("ENGINE_FIX.md 已带入（包的说明原文）",
      os.path.exists(os.path.join(ROOT, "ENGINE_FIX.md"))
      and "Three Swift files changed" in read("ENGINE_FIX.md"))
check("EngineTests/main.swift 已带入（LRC 回归测试，不进编译目标）",
      os.path.exists(os.path.join(ROOT, "EngineTests/main.swift"))
      and 'precondition(a.count == 2 && a[0].time == 9.5' in read("EngineTests/main.swift")
      and "EngineTests" not in pbx)
check("pbxproj: EngineTests 不在任何 Sources 里（只留文件不加 target）",
      "EngineTests" not in pbx)

print("\n== 15. 1.0.6 十项（皇上 22:59 令＋ChatGPT ZIP 选择性并入） ==")
re_ = read("Compatibility/RuntimeEnvironment.swift")
check("第 1 项：RuntimeEnvironment 重写——InstallEnvironment 四档＋detectInstallEnvironment",
      "enum InstallEnvironment: String" in re_
      and "static func detectInstallEnvironment()" in re_
      and '"trollstore"' in re_ and '"livecontainer"' in re_
      and '"signature"' in re_ and '"unknown"' in re_)
check("第 1 项：不再有「非宿主就当巨魔」（if (!isHosted) → trollstore 已删；注释里的历史引用除外）",
      not any("if (!isHosted)" in ln
              for ln in re_.splitlines()
              if not ln.strip().startswith("///") and not ln.strip().startswith("//"))
      and "if (![[TLDSRuntime shared] isHosted])" not in read("Overlay/TLDSAppDelegate.m")
      and "native-candidate" in re_)
check("第 1 项：native-candidate 映射到原生 HUD（与 trollstore 同引擎、不同模式名）",
      'case "trollstore", "native-candidate":' in re_
      and "return .nativeHUD" in re_)
ee = read("Compatibility/EffectiveEntitlements.swift")
check("第 5 项：EffectiveEntitlements 新文件——SecTask 实测（dlsym，不链接 Security）＋沙盒外写探测",
      "enum EffectiveEntitlements" in ee
      and "dlsym" in ee
      and "sandboxWriteProbe" in ee
      and "trollStoreEvidence" in ee
      and "sandboxedProven" in ee
      and "logReport" in ee)
check("第 5 项：TrollStore 正面证据判（任务权限 platform-application＋no-sandbox，或写探测成功）",
      "platform-application" in ee
      and "com.apple.private.security.no-sandbox" in ee
      and "func trollStoreEvidence()" in ee)
check("第 5 项：EntitlementDiagnostics 权限对照读实测值（优于 ChatGPT 的「有效权限未测」）",
      "EffectiveEntitlements.taskValue" in read("Compatibility/EntitlementDiagnostics.swift")
      and "有效权限未测" not in read("Compatibility/EntitlementDiagnostics.swift"))
check("第 2 项：三项判定分离——LyricStore 三组键（安装环境／显示能力各有结论＋理由）",
      '"tlds.installEnvironment"' in ls and '"tlds.installEnvironmentReason"' in ls
      and '"tlds.displayCapability"' in ls and '"tlds.displayCapabilityReason"' in ls
      and "installEnvironmentDescription" in ls
      and "displayCapabilityDescription" in ls)
check("第 2 项：DiagnosticsView 三项判定分行显示（安装环境行＋显示能力行）",
      "安装环境：" in dv and "显示能力：" in dv
      and "LyricStore.installEnvironmentDescription" in dv
      and "LyricStore.displayCapabilityDescription" in dv)
check("第 2 项：复核只定显示能力——delegate 的 native-candidate 分支写 displayCapability，不改安装环境",
      'setDisplayCapability:@"nativeHUD"' in td
      and 'setRunMode:@"native-candidate"' in td)
_widget_files = ["TrollLyricsWidget/TrollLyricsWidget.swift",
               "TrollLyricsWidget/WidgetView.swift",
               "TrollLyricsWidget/TrollLyricsWidgetBundle.swift",
               "Lyrics/LyricLine.swift", "Lyrics/LyricParser.swift",
               "Lyrics/LyricStore.swift"]
# 只查代码行（注释里提类型名不算引用，编得过）。
_widget_code = "\n".join(
    ln for f in _widget_files for ln in read(f).splitlines()
    if not ln.strip().startswith("///") and not ln.strip().startswith("//"))
check("Widget target 自包含：Widget Sources 的 6 个 Swift 文件代码行不引用 App-only 类型（InstallEnvironment／DisplayCapability）",
      "InstallEnvironment" not in _widget_code
      and "DisplayCapability" not in _widget_code,
      "run 45850840777 教训：LyricStore 引用枚举类型导致 Widget target Archive 失败")
for _s in ["TrollStore（巨魔）", "LiveContainer 宿主", "普通签名（沙盒内）",
           "未确认（权限探测不可用）", "原生 HUD 悬浮歌词",
           "PiP 画中画歌词（实验）", "应用内歌词"]:
    check(f"显示名一致：{_s} 在 LyricStore（字符串 switch）与 RuntimeEnvironment（枚举 displayName）两边都在",
          _s in ls and _s in re_)
pc = read("PlaybackEngine/PlaybackCoordinator.swift")
check("第 3 项：PlaybackCoordinator.start() 幂等（guard timer == nil，重复记跳过，不建第二个任务）",
      "guard timer == nil else" in pc
      and "检测引擎已运行，跳过重复启动" in pc)
check("第 3 项：poll 加 timer != nil 守卫（停了就不再 poll）",
      "timer != nil" in pc)
check("第 3 项：TLDSRuntime.start() 仍有 started 守卫（不建第二个检测引擎）",
      "startCallCount" in ta and "已启动，跳过" in ta)
mrd = read("Diagnostics/MediaRemoteDiagnostics.swift")
mra = read("MusicProviders/MediaRemoteAdapter.swift")
# build 23（2026-11-27 09:58 第三次审计定）：上面这条旧断言被推翻——
# @convention(block) 正是崩点：编译器在调用点后插 swift_isEscapingClosureAtFileLocation
# 检查，MediaRemote（异步 XPC）调用返回后仍持有 block，检查为真 → brk #1（0x44A5C）。
# 1.0.5 的 @escaping 才是对的，build 23 改回去；isPlaying 探针仍是 block（未动）。
check("第 4 项：MediaRemoteAdapter 签名修正（build 23 改回 @escaping——@convention(block) 是崩点）",
      "@escaping (CFDictionary?) -> Void" in mra
      and "@convention(block) (CFDictionary?) -> Void" not in mra)
check("第 4 项：注册改只收队列（删掉 1.0.5 的假回调——系统根本不调它）",
      "MRMediaRemoteRegisterForNowPlayingNotificationsFn" in mra
      and "DispatchQueue\n) -> Void" in mra)
check("第 4 项：调用改主队列（DispatchQueue.main）",
      "getNowPlayingInfo(\nDispatchQueue.main" in mra)
check("第 4 项：isPlaying 探针在位（MRMediaRemoteGetNowPlayingApplicationIsPlaying，block 回调，5 秒节流）",
      "MRMediaRemoteGetNowPlayingApplicationIsPlayingFn" in mra
      and "@convention(block) (UInt8) -> Void" in mra
      and "queryIsPlayingIfNeeded" in mra
      and "timeIntervalSince(last) < 5" in mra)
check("第 4 项：MediaRemoteDiagnostics 完成——recordRequest／recordIsPlaying／readStatus／summaryLine 带环境标签",
      "static func recordRequest()" in mrd
      and "static func recordIsPlaying(_ playing: Bool?)" in mrd
      and "static var readStatus: String" in mrd
      and "RuntimeCapabilities.environmentTag" in mrd)
check("第 4 项：readStatus 分得清 P0／可能没放歌／疑似 P0／超时／受限／解析失败／ok",
      "P0：放着歌还读不到" in mrd and "可能没放歌" in mrd
      and "疑似 P0" in mrd and "超时" in mrd and "受限" in mrd
      and "解析失败" in mrd)
check("第 4 项：P0 明确日志行（isPlaying=YES＋info=nil 时另记一行）",
      "P0——放着歌还读不到" in mrd)
check("第 4 项：DiagnosticsView 显示调用／回调／isPlaying 查询次数",
      "requestCount" in dv and "infoCallbackCount" in dv
      and "isPlayingQueryCount" in dv)
check("第 6 项：Context ID 未知不进判定（unknown／valid／invalid 三态，unknown 不算通过）",
      "contextIDUnknown" in td and "Context ID：未知" in td
      and "Context ID：有效" in td and "Context ID：无效" in td)
check("第 6 项：活着的「已确认可见」只剩注释（日志行里没有）",
      all(ln.strip().startswith("//") or ln.strip().startswith("///")
          for ln in (td + read("Overlay/TLDSAppDelegate.h")
                     + read("Diagnostics/OverlayDiagnostics.swift")).splitlines()
          if "已确认可见" in ln))
check("第 6 项：重建先销毁旧场景（requestSceneSessionDestruction＋活着的悬浮场景计数＋先销毁日志行）",
      "requestSceneSessionDestruction" in td
      and "logLiveFloatingScenesWithTag" in td
      and "先销毁旧悬浮场景" in td)
check("第 7 项：激活前后快照——ActivationView onAppear 记「激活前」，激活成功后记「激活成功后」",
      'LyricStore.logFloatingWindowState(tag: "激活前")' in read("App/ActivationView.swift")
      and 'LyricStore.logFloatingWindowState(tag: "激活成功后")' in read("App/ActivationView.swift")
      and "static func logFloatingWindowState(tag: String)" in ls)
check("第 7 项：上次退出状态记录（tlds.lastExitState／terminated-clean／background）",
      "tlds.lastExitState" in td and "terminated-clean" in td
      and '"background"' in td)
check("第 8 项：终止原因记录（WillTerminate＋内存警告疑似 jetsam；查不到写原因未知，不编）",
      "tlds_logWillTerminate" in td
      and "applicationDidReceiveMemoryWarning" in td)
check("第 9 项：PiP 两段独立状态（tlds.pipTestStage／tlds.pipLiveStage，各有未开始／进行中／已显示／失败）",
      '"tlds.pipTestStage"' in pip and '"tlds.pipLiveStage"' in pip
      and "testStage = \"进行中\"" in pip and "liveStage = \"进行中\"" in pip
      and "testStage = \"已显示\"" in pip and "liveStage = \"已显示\"" in pip)
check("第 9 项：DiagnosticsView 分行显示 PiP 两段状态",
      "固定文字段：" in dv and "实时歌词段：" in dv
      and "PiPLyricsRenderer.testStageText" in dv
      and "PiPLyricsRenderer.liveStageText" in dv)
check("第 9 项：PiP 实现本身未动（AVSampleBufferDisplayLayer 只进 RUN 当后续候选，不实现）",
      "AVSampleBufferDisplayLayer" not in pip
      and "AVAssetWriter" in pipf and "AVVideoCodecType.h264" in pipf)
check("第 10 项：激活接口不变（POST /api/verify）＋逐歌偏移＋Engine Fix 串全在",
      "https://guhailong-repo.pages.dev/api/verify" in ls
      and "timeOffset" in ls and "syncLiveLyricsAndProgress" in pc
      and "searchGeneration" in pc)
check("前缀统一：源码里无「诊断1.0.5」日志前缀（注释里的历史 1.0.5 引用除外）",
      "诊断1.0.5" not in (td + ta + re_ + read("Compatibility/RuntimeCapabilities.swift")
                          + read("Compatibility/EntitlementDiagnostics.swift")
                          + mrd + mra + pip + ls + dv))
check("前缀统一：测试文字已是 1.0.6（LyricStore／PiP／SettingsView 三处）",
      "桌面歌词 1.0.6" in ls and "桌面歌词 1.0.6" in pip
      and "桌面歌词 1.0.6" in read("App/SettingsView.swift")
      and "桌面歌词 1.0.5" not in ls and "桌面歌词 1.0.5" not in pip
      and "桌面歌词 1.0.5" not in read("App/SettingsView.swift"))

print("\n== 16. build 21 两处修（#1 重建竞态＋SecTask 三参数，皇上 2026-11-27 02:27 定） ==")
td21 = read("Overlay/TLDSAppDelegate.m")
sd21 = read("Overlay/TLDSSceneDelegate.m")
hd21 = read("Overlay/TLDSAppDelegate.h")
check("build 21：新锚点 floatingSceneEverConnected 在 header 声明（＋连接中跳过日志节流戳）",
      "floatingSceneEverConnected" in hd21
      and "lastConnectingSkipLogTime" in hd21)
check("build 21：创建新场景时锚点清 NO（createFloatingScene 里 EverCreated 置位后即清）",
      "self.floatingSceneEverConnected = NO" in td21)
check("build 21：悬浮场景完成连接时锚点置 YES（SceneDelegate willConnectToSession，floating 分支）",
      "appDelegate.floatingSceneEverConnected = YES" in sd21)
check("build 21：rebuild 里销毁调用被锚点守卫——只有旧场景曾经连上才销毁",
      "if (oldSession && self.floatingSceneEverConnected)" in td21
      and "requestSceneSessionDestruction" in td21)
check("build 21：旧场景未连上时跳过销毁分支在位（只摘 binder＋藏窗口，走 1.0.5 做法）",
      "跳过销毁旧场景会话" in td21
      and "只摘 binder＋藏窗口" in td21)
check("build 21：触发侧守卫——DidBecomeActive／2 秒看门狗在连接窗口里跳过这次恢复（不调 rebuild）",
      "正在连接中，跳过这次恢复" in td21
      and "self.floatingScene && !self.floatingSceneCreated && !self.floatingSceneEverConnected" in td21)
check("build 21：触发侧跳过日志有节流（20 秒，不让看门狗刷屏）",
      "lastConnectingSkipLogTime > 20.0" in td21)
check("build 21：不回归 14:59:44 第二窗修法——连上过、后来断开的旧场景照旧销毁（重建前后计数＋先销毁日志行仍在）",
      "logLiveFloatingScenesWithTag" in td21
      and "先销毁旧悬浮场景" in td21
      and "已请求销毁旧场景会话" in td21)
check("build 21：其余不动——isPlaying 探针、native-candidate、PiP 两段、激活、逐歌偏移、entitlements 均未碰",
      "MRMediaRemoteGetNowPlayingApplicationIsPlayingFn" in read("MusicProviders/MediaRemoteAdapter.swift")
      and "native-candidate" in td21
      and '"tlds.pipTestStage"' in read("Renderer/PiPLyricsRenderer.swift")
      and "https://guhailong-repo.pages.dev/api/verify" in ls)
ee21 = read("Compatibility/EffectiveEntitlements.swift")
check("build 21：SecTask 三参数修——CopyFn 是三参数（task、key、CFErrorRef *error），调用传 nil，2 参数版不在",
      "(UnsafeMutableRawPointer, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?)" in ee21
      and "(task, key as CFString, nil)" in ee21
      and "(task, key as CFString) else" not in ee21)
check("build 21：SecTask 7 个探针键仍在 entitlements 文件里（查都会成功，缺失参数平时不写东西）",
      all(k in read("TrollLyricsDesk/TrollLyricsDesk.entitlements")
          for k in ["platform-application", "com.apple.private.security.no-sandbox",
                    "com.apple.frontboard.launchapplications",
                    "com.apple.mediaremote.now-playing-read-access",
                    "com.apple.mediaremote.full-now-playing-read-access",
                    "com.apple.backboard.client", "get-task-allow"]))
print("\n== 17. build 22 只禁 isPlaying 探针（决定性实验，皇上 2026-11-27 09:22 定） ==")
mra22 = read("MusicProviders/MediaRemoteAdapter.swift")
# build 24：禁用标记字串改走 LyricStore.versionTag 插值，不再写死 "build 22"
#（build 23 的日志写 build 22 就是写死字串的教训）；探针本身仍禁用。
check("build 22：禁用标记字串在源码里在位（build 24 起走 versionTag 插值）",
      'LyricLogger.log("诊断1.0.6 MediaRemote：\\(LyricStore.versionTag)：isPlaying 探针已禁用")' in mra22
      and "build 22：isPlaying 探针已禁用" not in mra22)
check("build 22：queryIsPlayingIfNeeded() 在 5 秒节流检查后记日志＋return",
      "timeIntervalSince(last) < 5" in mra22
      and 'LyricLogger.log("诊断1.0.6 MediaRemote：\\(LyricStore.versionTag)：isPlaying 探针已禁用")' in mra22
      and "\n    return\n    guard let sym = bridge.symbol(MediaRemoteSymbols.getNowPlayingApplicationIsPlaying)" in mra22)
_i_throttle = mra22.index("timeIntervalSince(last) < 5")
_i_log = mra22.index("isPlaying 探针已禁用")
_i_sym = mra22.index("bridge.symbol(MediaRemoteSymbols.getNowPlayingApplicationIsPlaying)")
_i_cast = mra22.index("unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFn.self)")
check("build 22：return 在 bridge.symbol／dlsym 之前——探针调用代码仍在但不可达",
      _i_throttle < _i_log < _i_sym < _i_cast,
      f"throttle={_i_throttle} log={_i_log} symbol={_i_sym} bitcast={_i_cast}")
check("build 22：探针代码一字未动留着（typealias／dlsym／unsafeBitCast／query 调用都在）",
      "MRMediaRemoteGetNowPlayingApplicationIsPlayingFn" in mra22
      and "bridge.symbol(MediaRemoteSymbols.getNowPlayingApplicationIsPlaying)" in mra22
      and "unsafeBitCast(sym, to: MRMediaRemoteGetNowPlayingApplicationIsPlayingFn.self)" in mra22
      and "query(DispatchQueue.main) { playing in" in mra22
      and "MediaRemoteDiagnostics.recordIsPlayingQuery()" in mra22)
check("build 22：调用点未动——info==nil 时仍调 queryIsPlayingIfNeeded()（函数内直接返回）",
      "if info == nil {" in mra22 and "queryIsPlayingIfNeeded()" in mra22)
check("build 22：其余不动——#1 守卫、SecTask 三参数、native-candidate、PiP 两段、激活、逐歌偏移、entitlements 均未碰",
      "floatingSceneEverConnected" in read("Overlay/TLDSAppDelegate.m")
      and "(UnsafeMutableRawPointer, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?)" in read("Compatibility/EffectiveEntitlements.swift")
      and "native-candidate" in read("Overlay/TLDSAppDelegate.m")
      and '"tlds.pipTestStage"' in read("Renderer/PiPLyricsRenderer.swift")
      and "https://guhailong-repo.pages.dev/api/verify" in ls
      and "timeOffset" in ls)


print("\n== 18. build 23 只改回调回 @escaping（病根修复实验，第三次审计 2026-11-27 09:58 定） ==")
mra23 = read("MusicProviders/MediaRemoteAdapter.swift")
check("build 23：GetNowPlayingInfo 回调改回 @escaping（typealias 里在位）",
      "private typealias MRMediaRemoteGetNowPlayingInfoFn = @convention(c) (" in mra23
      and "@escaping (CFDictionary?) -> Void" in mra23)
_i_fn = mra23.index("MRMediaRemoteGetNowPlayingInfoFn")
_i_esc = mra23.index("@escaping (CFDictionary?) -> Void")
check("build 23：@escaping 就在 GetNowPlayingInfo 的 typealias 里（不在别处）",
      _i_fn < _i_esc < _i_fn + 200,
      f"fn={_i_fn} escaping={_i_esc}")
check("build 23：GetNowPlayingInfo 回调不再是 @convention(block)（CFDictionary 版不在）",
      "@convention(block) (CFDictionary?) -> Void" not in mra23)
check("build 23：isPlaying 探针的 typealias 绝对未动——仍是 @convention(block) (UInt8)",
      "@convention(block) (UInt8) -> Void" in mra23
      and "MRMediaRemoteGetNowPlayingApplicationIsPlayingFn" in mra23)
check("build 23：@escaping 闭包里显式 self.（编译强制，行为不变——闭包已 [weak self]，内层 Task 已 guard let self）",
      "self.queryIsPlayingIfNeeded()" in mra23)
check("build 23：没有用 withoutActuallyEscaping 包起来，也没有删回调",
      "withoutActuallyEscaping" not in mra23
      and "getNowPlayingInfo(" in mra23
      and "MediaRemoteDiagnostics.recordRequest()" in mra23)
check("build 23：isPlaying 探针仍禁用（build 24 起标记走 versionTag＋return 仍在）",
      'LyricLogger.log("诊断1.0.6 MediaRemote：\\(LyricStore.versionTag)：isPlaying 探针已禁用")' in mra23
      and "\n    return\n    guard let sym = bridge.symbol(MediaRemoteSymbols.getNowPlayingApplicationIsPlaying)" in mra23)
check("build 23：其余不动——#1 守卫、SecTask 三参数、native-candidate、PiP 两段、激活、逐歌偏移、entitlements 均未碰",
      "floatingSceneEverConnected" in read("Overlay/TLDSAppDelegate.m")
      and "(UnsafeMutableRawPointer, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?)" in read("Compatibility/EffectiveEntitlements.swift")
      and "native-candidate" in read("Overlay/TLDSAppDelegate.m")
      and '"tlds.pipTestStage"' in read("Renderer/PiPLyricsRenderer.swift")
      and "https://guhailong-repo.pages.dev/api/verify" in ls
      and "timeOffset" in ls)


print("\n== 19. build 24 五件修（巨魔主线修复版，皇上 2026-11-27 10:20 定） ==")
ls24 = read("Lyrics/LyricStore.swift")
ta24 = read("App/TrollLyricsDeskApp.swift")
mra24 = read("MusicProviders/MediaRemoteAdapter.swift")
td24 = read("Overlay/TLDSAppDelegate.m")
by24 = read(".github/workflows/build.yml")
_vt = re.search(r'static let versionTag = "([^"]+)"', ls24)
check("build 28（第 2 项）：统一常量 versionTag 在 LyricStore，值是 build 28",
      _vt is not None and _vt.group(1).startswith("build 28"),
      _vt.group(1) if _vt else "无 versionTag")
check("build 28（第 2 项）：versionTag 长串（UTF-8＞15 字节，Release 下进 __cstring，验包能搜到 build 28）",
      _vt is not None and len(_vt.group(1).encode("utf-8")) > 15,
      f"{len(_vt.group(1).encode('utf-8'))} bytes" if _vt else "无 versionTag")
check("build 24（第 2 项）：探针日志走 versionTag 插值，写死的 build 22 字串不在源码运行时串里",
      'LyricLogger.log("诊断1.0.6 MediaRemote：\\(LyricStore.versionTag)：isPlaying 探针已禁用")' in mra24
      and '"build 22' not in mra24
      and "build 22：isPlaying 探针已禁用" not in mra24)
check("build 24（第 2 项）：@escaping 闭包里显式 self. 仍在（build 23 编译强制那词没弄丢）",
      "self.queryIsPlayingIfNeeded()" in mra24)
check("build 24（第 2 项）：全树核查——TLDSAppDelegate.m 运行时字串里的 build 21 已去掉（只剩注释里的历史引用）",
      "（build 21 竞态修）" not in td24
      and "（竞态修）" in td24
      and "跳过销毁旧场景会话" in td24)
check("build 24（第 1 项）：LC_HOME_PATH 环境变量排第一——在 plist 键／路径信号之前判",
      'environment["LC_HOME_PATH"]' in ls24
      and ls24.index('if ProcessInfo.processInfo.environment["LC_HOME_PATH"]') < ls24.index('if Bundle.main.object(forInfoDictionaryKey: "TLDSLiveContainer")')
      and ls24.index('if ProcessInfo.processInfo.environment["LC_HOME_PATH"]') < ls24.index('lower.contains("livecontainer")'))
check("build 24（第 1 项）：包路径 /Documents/Applications/ 信号在（旧线信号二）",
      'contains("/documents/applications/")' in ls24)
check("build 24（第 1 项）：信号明细写清 LC_HOME_PATH 与 /Documents/Applications/ 命中情况",
      "环境变量 LC_HOME_PATH 已设" in ls24
      and "包路径含 /Documents/Applications/" in ls24)
check("build 24（第 1 项）：检测时把实测值写进日志——logEnvironmentDetection 在 detectInstallEnvironment 里调",
      "func logEnvironmentDetection()" in ta24
      and "logEnvironmentDetection()" in ta24
      and ta24.index("func logEnvironmentDetection()") > ta24.index("func detectInstallEnvironment()"))
check("build 24（第 1 项）：环境检测日志含进程名／Home／bundle／argv[0]／LC_HOME_PATH",
      "processName" in ta24 and "NSHomeDirectory()" in ta24
      and "Bundle.main.bundlePath" in ta24
      and "arguments.first" in ta24
      and 'environment["LC_HOME_PATH"]' in ta24)
check("build 24（第 2 项）：启动时版本对账行——versionTag 与 CFBundleVersion 并排记进日志",
      "诊断1.0.6 版本：" in ta24
      and "LyricStore.versionTag" in ta24
      and 'CFBundleVersion' in ta24)
check("build 24（第 1 项）：TrollStore 检测不动——SecTask 正面证据仍在 detectInstallEnvironment 之前判 LC",
      "LyricStore.isLiveContainer" in read("Compatibility/RuntimeEnvironment.swift")
      and "trollStoreEvidence()" in read("Compatibility/RuntimeEnvironment.swift")
      and read("Compatibility/RuntimeEnvironment.swift").index("LyricStore.isLiveContainer") < read("Compatibility/RuntimeEnvironment.swift").index("trollStoreEvidence()"))
check("build 24（第 4 项）：OverlayDiagnostics.logSummary() 有调用者——setRunMode 里调",
      "OverlayDiagnostics.logSummary()" in ta24
      and ta24.index("func setRunMode") < ta24.index("OverlayDiagnostics.logSummary()"))
check("build 24（第 4 项）：诊断摘要字串在源码里在位（setRunMode 调了它，整模块优化裁不掉）",
      "悬浮窗复核摘要" in read("Diagnostics/OverlayDiagnostics.swift"))
check("build 24（第 3 项）：build.yml 同时上传 dSYM（Package dSYM 步＋Upload dSYM artifact）",
      "Package dSYM" in by24
      and "build/TrollLyricsDesk.xcarchive/dSYMs" in by24
      and "桌面歌词-1.0.6-dSYM" in by24
      and "Upload dSYM artifact" in by24)
check("build 24（第 3 项）：IPA 产物不变（名与上传步仍在，dSYM 是另加的产物）",
      "桌面歌词-1.0.6.ipa" in by24
      and "name: 桌面歌词-1.0.6\n" in by24)
check("build 24（第 5 项）：@escaping 修法不动——GetNowPlayingInfo 回调仍是 @escaping，isPlaying 仍是 block",
      "@escaping (CFDictionary?) -> Void" in mra24
      and "@convention(block) (CFDictionary?) -> Void" not in mra24
      and "@convention(block) (UInt8) -> Void" in mra24
      and "withoutActuallyEscaping" not in mra24)
check("build 24（第 5 项）：审计结论——全树 Swift 无 as!／fatalError；try! 只剩 LyricParser 两行静态正则（字面量 pattern，不可能失败）",
      not any("as!" in ln or "fatalError" in ln
              for f in all_swift_files for ln in read(f).splitlines()
              if not ln.strip().startswith("//") and not ln.strip().startswith("///"))
      and sum(ln.count("try!") for f in all_swift_files
              for ln in read(f).splitlines()) == 2)
check("build 24（第 5 项）：其余不动——#1 守卫、SecTask 三参数、native-candidate、PiP 两段、激活、逐歌偏移、entitlements、包名、MinOS 均未碰",
      "floatingSceneEverConnected" in td24
      and "(UnsafeMutableRawPointer, CFString, UnsafeMutablePointer<Unmanaged<CFError>?>?)" in read("Compatibility/EffectiveEntitlements.swift")
      and "native-candidate" in td24
      and '"tlds.pipTestStage"' in read("Renderer/PiPLyricsRenderer.swift")
      and "https://guhailong-repo.pages.dev/api/verify" in ls24
      and "timeOffset" in ls24
      and "com.ycwl.Lyrics" in read("TrollLyricsDesk/Info.plist"))

print("\n== 20. build 25 启动＋回前台重建兜底（皇上 2026-11-27 14:30 定） ==")
td25 = read("Overlay/TLDSAppDelegate.m")
th25 = read("Overlay/TLDSAppDelegate.h")
ls25 = read("Lyrics/LyricStore.swift")
ta25 = read("App/TrollLyricsDeskApp.swift")
mra25 = read("MusicProviders/MediaRemoteAdapter.swift")
_pbx25 = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
check("build 25（兜底一）：Shell 回调里有守卫——场景已由兜底建好就跳过，不建第二个窗",
      "Shell 回调到了，悬浮场景已由兜底建好，跳过" in td25)
check("build 25（兜底一）：看门狗／回前台直接建场景——reactivate 里调同款 createFloatingSceneWithIdentifier",
      "启动兜底：Shell 回调未到，直接建悬浮场景" in td25
      and td25.index("启动兜底：Shell 回调未到，直接建悬浮场景") > td25.index("reactivateFloatingOverlayWithTrigger"))
check("build 25（兜底一）：启动 2 秒内不抢建——launchTime 在 didFinishLaunching 里记，直接建要过 2.0 秒门槛",
      "self.launchTime = CFAbsoluteTimeGetCurrent();" in td25
      and "now25 - self.launchTime < 2.0" in td25
      and "double launchTime" in th25)
check("build 25（兜底二）：卡住超时 10 秒——floatingSceneCreatedTime 在创建时记，超 10 秒未连上走重建",
      "self.floatingSceneCreatedTime = CFAbsoluteTimeGetCurrent();" in td25
      and "now - self.floatingSceneCreatedTime < 10.0" in td25
      and "判定卡住，走重建" in td25
      and "double floatingSceneCreatedTime" in th25)
check("build 25：#1 守卫不动——连接窗口（10 秒内）仍跳过恢复，build 21 闪退保护在",
      "场景正在连接中，跳过这次恢复" in td25
      and "floatingSceneEverConnected" in td25)
check("build 25：解锁重建原样不动——rebuildFloatingOverlay 仍在，3 秒节流与未连上跳过销毁都在",
      "锁屏恢复：完整重建悬浮场景" in td25
      and "now - self.lastRebuildTime < 3.0" in td25
      and "跳过销毁旧场景会话" in td25)
check("build 25：保活不动——BackgroundKeepAlive 仍在巨魔模式下启动，一字未改",
      "BackgroundKeepAlive.shared.start()" in ta25
      and "if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }" in ta25)
check("build 25：@escaping 不动——GetNowPlayingInfo 回调仍是 @escaping（build 23 闪退修法，逃逸检查点保持 2 个的源码依据）",
      "@escaping (CFDictionary?) -> Void" in mra25
      and "@convention(block) (CFDictionary?) -> Void" not in mra25
      and "withoutActuallyEscaping" not in mra25)
open_item("build 25 真机验①：冷启动后退到主屏幕，悬浮窗在不在",
          "11:05 那次重启动后退出来没有窗——修完冷启动 2 秒后看门狗兜底应已建好窗，"
          "退到主屏幕窗应在；日志里应有「启动兜底」或「系统 Shell 注册成功」＋创建行")
open_item("build 25 真机验②：锁屏→解锁，悬浮窗在不在",
          "10:56 那次解锁后主屏幕没窗——修完解锁重建照常跑；若进程还活着，窗应直接在；"
          "若进程被杀，解锁时没人重建，看第③项")
open_item("build 25 真机验③：锁屏久一点（等进程被杀）→解锁→打开一次 App，窗回不回来",
          "核心验收：进程被杀后重启动，2 秒内看门狗兜底建窗，打开 App 再退到主屏幕窗应回来；"
          "日志里应有「启动兜底」行，且只建一个窗（回调守卫，不建两个）")
open_item("build 25 真机验：主页面不闪退（#1 守卫仍在）",
          "连接窗口（10 秒内）看门狗仍跳过恢复；验：进主页面不闪、悬浮窗／激活／逐歌偏移照常")
open_item("build 25 真机验：只建一个窗",
          "兜底建窗＋Shell 回调晚到、解锁重建＋旧窗残留两种情况都不应出现两个窗；"
          "日志里活着的悬浮场景数应为 1")


print("\n== 21. build 26 前台复核兜底（皇上 2026-11-27 15:14 定「直接修，加兜底复核」） ==")
td26 = read("Overlay/TLDSAppDelegate.m")
th26 = read("Overlay/TLDSAppDelegate.h")
ls26 = read("Lyrics/LyricStore.swift")
ta26 = read("App/TrollLyricsDeskApp.swift")
mra26 = read("MusicProviders/MediaRemoteAdapter.swift")
_pl26 = [plistlib.loads(open(os.path.join(ROOT, r), "rb").read())
         for r in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]]
_pbx26 = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
_vt26 = re.search(r'static let versionTag = "([^"]+)"', ls26)
check("build 26（复核入口）：回到前台通知里排 1.5 秒复核，同一次回前台只排一次（scheduled 守卫）",
      "foregroundVerifyFloatingWindow" in td26
      and "if (!self.foregroundVerifyScheduled)" in td26
      and "foregroundVerifyScheduled = YES" in td26
      and "1.5 * NSEC_PER_SEC" in td26
      and td26.index("foregroundVerifyFloatingWindow") > td26.index("tlds_reactivateFromForegroundNotification"))
check("build 26（复核入口）：复核方法与守卫属性在 .h 声明",
      "- (void)foregroundVerifyFloatingWindow;" in th26
      and "foregroundVerifyScheduled" in th26
      and "foregroundVerifyRetries" in th26)
check("build 26（判据）：只认窗口本身——非空／isHidden=NO／alpha>0／windowScene 非空／视图已挂上",
      "w != nil && !w.isHidden && w.alpha > 0 && w.windowScene != nil" in td26
      and "w.rootViewController.view.window == w" in td26)
check("build 26（日志）：窗在记「在，不动」，窗不在记「不在，走重建（触发：foreground-verify）」",
      "诊断1.0.6 前台复核：悬浮窗在，不动" in td26
      and "诊断1.0.6 前台复核：悬浮窗不在，走重建（触发：foreground-verify" in td26)
check("build 26（宽限）：场景刚建好还在连接时不到 2 秒不判「不在」，最多再排一次（1.5 秒后）；10 秒卡住线复用 build 25",
      "age < 2.0" in td26
      and "场景正在连接中，先不动" in td26
      and "foregroundVerifyRetries < 2" in td26
      and "age < 10.0" in td26
      and "场景创建已超过 10 秒仍未连接，判定卡住，走重建（触发：foreground-verify" in td26)
check("build 26（节流）：重建 3 秒节流内被拦住时 3.5 秒后再验一次，不让这次回前台白跑",
      "3 秒节流内，3.5 秒后再验一次" in td26
      and "3.5 * NSEC_PER_SEC" in td26)
check("build 26：复核只验不直接建场景——创建归 build 25 启动兜底，窗不在走现成的 rebuildFloatingOverlay",
      "rebuildFloatingOverlay" in td26
      and td26.count("[self rebuildFloatingOverlay]") >= 2
      and "createFloatingSceneWithIdentifier" in td26)
check("build 26：解锁重建原样不动——rebuildFloatingOverlay 仍在，3 秒节流与未连上跳过销毁都在",
      "锁屏恢复：完整重建悬浮场景" in td26
      and "now - self.lastRebuildTime < 3.0" in td26
      and "跳过销毁旧场景会话" in td26)
check("build 26：build 25 启动兜底在位——Shell 回调守卫＋看门狗／回前台直接建＋启动 2 秒门槛",
      "启动兜底：Shell 回调未到，直接建悬浮场景" in td26
      and "Shell 回调到了，悬浮场景已由兜底建好，跳过" in td26
      and "now25 - self.launchTime < 2.0" in td26)
check("build 26：#1 守卫不动——连接窗口（10 秒内）仍跳过恢复，build 21 闪退保护在",
      "场景正在连接中，跳过这次恢复" in td26
      and "floatingSceneEverConnected" in td26)
check("build 26：保活不动——BackgroundKeepAlive 仍在巨魔模式下启动，一字未改",
      "BackgroundKeepAlive.shared.start()" in ta26
      and "if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }" in ta26)
check("build 26：@escaping 不动——GetNowPlayingInfo 回调仍是 @escaping（build 23 闪退修法，逃逸检查点保持 2 个的源码依据）",
      "@escaping (CFDictionary?) -> Void" in mra26
      and "@convention(block) (CFDictionary?) -> Void" not in mra26
      and "withoutActuallyEscaping" not in mra26)
open_item("build 26 真机验①：冷启动后退到主屏幕，悬浮窗在不在",
          "build 25 那项已过——修完冷启动 2 秒后看门狗兜底应已建好窗，退到主屏幕窗应在；"
          "日志里应有「启动兜底」或「系统 Shell 注册成功」＋创建行；回前台复核应记「悬浮窗在，不动」")
open_item("build 26 真机验②：锁屏→解锁→打开一次 App，悬浮窗回不回来（核心验收）",
          "build 25 那项在主屏幕上没窗——修完解锁重建仍在后台跑，打开 App 回前台 1.5 秒后"
          "复核应验到窗不在（或场景还在连接），走重建（触发：foreground-verify），"
          "再退到主屏幕窗应回来；日志里应有「前台复核：悬浮窗不在，走重建」＋重建行。"
          "注意：复核只在回前台时跑，不开 App 只解锁，主屏幕上仍可能没窗——"
          "那是已知局限（后台重建≠可见），不是复核没跑")
open_item("build 26 真机验③：锁屏久一点（等进程被杀）→解锁→打开一次 App，窗回不回来",
          "进程被杀后重启动，2 秒内看门狗兜底建窗，打开 App 再退到主屏幕窗应回来；"
          "日志里应有「启动兜底」行，且只建一个窗（回调守卫，不建两个）")
open_item("build 26 真机验：主页面不闪退（#1 守卫仍在）",
          "连接窗口（10 秒内）看门狗仍跳过恢复，前台复核也不重建正在连接的场景；"
          "验：进主页面不闪、悬浮窗／激活／逐歌偏移照常")
open_item("build 26 真机验：只建一个窗",
          "前台复核走重建时先销毁旧会话（连上过才销毁）、只建一个新窗；"
          "日志里活着的悬浮场景数应为 1")


print("\n== 22. build 27 解锁重现（皇上 2026-11-27 15:45 定「继续修：解锁后直接有窗」） ==")
td27 = read("Overlay/TLDSAppDelegate.m")
th27 = read("Overlay/TLDSAppDelegate.h")
ls27 = read("Lyrics/LyricStore.swift")
ta27 = read("App/TrollLyricsDeskApp.swift")
mra27 = read("MusicProviders/MediaRemoteAdapter.swift")
_pl27 = [plistlib.loads(open(os.path.join(ROOT, r), "rb").read())
         for r in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]]
_pbx27 = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
_vt27 = re.search(r'static let versionTag = "([^"]+)"', ls27)
check("build 27：版本号三处一致——两 plist CFBundleVersion=27、pbxproj 4 处、versionTag 是 build 27（build 28 起见 §23，此处已随版本前滚）",
      all(p.get("CFBundleVersion") == "28" for p in _pl27)
      and _pbx27.count("CURRENT_PROJECT_VERSION = 28;") == 4
      and _vt27 is not None and _vt27.group(1).startswith("build 28"),
      _vt27.group(1) if _vt27 else "无 versionTag")
check("build 27（解锁重现方法）：unlockRestoreFloatingOverlay 在 .m 实现、.h 声明",
      "- (void)unlockRestoreFloatingOverlay {" in td27
      and "- (void)unlockRestoreFloatingOverlay;" in th27)
check("build 27（解锁入口）：Darwin 锁屏轮询确认解锁后调 unlockRestoreFloatingOverlay，不再直接调 rebuildFloatingOverlay",
      "[appDelegate unlockRestoreFloatingOverlay];" in td27
      and "[appDelegate rebuildFloatingOverlay];" not in td27)
check("build 27（重现优先）：旧场景可用（场景非空＋已连＋窗口在）时走 reactivate「解锁重现」，不销毁、不新建",
      "self.floatingScene && self.floatingSceneCreated && self.floatingWindow" in td27
      and '[self reactivateFloatingOverlayWithTrigger:@"解锁重现"]' in td27
      and "诊断1.0.6 解锁重现：旧场景还在" in td27)
check("build 27（兜底）：旧场景不在时记「旧场景已不在」并走完整重建 rebuildFloatingOverlay",
      "诊断1.0.6 解锁重现：旧场景已不在" in td27
      and "[self rebuildFloatingOverlay];" in td27)
check("build 27（重现后复核）：重现后 2 秒记「解锁重现后复核」行（窗口状态，本地状态≠屏幕可见）",
      "诊断1.0.6 解锁重现后复核：" in td27
      and "2.0 * NSEC_PER_SEC" in td27
      and "本地状态≠屏幕可见，见主屏幕为准" in td27)
check("build 27（不动）：完整重建 rebuildFloatingOverlay 原样在位——3 秒节流、未连上跳过销毁、换新标识都在",
      "锁屏恢复：完整重建悬浮场景" in td27
      and "now - self.lastRebuildTime < 3.0" in td27
      and "跳过销毁旧场景会话" in td27)
check("build 27（不动）：build 26 前台复核在位——foregroundVerifyFloatingWindow＋触发 foreground-verify",
      "foregroundVerifyFloatingWindow" in td27
      and "foreground-verify" in td27)
check("build 27（不动）：build 25 启动兜底在位——Shell 回调守卫＋看门狗／回前台直接建＋启动 2 秒门槛",
      "启动兜底：Shell 回调未到，直接建悬浮场景" in td27
      and "Shell 回调到了，悬浮场景已由兜底建好，跳过" in td27
      and "now25 - self.launchTime < 2.0" in td27)
check("build 27（不动）：#1 守卫不动——连接窗口（10 秒内）仍跳过恢复，build 21 闪退保护在",
      "场景正在连接中，跳过这次恢复" in td27
      and "floatingSceneEverConnected" in td27)
check("build 27（不动）：保活不动——BackgroundKeepAlive 仍在巨魔模式下启动，一字未改",
      "BackgroundKeepAlive.shared.start()" in ta27
      and "if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }" in ta27)
check("build 27（不动）：@escaping 不动——GetNowPlayingInfo 回调仍是 @escaping（build 23 闪退修法，逃逸检查点保持 2 个的源码依据）",
      "@escaping (CFDictionary?) -> Void" in mra27
      and "@convention(block) (CFDictionary?) -> Void" not in mra27
      and "withoutActuallyEscaping" not in mra27)
check("build 27（不动→build 28 已改）：歌词「·」识别修法在 build 27 时不在——build 28 已加入（见 §23）",
      '" — ", " – ", " - ", " · ", "—", "–"' in ls27)
open_item("build 27 真机验①：冷启动后退到主屏幕，悬浮窗在不在（歌词当前行在不在）",
          "build 26 那项已过——冷启动 2 秒后看门狗兜底应已建好窗，退到主屏幕窗应在，"
          "歌词应是当前行；日志里应有「启动兜底」或「系统 Shell 注册成功」＋创建行")
open_item("build 27 真机验②：锁屏→解锁→主屏幕，悬浮窗和歌词回不回来（核心验收，不开 App）",
          "解锁后主屏幕上应直接有窗，窗里是当前歌词行（跟着歌走）；"
          "日志里应有「解锁重现：旧场景还在」＋「解锁重现后复核」行；"
          "注意：本地状态好≠屏幕可见——以主屏幕肉眼为准，日志只证明重现跑没跑")
open_item("build 27 真机验③：锁屏久一点（等进程被杀）→解锁→打开一次 App，窗回不回来",
          "进程被杀后重启动，2 秒内看门狗兜底建窗，打开 App 再退到主屏幕窗应回来；"
          "日志里应有「启动兜底」行，且只建一个窗（回调守卫，不建两个）")
open_item("build 27 真机验：主页面不闪退（#1 守卫仍在）",
          "连接窗口（10 秒内）看门狗仍跳过恢复；验：进主页面不闪、悬浮窗／激活／逐歌偏移照常")
open_item("build 27 真机验：只建一个窗",
          "解锁重现不销毁、不新建；旧场景不在走重建时先销毁旧会话、只建一个新窗；"
          "日志里活着的悬浮场景数应为 1，悬浮窗控制器初始化次数不应多一次")


print("\n== 23. build 28 「·」歌词识别修法＋锁屏诊断日志两行（皇上 2026-11-27 21:05 定：停掉后台 Scene 重发/重建/重现路线；build 28 只留「·」修法＋必要诊断日志，不拉长轮询、不加事件监听） ==")
td28 = read("Overlay/TLDSAppDelegate.m")
ls28 = read("Lyrics/LyricStore.swift")
pc28 = read("PlaybackEngine/PlaybackCoordinator.swift")
mra28 = read("MusicProviders/MediaRemoteAdapter.swift")
ta28 = read("App/TrollLyricsDeskApp.swift")
_pl28 = [plistlib.loads(open(os.path.join(ROOT, r), "rb").read())
         for r in ["TrollLyricsDesk/Info.plist", "TrollLyricsWidget/Info.plist"]]
_pbx28 = read("TrollLyricsDesk.xcodeproj/project.pbxproj")
_vt28 = re.search(r'static let versionTag = "([^"]+)"', ls28)
check("build 28：版本号三处一致——两 plist CFBundleVersion=28、pbxproj 4 处、versionTag 是 build 28",
      all(p.get("CFBundleVersion") == "28" for p in _pl28)
      and _pbx28.count("CURRENT_PROJECT_VERSION = 28;") == 4
      and _vt28 is not None and _vt28.group(1).startswith("build 28"),
      _vt28.group(1) if _vt28 else "无 versionTag")
check("build 28（「·」识别①）：songIdentityParts 认 \" · \"——分隔符六种，两处（artistCarriesLyric 镜像＋songIdentityParts）",
      ls28.count('" — ", " – ", " - ", " · ", "—", "–"') == 2)
check("build 28（「·」识别②）：searchTerms 存在——只拆 \" · \"，head=歌名、tail=歌手，artist 先、title 后，无 \" · \" 原样返回；例歌在注释里",
      "static func searchTerms(title: String, artist: String) -> (track: String, artist: String) {" in ls28
      and 'field.range(of: " · ")' in ls28
      and "for field in [artist, title]" in ls28
      and "return (head, tail)" in ls28
      and "return (title, artist)" in ls28
      and "为你等天晴 · 桃枝渡晚" in ls28
      and "血染江山的画怎敌你眉间 一点朱砂 · 清越" in ls28)
check("build 28（「·」识别③）：loadLyrics 用解析后的 searchTrack 搜词＋匹配＋缓存，搜词提示用真歌名",
      "let searchTrack = MusicTrack(" in pc28
      and "LRCLibClient.shared.search(\n                track: searchTrack" in pc28
      and "track: searchTrack" in pc28
      and 'message = "正在搜索歌词：\\(searchTrack.title)"' in pc28)
check("build 28（「·」识别④）：两处缓存查键都用 searchTerms 解析后——新歌分支＋publishImmediately",
      pc28.count("LyricStore.searchTerms(") == 3)
check("build 28（「·」识别⑤）：换歌键仍走 stableSongIdentity——trackKey 不动，逐歌偏移键不动",
      "LyricStore.stableSongIdentity(" in pc28
      and "offsetKeyPrefix + stableSongIdentity(title: title, artist: artist)" in ls28)
check("build 28（诊断①）：收到 Darwin 通知记一行——TLDSLockStateChanged 里「解锁：收到 Darwin 通知」",
      "诊断1.0.6 解锁：收到 Darwin 通知" in td28)
check("build 28（诊断②）：16 次轮询过期记一行——最后一轮（i == attempts - 1）且仍未确认才记",
      "诊断1.0.6 解锁：16 次轮询过期，未确认解锁" in td28
      and "i == attempts - 1" in td28)
check("build 28（不动①）：轮询窗口不拉长——attempts 仍 16，延迟公式 0.15 + i * 0.25 原样",
      "int attempts = 16;" in td28
      and "double delay = 0.15 + i * 0.25;" in td28)
_src28 = []
for _dp, _dn, _fs in os.walk(ROOT):
    if "hidden_files" in _dp or ".git" in _dp:
        continue
    for _f in _fs:
        if _f.endswith((".m", ".h", ".swift")):
            _src28.append(os.path.join(_dp, _f))
check("build 28（不动②）：不加事件监听——产品源码全树无 UIApplicationProtectedDataDidBecomeAvailableNotification",
      not any("UIApplicationProtectedDataDidBecomeAvailableNotification" in open(_p, errors="ignore").read() for _p in _src28))
check("build 28（不动③）：解锁重现／重建／前台复核逻辑一字未改——unlockRestore 调用、rebuild 兜底、foregroundVerify 都在",
      "[appDelegate unlockRestoreFloatingOverlay];" in td28
      and "锁屏恢复：完整重建悬浮场景" in td28
      and "foregroundVerifyFloatingWindow" in td28)
check("build 28（不动④）：@escaping 不动——GetNowPlayingInfo 回调仍是 @escaping（build 23 闪退修法）",
      "@escaping (CFDictionary?) -> Void" in mra28
      and "@convention(block) (CFDictionary?) -> Void" not in mra28)
check("build 28（不动⑤）：#1 守卫＋保活不动——连接窗口仍跳过恢复，BackgroundKeepAlive 仍在巨魔模式下启动",
      "场景正在连接中，跳过这次恢复" in td28
      and "if !LyricStore.isLiveContainer { BackgroundKeepAlive.shared.start() }" in ta28)
check("build 28（不动⑥）：锁屏歌词不恢复——两 plist 都无 NSSupportsLiveActivities",
      all("NSSupportsLiveActivities" not in p for p in _pl28))
open_item("build 28 真机验①：放「·」型歌（汽水音乐放《为你等天晴》）——「检测到新歌曲」整首只跳一次，不再每句一跳",
          "放歌后看日志：换歌行只在切歌时出现一次；接着几句歌词不应再出现「检测到新歌曲」；"
          "trackKey 不再每句变，syncLiveLyricsAndProgress 应正常走（进度不跳变）")
open_item("build 28 真机验②：搜词用真歌名/真歌手——《为你等天晴》应搜到同步歌词（LRCLIB 有这首就命中）",
          "搜到则悬浮窗显示同步歌词行（按进度走）；搜不到则看日志「没有找到匹配的同步歌词：为你等天晴」——"
          "搜词名必须是真歌名，不再是歌词行；第二次放同一首歌应走本地缓存（「本地歌词命中」），不再联网")
open_item("build 28 真机验③：普通播放器（Apple Music 等）不受影响——换歌、搜词、缓存照常",
          "「·」修法只在字段含 \" · \" 时才改行为，无 \" · \" 原样返回；"
          "逐歌偏移（[offset:] 叠加）不动，以前调过的偏移不必重调")
open_item("build 28 真机验④：锁屏→解锁，看两行新诊断日志",
          "锁屏→解锁后日志里应有「解锁：收到 Darwin 通知 …，开始轮询确认解锁」；"
          "若密码输得慢（4 秒轮询过期），应有「16 次轮询过期，未确认解锁」行；"
          "这两行只是诊断，不改行为——窗的恢复仍按 build 27（重现跑了但贴不上是已知限度，等 HUD 专项）")
open_item("build 28 真机验：主页面不闪退、只建一个窗、激活／逐歌偏移照常",
          "只改搜词＋两行日志；进主页面不闪、悬浮窗／激活／逐歌偏移照常；"
          "解锁重现、重建、前台复核、保活全没动")


print("\n== 10. OPEN（只能真机／macOS 编的，如实列，不编通过） ==")
open_item("macOS 编译未做（Linux 没 Xcode/swiftc）",
          "ActivityKit 弱链接、DynamicIsland 展开区、if #available 组合、"
          "TLDSInstallNativeWindowFix 与分类 hook 并存，都要 macOS 构建才见分晓")
open_item("五件要真机验：Telegram 行／日志复制／背景图／固定位置／提示行＋标题居中",
          "点 Telegram 行进 @Guhailon 频道；日志复制贴到别处；背景设置选图后四处立即换图、"
          "开关关变纯黑、透明度滑杆跟手；固定开关开后悬浮窗拖不动、提示行变“已固定”；"
          "标题居中、齿轮仍右上")
open_item("激活要真机验：首次打开弹激活页，码对放行、码错报“激活码不正确”、断网报“需要联网激活”",
          "激活后不用重启进主界面；悬浮窗与小组件在未激活时分别是隐藏与占位")
open_item("锁屏已取消，不再验（皇上 2026-11-26 21:46 令）",
          "1.0.1 起从未在真机上证实可用；代码在 git 历史 newbase e0c154a 里，"
          "以后想加回来可从那恢复；build 18 已发包里的锁屏不动")
open_item("LC 兼容要真机验：同 IPA 导入 LiveContainer 能启动、应用内歌词 0.25s 刷新、"
          "暂停／归零可用；巨魔模式悬浮窗／锁屏／保活一切照旧",
          "LiveContainer 的进程模型＋后台行为没验过；检测是启发式，不是权限证明")
open_item("二进制字面量扫描的限制（已查明，非缺陷；见 RUN 第三阶段）",
          "Release 二进制里 ≤15 字节的行内字面量（livecontainer／/lcapps/／"
          "LCAppDelegate／桌面歌词等）以 small-string immediates 进代码段，"
          "不在 __cstring 里，字节扫描不到；＞15 字节或 static-let 字面量"
          "（TLDSLiveContainer／lyric.timeOffset|／tld.activated）在位；"
          "方法名符号 Release 下被 strip，源码级核查为准；LC 宿主模式"
          "是否真生效只能真机验")
open_item("验包时 ActivityKit 应为不在位（锁屏已取消，弱链接已删）",
          "macho_inspect.py 查两二进制：ActivityKit 不应再出现；"
          ".tbd 直链（FrontBoard／FrontBoardServices／RunningBoardServices／"
          "AppleAccount）是悬浮窗的，仍应在位")


open_item("暂停进度修正要真机验（30 秒处暂停，5 秒后进度应停在 30 秒附近，不涨到 35 秒）",
          "只改了 MediaRemoteAdapter 的估算公式与缓存逻辑，未改同步修正；"
          "暂停后歌词行是否还跟着错误进度走，以真机为准")
open_item("Engine Fix 换歌／搜词代次要真机验（快切歌时旧任务歌词不写进新歌）",
          "generation 守卫＋缓存优先是源码级并入，只过自检，未过 Xcode 编译；"
          "真机上快切两三首歌，看歌词是否跟当前歌走")
open_item("LyricParser [offset:] 与逐歌偏移叠加要真机验",
          "解析层 [offset:] 只改解析出的时间，逐歌 timeOffset 另在 lookup 时叠加；"
          "以前给带 [offset:] 的歌手调过的逐歌偏移可能要重调（旧解析忽略 [offset:]，"
          "手调值可能一直在替它补，见 RUN 附二）")
open_item("EngineTests LRC 回归测试本机没跑成（无 swiftc），以云端构建＋真机为准",
          "包自称 Linux 下 LRC 测试通过，但本机无 Swift 工具链，没法复核；"
          "解析逻辑是源码级审过，不是执行验证")
open_item("LC 激活存储统一要真机验（LC 里激活成功后应直接进主界面，不再停留激活页）",
          "只改了存储入口，激活流程／服务端校验一字未动；"
          "巨魔模式下 LyricStore.defaults 就是 App Group suite，行为不变")
open_item("1.0.6 真机验（主线：LC 机 iPhone 18 Pro Max／iOS 27.0.1）——P0 第一项：放着 QQ 音乐，看回调里 info 有没有内容、歌名读不读得到",
          "签名修正（回调改 block、注册改只收队列）是首要怀疑；若放着歌仍 info=nil，"
          "诊断页应写「P0：放着歌还读不到（isPlaying=YES，info=nil）」，日志里应有对应的 P0 行；"
          "若读到了，readStatus 应是 ok，歌名正常显示")
open_item("1.0.6 真机验（LC 机）——安装环境行：不应再出现 trollstore／模式翻转",
          "启动时安装环境应是 livecontainer（LC 信号命中）或 unknown（信号全漏时落 native-candidate），"
          "绝不是 trollstore；2 秒后不应出现复核改模式的行；结论行应是「托管结构检查通过；"
          "实际屏幕可见性未确认」，不是「已确认可见」")
open_item("1.0.6 真机验（LC 机）——三项判定各自是什么（诊断页分行看）",
          "安装环境／显示能力／权限对照三行各自的结论与理由；托管复核只定显示能力，"
          "安装环境行在复核后不应变；Context ID 未知时结论行写清三段（托管结构检查：通过／"
          "Context ID：未知／实际屏幕可见性：未确认）")
open_item("1.0.6 真机验（LC 机）——检测引擎计数恒为 1（同一次启动内）",
          "12 次重启那次是 14:46–47 那段（连点按钮疑似）；重测干净单次启动是对照；"
          "修完同一启动内「检测引擎启动第 N 次」应恒为 1，前台回来也不重起")
open_item("1.0.6 真机验（LC 机）——解锁重建不应再建第二个悬浮窗",
          "14:59:44 那次建了 TLDSFloatingLyric_1、旧窗疑似还在；修完重建前应先销毁旧场景／旧窗口，"
          "诊断里记清当前有几个悬浮窗、各自什么标识；只建一个窗")
open_item("1.0.6 真机验（LC 机）——后台终止原因：进程后台活多久、终止时记了什么",
          "23:23 重测：进程后台只活约 3 分钟就被终止；第 8 项只记事实——系统杀／宿主杀／"
          "自己退，查不到写「原因未知」，不编；LC 下保活本来就被跳过，后台 3 分钟被终止是预期行为")
open_item("1.0.6 真机验（LC 机）——PiP 两段分开验（固定文字段先，实时歌词段后）",
          "两段各有各的诊断页状态行（未开始／进行中／已显示／失败＋原因）；"
          "PiP 能显示不代表能自动拿到别的播放器的歌")
open_item("1.0.6 真机验（另一条：巨魔机 iPhone 11／TrollStore）——巨魔原生回归",
          "日志应是「巨魔原生模式」，无复核行；检测引擎计数恒为 1；"
          "与 LC 机分开列期望，不要把两台机的结果混在一起判")
open_item("1.0.6 真机验（两台机）——激活前后快照：激活成功不应丢窗",
          "激活前、激活成功后各记一次悬浮窗状态（窗口在不在、isHidden、windowScene、frame）；"
          "14:45:36 激活成功前后那两条「锁屏恢复」行要能对上快照")
open_item("OPEN：isPlaying 假定签名待真机验证（(dispatch_queue_t, completion(Boolean))，completion 为 block）",
          "与 GetNowPlayingInfo 同族，签名按 block 声明；符号缺失时回退、不伪造；"
          "若 LC 机上 isPlaying 查不到，readStatus 应是「疑似 P0」而不是编一个结论")
open_item("OPEN：LC 信号在确认的 LC 机上是否命中（父进程名探测 proc_pidpath(getppid()) 是否为 LiveContainer）",
          "若 LC 信号全漏，安装环境落 signature／inApp，行为正确、标签待收敛；"
          "Info.plist 键 TLDSLiveContainer 在本工程里从来没设过值，单 IPA 不能把它写死 true")
open_item("OPEN：os_proc_available_memory 后台内存读数（第 8 项终止原因的辅助证据）",
          "只记读数，不由此编终止原因")
open_item("1.0.6 诊断要真机验：日志页抄回诊断行（见 RUN_1.0.6.md 待验清单）",
          "MediaRemote dlopen/dlsym／调用次数／回调次数／info 有无／isPlaying 结果；"
          "强制测试开关开后悬浮窗是否出现测试文字；托管复核逐项结论；运行模式进了哪档；"
          "启动计数是否都为 1")
open_item("LC 里首次调用 FBSystemShellInitialize 的风险未验证",
          "1.0.4／newbase 在宿主模式下从不调它；1.0.5 为探测增强宿主改为尝试＋复核，"
          "调用包在 @try/@catch 里、回调不来时 6 秒兜底复核判兼容；若 LC 真机启动就闪退，"
          "第一嫌疑就是这次尝试——日志里若连「待探测」都没有，就是启动时崩了")
open_item("PiP 是实验引擎，真机只验到哪一步以实测为准（RUN_1.0.6.md §五）",
          "先验固定测试文字能否在桌面／其他 App 上方出现，再接实时歌词；"
          "透明背景受限、拖动由系统控制、锁屏不保证；PiP 能显示不代表能拿到别的播放器的歌")
open_item("三档模式的复核时序未验证",
          "复核在创建后 2 秒跑、场景未连上时 3 秒后再跑一次；真机上场景连接若慢于 5 秒，"
          "会误判兼容——日志里「复核推迟」出现几次、最终进了哪档，以真机为准")
open_item("build 22 真机验（LC 机 iPhone 13 Pro／iOS 27.0.1）：进主页面不再闪退",
          "只禁 isPlaying 探针：决定性实验——若不闪了，#2 就是崩点（或崩点之一）；"
          "若还闪，#2 排除，下一处查 #4 场景创建时序；验：进主页面不闪、悬浮窗／激活／逐歌偏移照常、"
          "日志里应有「build 22：isPlaying 探针已禁用」行")
open_item("build 23 真机验（LC 机 iPhone 13 Pro／iOS 27.0.1）：进主页面不再闪退",
          "只改 GetNowPlayingInfo 回调回 @escaping：病根修复实验——若不闪了，逃逸检查就是崩点；"
          "若还闪，#2／回调签名都排除，下一处查 #4 场景创建时序；验：进主页面不闪、悬浮窗／激活／逐歌偏移照常、"
          "日志里仍应有「build 22：isPlaying 探针已禁用」行（探针仍禁着）")
open_item("build 24 真机验（主线：巨魔机 iPhone 11／iOS 16.5／Dopamine rootless／TrollStore）——五项核心功能",
          "皇上 2026-11-27 10:20 定巨魔版是正式开发主线：(1) MediaRemote 实际权限"
          "（SecTask 实测 platform-application／no-sandbox 是不是 YES）；"
          "(2) 三大音乐平台读歌（QQ 音乐／酷我／网易云，放着歌看歌名读不读得到）；"
          "(3) 歌词同步（逐歌偏移、LRCLIB 跟随）；(4) 跨 App 悬浮窗"
          "（退到桌面／别的 App 上方有没有歌词窗）；(5) 后台稳定性"
          "（后台保活、回前台不丢窗、不闪退）")
open_item("build 24 真机验（LC 机复核：iPhone 13 Pro／iOS 27.0.1／LiveContainer 3.8.12）——环境识别修完后的复核",
          "安装环境应判 livecontainer（LC_HOME_PATH 信号命中），不再是「普通签名（沙盒内）」；"
          "日志里应有「诊断1.0.6 环境检测」两行（进程名／Home 目录／bundle 路径／argv[0]／"
          "LC_HOME_PATH 值／各信号结果）＋「诊断1.0.6 版本」对账行；探针日志应写 build 24，"
          "不再是 build 22；每次定档后应有「诊断1.0.6 悬浮窗复核摘要」行")
open_item("build 24：dSYM 产物在且 UUID 对得上（验包时核对，不进自检）",
          "CI 同一个 run 应有两个产物（桌面歌词-1.0.6 IPA＋桌面歌词-1.0.6-dSYM）；"
          "下载 dSYM 后核对它的 UUID 与 IPA 二进制的 Mach-O UUID 一致（App 与 Widget 各一对）；"
          "zsign 重签不应改 LC_UUID，若对不上，先查是不是 zsign 改了 UUID")
open_item("不上源已定（皇上 2026-11-27 10:22）：TrollLyricsDesk 不部署到越狱源",
          "现在就定了，不用等验收；真机验收照常继续；RUN §十四按已定版写，"
          "不要再写「等验收通过再定上源」")
open_item("build 21 真机验（LC 机 iPhone 13 Pro／iOS 27.0.1）：进主页面不再闪退",
          "只修重建竞态：主页面出现那一刻 DidBecomeActive／2 秒看门狗在连接窗口里跳过恢复，"
          "rebuild 不销毁未连上的会话；验：进主页面不闪、悬浮窗／激活／逐歌偏移照常、"
          "解锁重建仍只建一个窗；PiP 两段、P0 仍按 build 20 的清单验")

print()
print("FAILED:", fails if fails else "none")
print("OPEN:", len(opens), "items (see above)")
sys.exit(1 if fails else 0)

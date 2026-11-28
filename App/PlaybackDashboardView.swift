import SwiftUI
import MediaPlayer

/// 主界面：播放状态面板。
/// - 去掉了原「播放状态」大标题 + 波形图标，以及「没有找到匹配的同步歌词」提示；
/// - 背景与原主界面保持一致的紫 → 黑 → 蓝渐变；
/// - 内容整体上移；
/// - 右上角齿轮进入「设置」，设置里含「设置 / 关于」两个入口。
struct PlaybackDashboardView: View {

    // 复用 App 级检测引擎（TrollLyricsRuntime 注入）。
    @EnvironmentObject private var coordinator: PlaybackCoordinator

    /// 悬浮歌词窗开关（与悬浮控制器共享存储 LyricStore.defaults 的 floatingLyric.enabled）。
    /// UserDefaults.bool 未设置时返回 false，所以这里显式注册默认值 true。
    @AppStorage("floatingLyric.enabled", store: LyricStore.defaults)
    private var floatingEnabled = true

    /// 悬浮窗固定位置开关（与悬浮控制器共享存储 LyricStore.defaults 的 floatingLyric.positionLocked）。
    /// 默认 false（可拖）；打开后悬浮窗拖不动，位置保持上次存好的地方。
    @AppStorage("floatingLyric.positionLocked", store: LyricStore.defaults)
    private var positionLocked = false

    /// 2.0.2：药丸固定位置开关——新键 hudPill.positionLocked（不要复用
    /// 上面那把已死的 floatingLyric.positionLocked）。开 = 拖动不响应，
    /// 关 = 可以拖动；默认关。守护进程每秒 tick 重读。
    @AppStorage("hudPill.positionLocked", store: LyricStore.defaults)
    private var hudPillPositionLocked = false

    /// 2.0.4：药丸位置滑块——横向／纵向两条，直接写 hudPill.positionX／Y
    /// （与 2.0.2 拖动、2.0.3 直接拖动共用同一对键，不另发明键；
    /// daemon 每秒 tick 重读，键变了就移药丸，拖动中不抢）。
    /// 固定位置开时滑块置灰（.disabled），关时能拖。进页面时 onAppear
    /// 从共享存储读回当前药丸位置（没拖过就没有键，用默认居中偏上）。
    @State private var pillSliderX: Double = Double(UIScreen.main.bounds.width) / 2
    @State private var pillSliderY: Double = 120

    private func syncPillSliders() {
        let store = LyricStore.defaults
        let width = Double(UIScreen.main.bounds.width)
        let height = Double(UIScreen.main.bounds.height)
        if let x = store?.object(forKey: "hudPill.positionX") as? NSNumber {
            pillSliderX = min(max(x.doubleValue, 0), width)
        } else {
            pillSliderX = width / 2
        }
        if let y = store?.object(forKey: "hudPill.positionY") as? NSNumber {
            pillSliderY = min(max(y.doubleValue, 0), height)
        } else {
            pillSliderY = 120
        }
    }

    private func writePillSliderPosition() {
        LyricStore.defaults?.set(pillSliderX, forKey: "hudPill.positionX")
        LyricStore.defaults?.set(pillSliderY, forKey: "hudPill.positionY")
    }

    /// 悬浮歌词文字颜色（0xRRGGBB，写进共享存储，悬浮窗每次刷新时读取）。
    @AppStorage("floatingLyric.textColorHex", store: LyricStore.defaults)
    private var lyricTextColorHex: Int = 0xFFFFFF

    @State private var showSettings = false
    @State private var showAbout = false
    /// 齿轮自绘菜单开关（系统 Menu 宽度由系统写死，改不了；自绘可收窄）。
    @State private var showGearMenu = false

    /// 2.0.1/build 31：HUD 守护进程状态（-check 的实时结果，不是偏好
    /// 设置）。写法复用 SettingsView.swift:167-169／462-479。
    /// Lee 定放主页面：2.0.0 时药丸只能从设置页开，他进不去那个页面，
    /// 所以 Enable 直接放在这里（死开关原位置）。
    /// 2.0.3：状态行已藏掉（开关本身就表示开／关），hudStatusText 与
    /// PID 文件读取随行撤掉；refreshHUDStatus() 只剩更新 hudRunning，
    /// 供下面的 Toggle 绑定读真实状态。
    @State private var hudRunning = false
    @State private var hudCheckGeneration = UUID()
    @State private var hudBusy = false

    /// 2.0.1/build 31：读 HUD 守护进程状态（SettingsView.swift:462 同款：
    /// -check 为准）。2.0.3 起不再读 PID 文件（pid 只在日志里，不显示了）。
    private func refreshHUDStatus() {
        // 2.0.4（兼容补丁并入）：未知环境 fail-closed——门控不通过时
        // 直接报未运行，不调 -check（避免未知环境下误判守护进程状态）。
        let generation = UUID()
        hudCheckGeneration = generation
        guard RuntimeEnvironment.canUseNativeHUD else {
            hudRunning = false
            return
        }
        // 2.0.7（ChatGPT 稳定性并入）：-check 要 spawn 子进程，挪到后台
        // 队列，不堵主线程；代次守卫丢弃过期回调。
        DispatchQueue.global(qos: .utility).async {
            let running = TLDHUDIsEnabled()
            DispatchQueue.main.async {
                guard hudCheckGeneration == generation, !hudBusy else { return }
                hudRunning = running
            }
        }
    }

    /// 2.0.3（Lee 定：一个开关替代两个大按键）：Toggle 绑定直接读
    /// hudRunning（-check 实时结果，不是偏好值）；拨动即调
    /// TLDHUDSetEnabled，走原来按钮那套后台队列＋hudBusy 防连点，
    /// 完事 refreshHUDStatus() 回写真实状态。不用 @AppStorage 存
    /// 开关状态（那就是旧死开关的毛病），也不复用
    /// floatingLyric.enabled 那个死键。
    private var hudEnabledToggle: Binding<Bool> {
        Binding(
            get: { hudRunning },
            set: { newValue in setHUDEnabled(newValue) }
        )
    }

    private func setHUDEnabled(_ enabled: Bool) {
        guard !hudBusy else { return }
        hudBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            TLDHUDLogMessage(enabled ? "main: enable requested"
                                     : "main: disable requested")
            TLDHUDSetEnabled(enabled)
            TLDHUDLogMessage(enabled ? "main: enable done"
                                     : "main: disable done")
            DispatchQueue.main.async {
                hudBusy = false
                refreshHUDStatus()
            }
        }
    }

    /// 从共享存储读回开关值并赋给 @AppStorage，强制刷新开关 UI。
    /// 悬浮窗双击隐藏写入的是另一个 UserDefaults 实例，@AppStorage 不会自动感应。
    private func syncFloatingEnabled() {
        let store = LyricStore.defaults
        let enabled = store?.object(forKey: "floatingLyric.enabled") as? Bool ?? true
        if floatingEnabled != enabled {
            floatingEnabled = enabled
        }
    }

    /// ColorPicker 需要 Color 绑定，这里和 Int 存储值互转。
    private var lyricTextColor: Binding<Color> {
        Binding(
            get: { Color(uiColor: UIColor(tldsHex: lyricTextColorHex)) },
            set: { lyricTextColorHex = $0.tldsHex }
        )
    }

    var body: some View {

        NavigationView {

            ZStack {

                // 共用背景：跟设置页／关于页同一份，随「背景设置」换
                AppBackgroundView()

                VStack(spacing: 22) {

                    // 标题居中，齿轮仍固定在右上角原位
                    ZStack(alignment: .topTrailing) {
                        Text("桌面歌词")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            // 标题和下方内容再整体下移一行
                            .padding(.top, 80)

                        // 独立的菜单子视图：不依赖 coordinator.state，
                        // 播放状态每 0.25s 刷新时菜单不会被重建，避免弹出层闪烁。
                        GearMenu(showMenu: $showGearMenu)
                    }

                    // 播放状态卡片：始终显示。没在放歌时保留卡片并给出提示，
                    // 只有检测到播放器播放时才显示歌词 / 状态。
                    VStack(spacing: 12) {

                        if let state = coordinator.state {

                            // 稳定识别哪一行是歌词：某些播放器会在 title / artist
                            // 之间来回交换「歌手 — 歌名」标识与逐句歌词，只盯着某个
                            // 字段判断会翻转。统一用 LyricStore.lyricLocation（认出
                            // 固定的标识串），保证歌词永远显示在上面的大字位置。
                            let snapshot = LyricStore.load()
                            // 2.0.6：歌卡逐字门复用 LyricMatcher 的字母数字
                            // 归一化——旧闭包只去空格，「你好」和「你 好」
                            // 会被判成两行，逐字门白白关掉。药丸与 LC 应用内
                            // 区没有这道门，不动它们。
                            let normalize: (String) -> String = LyricMatcher.normalize
                            let lyricTexts = Set(
                                snapshot?.lyrics.map { normalize($0.text) } ?? []
                            )
                            let title = state.track.title
                            let secondary = state.track.artist
                            let location = LyricStore.lyricLocation(
                                title: title,
                                artist: secondary,
                                lyricTexts: lyricTexts
                            )
                            let topText = location == .artist ? secondary : title
                            // 2.0.3（Lee 定：直接藏掉，只留歌词）：身份行
                            // bottomText（歌名 · 歌手）不再渲染，卡片只留
                            // 上行歌词＋PLAYING；state.track 原文、
                            // 快照写入、识别都不动。

                            // 2.0.2：歌名／歌手只在显示时按简繁开关转换——
                            // state.track 是 MediaRemote 原文，识别／缓存／
                            // 快照都不动它。
                            // 2.0.4：卡拉OK——卡片大字那行正是当前歌词行时
                            // 逐字亮（字段型播放器把歌词放进 title／artist，
                            // 大字就是歌词行；正常播放器大字是歌名，不逐字，
                            // 原样显示）。TimelineView 每 0.25s 重算已唱位置。
                            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                                if let snapshot,
                                   let pair = LyricStore.currentLyricAndElapsed(snapshot, at: Date()),
                                   LyricStore.isKaraokeEnabled,
                                   let words = pair.line.words, !words.isEmpty,
                                   normalize(pair.line.text) == normalize(topText) {
                                    KaraokeLyricText(line: pair.line, elapsed: pair.elapsed, font: .title2.bold(), baseColor: .white)
                                        .multilineTextAlignment(.center)
                                } else {
                                    Text(LyricStore.convertForDisplay(topText))
                                        .font(.title2.bold())
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.center)
                                }
                            }

                            Text(
                                state.status.rawValue.uppercased()
                            )
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.9))

                            // 2.0.3（Lee 定：进度行藏掉）——进度显示行已删；
                            // 歌卡只剩歌词行＋PLAYING。position 照常更新，
                            // 只是不显示。

                        } else {

                            Text("未检测到播放器播放音乐")
                                .font(.title3.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 60)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)

                    // LiveContainer 宿主：没有悬浮窗／小组件，只在应用内显示歌词，
                    // 0.25s 刷新一次，带暂停／开始与归零。
                    if !RuntimeEnvironment.canUseNativeHUD {
                        Text("兼容环境 · 应用内歌词模式")
                            .foregroundColor(.white)
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            if let snapshot = LyricStore.load() {
                                VStack(spacing: 12) {
                                    Text(snapshot.title).font(.headline)
                                    // 1.0.5（第 2 项＋应用内渲染器）：宿主模式本来就没有悬浮窗，
                                    // 测试开关开时测试文字显示在这里（应用内歌词区），
                                    // 并明确说明这不是悬浮窗；关后恢复正常歌词。
                                    // 2.0.4：卡拉OK——当前歌词行有逐字时间戳时
                                    // 逐字亮（已唱金色、未唱灰色）；测试文字开
                                    // 时不逐字，没有逐字时间戳时退回整行显示。
                                    if !LyricStore.isTestTextEnabled,
                                       let pair = LyricStore.currentLyricAndElapsed(snapshot, at: context.date),
                                       LyricStore.isKaraokeEnabled,
                                       let words = pair.line.words, !words.isEmpty {
                                        KaraokeLyricText(line: pair.line, elapsed: pair.elapsed, font: .title2, baseColor: .white)
                                            .multilineTextAlignment(.center)
                                    } else {
                                        Text(InAppLyricsRenderer.currentDisplayText(at: context.date))
                                            .font(.title2).multilineTextAlignment(.center)
                                    }
                                    Button(snapshot.isPlaying ? "暂停歌词" : "开始歌词") {
                                        var updated = snapshot
                                        updated.elapsedWhenPaused = LyricStore.currentElapsed(snapshot, at: Date())
                                        updated.startedAt = Date()
                                        updated.isPlaying.toggle()
                                        LyricStore.save(updated)
                                    }
                                    Button("歌词归零") {
                                        var updated = snapshot
                                        updated.elapsedWhenPaused = 0
                                        updated.startedAt = Date()
                                        LyricStore.save(updated)
                                    }
                                }.foregroundColor(.white)
                            } else {
                                Text("请在设置中搜索或导入歌词").foregroundColor(.white)
                            }
                        }
                    } else {
                    // 2.0.1：主页面这组旧悬浮窗控件已整组藏掉——它们管的都是
                    // 已死的 FrontBoard 悬浮窗（FloatingLyricViewController，
                    // 唯一消费方；2.0.0 起 TLDSFrontBoardOverlayDisabled = YES
                    // 把整条路关掉，开关开了药丸也不会出来，Lee 2.0.0 真机已踩到）。
                    // 藏掉的三样：「显示悬浮歌词窗」Toggle（floatingLyric.enabled）、
                    // 「固定悬浮窗位置」Toggle（floatingLyric.positionLocked，
                    // 只管同一悬浮窗的拖动，同样已死）、「悬浮窗歌词颜色」
                    // 取色器（floatingLyric.textColorHex，HUD 药丸不读它，
                    // 快照里只有透明度／字号）。只改 UI 呈现：三个存储键本身
                    // 与 @AppStorage 声明、syncFloatingEnabled() 一律不动，
                    // 以免牵连其他逻辑。
                    // 2.0.1/build 31：原位置那句「药丸只从设置页开」的说明
                    // 换成真正能用的 HUD 区段（Lee 定放主页面——设置页
                    // SettingsView 是死页面，他进不去）。调用与文案复用
                    // SettingsView.swift:322 的现成写法，不重写 daemon 逻辑。
                    // LC 模式下只显示禁用说明，绝不调 SetHUDEnabled。
                    VStack(spacing: 12) {
                        // 2.0.3（Lee 定：区段标题藏掉，只留控件）——
                        // 区段标题「悬浮歌词（HUD 守护进程）」已删，开关、
                        // 固定位置、颜色、说明文字、日志入口都原样留着。
                        if !RuntimeEnvironment.canUseNativeHUD {
                            Text("当前环境未确认具备原生 HUD 权限；使用应用内歌词或独立 PiP 测试。")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            // 2.0.3（Lee 定：一个开关替代两个大按键＋状态行
                            // 藏掉）：开关本身就表示开／关。Toggle 出现时刷
                            // 一次真实状态（onAppear）；body 每 0.25s 重建
                            // 不调 -check，那样太贵。
                            Toggle("启用悬浮歌词", isOn: hudEnabledToggle)
                                .foregroundColor(.white)
                                .disabled(hudBusy)
                                .onAppear {
                                    refreshHUDStatus()
                                }

                            // 2.0.2：药丸固定位置（新键 hudPill.positionLocked，
                            // 默认关）＋悬浮歌词颜色（复用旧键
                            // floatingLyric.textColorHex，build 30 只藏了控件，
                            // 键与 lyricTextColor 互转 helper 都还在）。LC 分支
                            // 在上面那个 if 里，这里是非 LC 才进得来。
                            Toggle("固定位置", isOn: $hudPillPositionLocked)
                                .foregroundColor(.white)

                            // 2.0.4：药丸位置滑块——横向／纵向两条，拖滑块
                            // 直接定药丸位置（写 hudPill.positionX／Y，
                            // daemon 每秒 tick 重读应用；拖动中不抢）。
                            // 固定位置开时置灰拖不动；进页面时 onAppear
                            // 读回当前药丸位置。夹取不出屏由 daemon 的
                            // clampedPillCenterForCenter 负责。
                            VStack(spacing: 8) {
                                HStack {
                                    Text("横向")
                                        .foregroundColor(.white)
                                    Slider(value: $pillSliderX, in: 0...Double(UIScreen.main.bounds.width))
                                        .disabled(hudPillPositionLocked)
                                        .onChange(of: pillSliderX) { _ in writePillSliderPosition() }
                                    Text("\(Int(pillSliderX))")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                                HStack {
                                    Text("纵向")
                                        .foregroundColor(.white)
                                    Slider(value: $pillSliderY, in: 0...Double(UIScreen.main.bounds.height))
                                        .disabled(hudPillPositionLocked)
                                        .onChange(of: pillSliderY) { _ in writePillSliderPosition() }
                                    Text("\(Int(pillSliderY))")
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .onAppear {
                                syncPillSliders()
                            }

                            ColorPicker("悬浮歌词颜色", selection: lyricTextColor)
                                .foregroundColor(.white)

                            // 2.0.3（Lee 定：区段说明文字藏掉）——上面那段
                            // 「启用后歌词药丸显示在桌面…」说明文字已删；
                            // 区段只剩开关＋固定位置＋颜色＋日志入口。
                            NavigationLink {
                                HUDLogView()
                            } label: {
                                Label(
                                    "查看守护进程日志",
                                    systemImage: "doc.text"
                                )
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                    }

                    Spacer()
                }
                .padding()

                // 齿轮自绘菜单：放在 ZStack 顶层，遮罩可覆盖整屏。
                // 系统 Menu 宽度由系统定死（实测 219pt），自绘后收窄到 110pt（约一半），
                // 且和 LogView 一样不依赖 UIContextMenuInteraction，播放刷新时不会闪。
                if showGearMenu {
                    ZStack(alignment: .topTrailing) {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                            .onTapGesture { showGearMenu = false }

                        // 图标固定在弹窗左侧（往前面移），文字仍居中；整行可点。
                        VStack(alignment: .center, spacing: 0) {
                            Button {
                                showGearMenu = false
                                showSettings = true
                            } label: {
                                Text("设置")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .overlay(alignment: .leading) {
                                        Image(systemName: "gearshape.fill")
                                            .padding(.leading, 14)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 12)
                            }
                            .foregroundColor(.white)

                            Divider()
                                .background(Color.white.opacity(0.16))

                            Button {
                                showGearMenu = false
                                showAbout = true
                            } label: {
                                Text("关于")
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .overlay(alignment: .leading) {
                                        Image(systemName: "info.circle.fill")
                                            .padding(.leading, 14)
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 12)
                            }
                            .foregroundColor(.white)
                        }
                        // 原系统菜单约 219pt，收窄一半到 110pt，再三次加宽 10% → 146pt
                        .frame(width: 146)
                        .background(Color(red: 0.20, green: 0.20, blue: 0.21))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
                        // 用户要求整体往右移：trailing 56 → 40（右移约 16pt）。
                        .padding(.trailing, 40)
                        .padding(.top, 56)
                    }
                    .zIndex(10)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                NavigationView {
                    ContentView()
                        .environmentObject(coordinator)
                }
            }
            .sheet(isPresented: $showAbout) {
                AboutSheet().equatable()
            }
        }
    }
}

/// 卡拉OK逐字行（2.0.4，药丸与应用内共用同一渲染规矩）。
/// 有逐字时间戳时：已唱的字金色、未唱的字灰色（Lee 定的对比效果图：
/// 「想着温柔的」金色在前、「某某某」灰色在后）；没有逐字时间戳
/// （words 为空）或开关关时，退回整行原样高亮，不会没词显示。
/// 只改显示层：每词按简繁开关逐词转换，快照里的原文不动。
private struct KaraokeLyricText: View {
    let line: LyricLine
    let elapsed: TimeInterval
    let font: Font
    let baseColor: Color

    /// 已唱金色（效果图的琥珀金）；未唱灰色 = 底色 45%（与药丸暗行同档）。
    private static let sungGold = Color(red: 1.0, green: 0.8, blue: 0.1)

    var body: some View {
        if LyricStore.isKaraokeEnabled,
           let words = line.words, !words.isEmpty {
            words.reduce(Text("")) { partial, word in
                partial + Text(LyricStore.convertForDisplay(word.text))
                    .foregroundColor(word.time <= elapsed ? Self.sungGold : baseColor.opacity(0.45))
            }
            .font(font)
        } else {
            Text(LyricStore.convertForDisplay(line.text))
                .font(font)
                .foregroundColor(baseColor)
        }
    }
}

/// 「关于」页单独包一层并标成 Equatable：播放状态每 0.25s 刷新时，父视图的
/// body 会重建；这里让 SwiftUI 跳过 AboutView / LogView 的重建，避免日志页
/// 右上角菜单的弹出层被连带重建而闪烁。
private struct AboutSheet: View, Equatable {
    static func == (lhs: AboutSheet, rhs: AboutSheet) -> Bool { true }

    var body: some View {
        NavigationView {
            AboutView()
        }
    }
}

/// 右上角齿轮按钮。只负责切换 showMenu，真正的弹窗挂在页面顶层 ZStack，
/// 这样宽度可自绘收窄、且遮罩能盖住整屏。独立子视图避免被高频刷新重建。
private struct GearMenu: View {
    @Binding var showMenu: Bool

    var body: some View {
        Button {
            showMenu.toggle()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.35))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 颜色与 0xRRGGBB 互转（取色器 ↔ 悬浮窗共用同一个颜色值）
private extension UIColor {
    convenience init(tldsHex: Int) {
        self.init(
            red: CGFloat((tldsHex >> 16) & 0xFF) / 255,
            green: CGFloat((tldsHex >> 8) & 0xFF) / 255,
            blue: CGFloat(tldsHex & 0xFF) / 255,
            alpha: 1
        )
    }
}

private extension Color {
    /// 把 ColorPicker 选出的颜色转成 0xRRGGBB。
    var tldsHex: Int {
        let uiColor = UIColor(self)
        let rgbSpace = CGColorSpaceCreateDeviceRGB()
        let converted = uiColor.cgColor.converted(
            to: rgbSpace,
            intent: .defaultIntent,
            options: nil
        ) ?? uiColor.cgColor
        guard let components = converted.components, components.count >= 3 else {
            return 0xFFFFFF
        }
        func byte(_ value: CGFloat) -> Int {
            min(255, max(0, Int((value * 255).rounded())))
        }
        return (byte(components[0]) << 16)
            | (byte(components[1]) << 8)
            | byte(components[2])
    }
}

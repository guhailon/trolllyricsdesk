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

    /// 悬浮歌词窗开关（与悬浮控制器共享 App Group 的 floatingLyric.enabled）。
    /// UserDefaults.bool 未设置时返回 false，所以这里显式注册默认值 true。
    @AppStorage("floatingLyric.enabled", store: UserDefaults(suiteName: LyricStore.groupID))
    private var floatingEnabled = true

    /// 悬浮歌词文字颜色（0xRRGGBB，写进 App Group，悬浮窗每次刷新时读取）。
    @AppStorage("floatingLyric.textColorHex", store: UserDefaults(suiteName: LyricStore.groupID))
    private var lyricTextColorHex: Int = 0xFFFFFF

    @State private var showSettings = false
    @State private var showAbout = false
    /// 齿轮自绘菜单开关（系统 Menu 宽度由系统写死，改不了；自绘可收窄）。
    @State private var showGearMenu = false

    /// 从共享存储读回开关值并赋给 @AppStorage，强制刷新开关 UI。
    /// 悬浮窗双击隐藏写入的是另一个 UserDefaults 实例，@AppStorage 不会自动感应。
    private func syncFloatingEnabled() {
        let store = UserDefaults(suiteName: LyricStore.groupID)
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

                // 与原主界面（设置页）一致的渐变背景
                LinearGradient(
                    colors: [
                        Color.purple.opacity(0.8),
                        Color.black,
                        Color.blue.opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 22) {

                    // 左上角标题，右上角设置入口
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("桌面歌词")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.white)
                        }
                        // 标题和下方内容再整体下移一行；齿轮按钮仍固定在右上角原位
                        .padding(.top, 80)

                        Spacer()

                        // 独立的菜单子视图：不依赖 coordinator.state，
                        // 播放状态每 0.25s 刷新时菜单不会被重建，避免弹出层闪烁。
                        GearMenu(showMenu: $showGearMenu)
                    }

                    // 播放状态卡片：始终显示。没在放歌时保留卡片并给出提示，
                    // 只有检测到播放器播放时才显示歌名 / 歌手 / 状态 / 进度。
                    VStack(spacing: 12) {

                        if let state = coordinator.state {

                            // 稳定识别哪一行是歌词：某些播放器会在 title / artist
                            // 之间来回交换「歌手 — 歌名」标识与逐句歌词，只盯着某个
                            // 字段判断会翻转。统一用 LyricStore.lyricLocation（认出
                            // 固定的标识串），保证歌词永远显示在上面的大字位置。
                            let snapshot = LyricStore.load()
                            let normalize: (String) -> String = { text in
                                text.trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: " ", with: "")
                            }
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
                            let bottomText = location == .artist ? title : secondary

                            Text(topText)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text(bottomText)
                                .foregroundColor(.white.opacity(0.75))

                            Text(
                                state.status.rawValue.uppercased()
                            )
                            .font(.caption.bold())
                            .foregroundColor(.white.opacity(0.9))

                            Text(
                                "进度：\(Int(state.position)) 秒"
                            )
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))

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

                    // 操作提示：放在「显示悬浮歌词窗」开关上方
                    Text("悬浮窗口・长按拖动・双击隐藏")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)

                    // 悬浮歌词窗开关（放在「开始检测音乐」按钮上方）
                    Toggle(
                        "显示悬浮歌词窗",
                        isOn: $floatingEnabled
                    )
                    .foregroundColor(.white)
                    .tint(.purple)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                    // 双击悬浮窗隐藏时，通知到达后同步关掉这个开关
                    .onReceive(NotificationCenter.default.publisher(
                        for: LyricStore.floatingEnabledChanged
                    )) { _ in
                        syncFloatingEnabled()
                    }
                    // App 每次回到前台再校准一次（通知错过时的兜底）
                    .onReceive(NotificationCenter.default.publisher(
                        for: UIApplication.didBecomeActiveNotification
                    )) { _ in
                        syncFloatingEnabled()
                    }
                    .onAppear(perform: syncFloatingEnabled)

                    // 悬浮歌词颜色取色器（放在开关下方、「开始检测音乐」按钮上方）
                    HStack {
                        Text("悬浮窗歌词颜色")
                            .foregroundColor(.white)

                        Spacer()

                        ColorPicker("选择悬浮歌词颜色", selection: lyricTextColor)
                            .labelsHidden()
                            .frame(width: 28, height: 28)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)

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

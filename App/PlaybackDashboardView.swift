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
    @AppStorage("floatingLyric.enabled", store: LyricStore.defaults)
    private var floatingEnabled = true

    /// 悬浮窗固定位置开关（与悬浮控制器共享 App Group 的 floatingLyric.positionLocked）。
    /// 默认 false（可拖）；打开后悬浮窗拖不动，位置保持上次存好的地方。
    @AppStorage("floatingLyric.positionLocked", store: LyricStore.defaults)
    private var positionLocked = false

    /// 悬浮歌词文字颜色（0xRRGGBB，写进 App Group，悬浮窗每次刷新时读取）。
    @AppStorage("floatingLyric.textColorHex", store: LyricStore.defaults)
    private var lyricTextColorHex: Int = 0xFFFFFF

    @AppStorage(DualProcessBridge.tokenKey, store: LyricStore.defaults) private var bridgeToken = ""
    @State private var showSettings = false
    @State private var showAbout = false

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

                        Menu {
                            Button {
                                showSettings = true
                            } label: {
                                Label("设置", systemImage: "gearshape.2.fill")
                            }

                            Button {
                                showAbout = true
                            } label: {
                                Label("关于", systemImage: "info.circle.fill")
                            }
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.black.opacity(0.35))
                                .clipShape(Circle())
                        }
                    }

                    if let state = coordinator.state {

                        VStack(spacing: 12) {

                            Text(state.track.title)
                                .font(.title2.bold())
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            Text(state.track.artist)
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
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)
                    }

                    if LyricStore.isLiveContainer {
                        TextField("输入独立版配对码", text: $bridgeToken)
                            .textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
                        Text("LiveContainer · 应用内歌词模式")
                            .foregroundColor(.white)
                        TimelineView(.periodic(from: .now, by: 0.25)) { context in
                            let fresh = context.date.timeIntervalSince1970 - (LyricStore.defaults?.double(forKey: DualProcessBridge.freshnessKey) ?? 0) < 4
                            Text(fresh ? "独立核心已连接" : "未连接核心 · 本地模式").foregroundColor(.white)
                            if let snapshot = LyricStore.load() {
                                VStack(spacing: 12) {
                                    Text(snapshot.title).font(.headline)
                                    Text(LyricStore.currentLyric(snapshot, at: context.date)?.text ?? "等待歌词 / 请到设置导入")
                                        .font(.title2).multilineTextAlignment(.center)
                                    if !fresh {
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
                                    }
                                }.foregroundColor(.white)
                            } else {
                                Text("请在设置中搜索或导入歌词").foregroundColor(.white)
                            }
                        }
                    } else {
                    Button("复制 LiveContainer 配对码") {
                        UIPasteboard.general.string = bridgeToken
                    }.foregroundColor(.white)
                    // 悬浮窗操作提示（原先在悬浮窗卡片底部，现移到主界面；文案跟固定开关走）
                    Text(positionLocked ? "悬浮窗口 · 已固定 · 双击隐藏" : "悬浮窗口 · 长按拖动 · 双击隐藏")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

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

                    // 固定悬浮窗位置（放在显示开关下方；打开后拖不动，位置保持上次存好的地方）
                    Toggle(
                        "固定悬浮窗位置",
                        isOn: $positionLocked
                    )
                    .foregroundColor(.white)
                    .tint(.purple)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)

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

                    }
                    Spacer()
                }
                .padding()
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                NavigationView {
                    ContentView()
                        .environmentObject(coordinator)
                }
            }
            .sheet(isPresented: $showAbout) {
                NavigationView {
                    AboutView()
                }
            }
        }
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

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

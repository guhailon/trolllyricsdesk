import SwiftUI
import WidgetKit

/// 设置中心：从主界面右上角齿轮进入，提供「设置 / 关于」两个入口。
/// 背景与原主界面保持一致。
struct SettingsHubView: View {

    /// 从主界面继承检测引擎，再传给「设置」页的音乐检测按钮。
    @EnvironmentObject private var coordinator: PlaybackCoordinator

    var body: some View {
        ZStack {
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

            VStack(spacing: 24) {

                NavigationLink {
                    ContentView()
                        .environmentObject(coordinator)
                } label: {
                    Label(
                        "设置",
                        systemImage: "gearshape.2.fill"
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                }

                NavigationLink {
                    AboutView()
                } label: {
                    Label(
                        "关于",
                        systemImage: "info.circle.fill"
                    )
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(15)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("设置中心")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ContentView: View {

    /// 音乐检测控制从主界面移到这里，复用 App 级检测引擎。
    @EnvironmentObject private var coordinator: PlaybackCoordinator

    @State private var opacity = 0.65
    @State private var fontSize = 22.0

    /// 悬浮窗背景透明度（与悬浮控制器共享 App Group 的 floatingLyric.cardOpacity）。
    /// 0 = 背景完全透明，只显示歌词；1 = 完全不透明。
    @AppStorage("floatingLyric.cardOpacity", store: UserDefaults(suiteName: LyricStore.groupID))
    private var cardOpacity = 0.55

    var body: some View {

        ZStack {

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

                ScrollView {

                    VStack(spacing: 24) {

                        VStack(spacing: 16) {

                            Text("歌词透明度")
                                .foregroundColor(.white)

                            Slider(
                                value: $opacity,
                                in: 0.1...1.0
                            )

                            Text(
                                "\(Int(opacity * 100))%"
                            )
                            .foregroundColor(.white)

                            Text("歌词字体大小")
                                .foregroundColor(.white)

                            Slider(
                                value: $fontSize,
                                in: 14...36
                            )

                            Text(
                                "\(Int(fontSize)) pt"
                            )
                            .foregroundColor(.white)

                            Text("悬浮窗透明度")
                                .foregroundColor(.white)

                            Slider(
                                value: $cardOpacity,
                                in: 0...1
                            )

                            Text(
                                cardOpacity <= 0.001
                                    ? "完全透明（仅歌词）"
                                    : "\(Int(cardOpacity * 100))%"
                            )
                            .foregroundColor(.white)

                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)

                        VStack(spacing: 12) {
                            Text("音乐检测")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button {
                                coordinator.start()
                            } label: {
                                Label(
                                    "开始检测音乐",
                                    systemImage: "play.fill"
                                )
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(15)
                            }

                            Button {
                                coordinator.stop()
                            } label: {
                                Label(
                                    "停止检测",
                                    systemImage: "stop.fill"
                                )
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.white.opacity(0.14))
                                .foregroundColor(.white)
                                .cornerRadius(15)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)

                        VStack(spacing: 12) {
                            Text("锁屏歌词")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if #available(iOS 16.1, *) {
                                LiveActivitySectionView()
                            } else {
                                Text("锁屏歌词需要 iOS 16.1 或以上")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            Text("锁屏小组件：长按锁屏 → 自定 → 添加小组件 → 选「Troll Lyrics」长方形。")
                                .font(.footnote)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)

                        NavigationLink {
                            LyricsSearchView()
                        } label: {
                            Label(
                                "网易云 / QQ / 本地歌词",
                                systemImage: "music.note.list"
                            )
                            .font(.headline)
                            .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: opacity) { _ in
                saveSettings()
            }
            .onChange(of: fontSize) { _ in
                saveSettings()
            }
    }

    private func saveSettings() {

        guard var snapshot = LyricStore.load() else {
            return
        }

        snapshot.opacity = opacity
        snapshot.fontSize = fontSize

        LyricStore.save(snapshot)

        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// 锁屏歌词开关（路子 A：Live Activities，iOS 16.1+）。
/// 单独抽成子视图，整个包在 @available 里；ContentView 本体保持 MinOS 15.0。
@available(iOS 16.1, *)
private struct LiveActivitySectionView: View {

    @EnvironmentObject private var coordinator: PlaybackCoordinator
    @ObservedObject private var liveActivity = LyricsLiveActivityController.shared

    var body: some View {
        VStack(spacing: 12) {
            Button {
                // 先保证检测引擎在跑（没跑才起，跑着不动），再开锁屏歌词；
                // 不要直接调 coordinator.start()，它会先 stop() 取消搜词任务。
                coordinator.ensureRunning()
                liveActivity.start()
            } label: {
                Label(
                    "开启锁屏歌词",
                    systemImage: "lock.fill"
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(15)
            }
            .disabled(liveActivity.isActive)

            Button {
                liveActivity.stop()
            } label: {
                Label(
                    "停止锁屏歌词",
                    systemImage: "lock.open.fill"
                )
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.white.opacity(0.14))
                .foregroundColor(.white)
                .cornerRadius(15)
            }
            .disabled(!liveActivity.isActive)

            Text(liveActivity.statusMessage)
                .font(.footnote)
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            liveActivity.refresh()
        }
    }
}

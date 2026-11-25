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

    // 后台保活开关（默认关）：开着时用静音音频循环让检测引擎
    // 在后台继续 polling，关着时不播静音音频。存在 App Group。
    @AppStorage("hudKeepAliveEnabled", store: UserDefaults(suiteName: LyricStore.groupID))
    private var keepAliveEnabled = false

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

                            Toggle(isOn: $keepAliveEnabled) {
                                Text("后台保活（静音音频）")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            }
                            .tint(.purple)

                            Text("默认关。开着时退到后台也能继续检测换歌，关着不播静音音频。")
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
            .onAppear {
                applyKeepAlive()
            }
            .onChange(of: opacity) { _ in
                saveSettings()
            }
            .onChange(of: fontSize) { _ in
                saveSettings()
            }
            .onChange(of: keepAliveEnabled) { _ in
                applyKeepAlive()
            }
    }

    // 保活开关的实际动作：开就起静音音频引擎，关就停掉。
    // 只在开关变的时候调；开关默认关，什么都不做。
    private func applyKeepAlive() {
        if keepAliveEnabled {
            BackgroundKeepAlive.shared.start()
        } else {
            BackgroundKeepAlive.shared.stop()
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

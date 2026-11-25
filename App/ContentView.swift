import SwiftUI
import WidgetKit

struct ContentView: View {

    @State private var opacity = 0.65
    @State private var fontSize = 22.0

    // 后台保活开关（1.0.6，默认关）：开着时用静音音频循环让检测引擎
    // 在后台继续 polling，关着时不播静音音频。存在 App Group，
    // 和设置页的 7 个键同一个共享区。
    @AppStorage("hudKeepAliveEnabled", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var keepAliveEnabled = false

    private let demoLyrics = """
    [00:00.00]TrollLyricsDesk
    [00:04.00]透明动漫歌词桌面
    [00:08.00]第一阶段开发测试
    [00:12.00]欢迎使用歌词桌面
    [00:16.00]让音乐与歌词同步
    [00:20.00]TrollStore Edition
    """

    var body: some View {

        NavigationView {

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

                        Text("TrollLyricsDesk")
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)

                        Text("透明动漫歌词桌面")
                            .foregroundColor(.white.opacity(0.7))

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
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(20)

                        Button(action: loadDemo) {

                            Text("加载测试歌词")
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    Color.purple
                                )
                                .cornerRadius(15)
                        }

                        VStack(spacing: 12) {

                            Text("歌词悬浮窗")
                                .foregroundColor(.white)

                            Button(action: startFloatingLyrics) {

                                Text("开启歌词悬浮窗")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        Color.purple
                                    )
                                    .cornerRadius(15)
                            }

                            Button(action: stopFloatingLyrics) {

                                Text("关闭悬浮窗")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        Color.purple
                                    )
                                    .cornerRadius(15)
                            }

                            Button(action: previewFloatingLyrics) {

                                Text("预览悬浮歌词")
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        Color.purple
                                    )
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
                        }

                        NavigationLink {
                            LyricsSearchView()
                        } label: {
                            Label(
                                "歌词搜索与导入",
                                systemImage: "music.note.list"
                            )
                            .font(.headline)
                            .padding()
                        }

                        NavigationLink {
                            PlaybackDashboardView()
                        } label: {
                            Label(
                                "统一音乐播放引擎",
                                systemImage: "waveform"
                            )
                        }

                        NavigationLink {
                            AboutView()
                        } label: {
                            Label(
                                "关于",
                                systemImage: "info.circle"
                            )
                        }

                        Text("请在主屏幕添加 TrollLyrics Widget")
                            .font(.footnote)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding()
                }
            }
            .navigationBarHidden(true)
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

    private func loadDemo() {

        let snapshot = LyricSnapshot(
            title: "TrollLyricsDesk Demo",
            artist: "TrollStore Edition",
            lyrics: LyricParser.parse(demoLyrics),
            startedAt: Date(),
            isPlaying: true,
            elapsedWhenPaused: 0,
            opacity: opacity,
            fontSize: fontSize
        )

        LyricStore.save(snapshot)

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func startFloatingLyrics() {
        TLHelper.startHUD()
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

    private func stopFloatingLyrics() {
        TLHelper.stopHUD()
    }

    private func previewFloatingLyrics() {
        // 没有窗口时不做事：往一个没上屏的兜底 view 里加面板，
        // 面板会被单例卡住、再也点不出来。
        guard let host = TLAppRoot.keyWindowRootView() else {
            return
        }

        FloatingLyricsController.shared.show(in: host)
        FloatingLyricsController.shared.update(
            title: "TrollLyricsDesk",
            previous: "上一句歌词",
            current: "当前正在播放的歌词",
            next: "下一句歌词"
        )
    }
}

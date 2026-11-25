import SwiftUI
import WidgetKit

struct ContentView: View {

    @State private var opacity = 0.65
    @State private var fontSize = 22.0

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
            .onChange(of: opacity) { _ in
                saveSettings()
            }
            .onChange(of: fontSize) { _ in
                saveSettings()
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

import SwiftUI
import WidgetKit
import UIKit

/// 设置中心：从主界面右上角齿轮进入，提供「设置 / 关于」两个入口。
/// 背景与原主界面保持一致。
struct SettingsHubView: View {

    /// 从主界面继承检测引擎，再传给「设置」页的音乐检测按钮。
    @EnvironmentObject private var coordinator: PlaybackCoordinator

    var body: some View {
        ZStack {
            AppBackgroundView()

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

/// 共用 App 背景：读「背景设置」三个键（App Group），随选图实时换。
/// 之前全工程只有 SettingsView 写这三个键、没有任何界面读它们，选了图也换不了背景。
/// - 开关关 → 纯黑（无图无渐变）。
/// - 开且用户选过自定义图 → 全屏显示这张图，不透明度 = 1 − backgroundOpacity
///   （默认 0.25 即图 75% 显示，底下是黑色）。
/// - 开但没选过图 → 原来的紫／黑／蓝渐变（同样套这个不透明度）。
/// 选图后立即生效：loadSelectedPhoto 本来就即时写 selectedBackgroundData，
/// @AppStorage 会实时刷新。MinOS 15.0 兼容（UIImage(data:) 等老 API）。
struct AppBackgroundView: View {

    @AppStorage("animeBackgroundEnabled", store: LyricStore.defaults)
    private var animeBackgroundEnabled = true

    @AppStorage("backgroundOpacity", store: LyricStore.defaults)
    private var backgroundOpacity = 0.25

    @AppStorage("selectedBackgroundData", store: LyricStore.defaults)
    private var selectedBackgroundData = Data()

    var body: some View {
        ZStack {
            Color.black

            if animeBackgroundEnabled {
                if !selectedBackgroundData.isEmpty,
                   let image = UIImage(data: selectedBackgroundData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .opacity(1 - backgroundOpacity)
                } else {
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.8),
                            Color.black,
                            Color.blue.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .opacity(1 - backgroundOpacity)
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ContentView: View {

    /// 音乐检测控制从主界面移到这里，复用 App 级检测引擎。
    @EnvironmentObject private var coordinator: PlaybackCoordinator

    @State private var opacity = 1.0
    @State private var fontSize = 23.0

    /// 悬浮窗背景透明度（与悬浮控制器共享存储 LyricStore.defaults 的 floatingLyric.cardOpacity）。
    /// 0 = 背景完全透明，只显示歌词；1 = 完全不透明。
    @AppStorage("floatingLyric.cardOpacity", store: LyricStore.defaults)
    private var cardOpacity = 0.23

    /// 2.0.2：歌词简繁显示（新键 lyric.displayScript，"Hans" 简体／"Hant" 繁体，
    /// 默认简体）。只转显示层：主页面、应用内歌词区、药丸在渲染时转换；
    /// 快照里的 title／artist／歌词行一律存原文，搜索／缓存／换歌判定／逐歌偏移不动。
    @AppStorage("lyric.displayScript", store: LyricStore.defaults)
    private var displayScript = "Hans"

    /// 2.0.4：卡拉OK模式（新键 lyric.karaokeEnabled，默认开）。
    /// 有逐字时间戳的歌，药丸与应用内当前那句逐字亮（已唱金色、未唱灰色）；
    /// 没有逐字时间戳的歌、或开关关掉，退回整行高亮。只改显示层。
    @AppStorage("lyric.karaokeEnabled", store: LyricStore.defaults)
    private var karaokeEnabled = true

    var body: some View {

        ZStack {

            AppBackgroundView()

                ScrollView {

                    VStack(spacing: 24) {

                        VStack(spacing: 16) {

                            VStack(spacing: 8) {
                                HStack {
                                    Text("歌词透明度")
                                        .foregroundColor(.white)

                                    Spacer()

                                    Text("\(Int(opacity * 100))%")
                                        .foregroundColor(.white)
                                }

                                Slider(
                                    value: $opacity,
                                    in: 0.1...1.0
                                )
                            }

                            VStack(spacing: 8) {
                                HStack {
                                    Text("歌词字体大小")
                                        .foregroundColor(.white)

                                    Spacer()

                                    Text("\(Int(fontSize)) pt")
                                        .foregroundColor(.white)
                                }

                                Slider(
                                    value: $fontSize,
                                    in: 14...36
                                )
                            }

                            VStack(spacing: 8) {
                                HStack {
                                    Text("悬浮窗透明度")
                                        .foregroundColor(.white)

                                    Spacer()

                                    Text(
                                        cardOpacity <= 0.001
                                            ? "完全透明（仅歌词）"
                                            : "\(Int(cardOpacity * 100))%"
                                    )
                                    .foregroundColor(.white)
                                }

                                Slider(
                                    value: $cardOpacity,
                                    in: 0...1
                                )
                            }

                            VStack(spacing: 8) {
                                HStack {
                                    Text("歌词简繁")
                                        .foregroundColor(.white)

                                    Spacer()

                                    Text(displayScript == "Hant" ? "繁体" : "简体")
                                        .foregroundColor(.white)
                                }

                                Picker("歌词简繁", selection: $displayScript) {
                                    Text("简体").tag("Hans")
                                    Text("繁体").tag("Hant")
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(spacing: 8) {
                                Toggle("卡拉OK模式", isOn: $karaokeEnabled)
                                    .foregroundColor(.white)
                                Text("有逐字时间戳的歌词逐字亮（已唱金色、未唱灰色）；没有逐字时间戳的歌仍整行亮。")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

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

        if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }
    }
}

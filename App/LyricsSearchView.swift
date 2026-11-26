import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

/// 传递「音乐平台」行在锚定坐标空间中的实际位置，用于把自绘菜单贴到该行下方。
private struct PlatformRowFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct LyricsSearchView: View {

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""

    @State private var platform: MusicPlatform = .netEase

    @State private var results: [LRCLyricsRecord] = []

    @State private var isSearching = false
    @State private var errorMessage: String?

    @State private var showingImporter = false

    /// 音乐平台自绘菜单开关。系统 Picker（Menu 样式）弹出时用模糊层截取底层，
    /// 底层列表一刷新就重新采样，文字会「一闪一闪」；改用普通视图绘制，不闪烁。
    @State private var showPlatformMenu = false
    /// 「音乐平台」行的实际位置，用于把自绘菜单锚定到该行下方（贴近原 Picker 弹出位置）。
    @State private var platformRowFrame: CGRect = .zero

    @State private var opacity = 0.65
    @State private var fontSize = 22.0

    private let netEase = NetEaseAdapter()
    private let qqMusic = QQMusicAdapter()

    var body: some View {

        ZStack {

        Form {

            Section("歌曲信息") {

                platformRow

                TextField("歌曲名称", text: $title)

                TextField("歌手名称", text: $artist)

                TextField("专辑（可选）", text: $album)
            }

            Section("歌词来源") {

                Button {
                    Task {
                        await searchLyrics()
                    }
                } label: {

                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("在线搜索歌词")

                        Spacer()

                        if isSearching {
                            ProgressView()
                        }
                    }
                }
                .disabled(
                    title.trimmingCharacters(
                        in: .whitespaces
                    ).isEmpty || isSearching
                )

                Button {
                    showingImporter = true
                } label: {

                    Label(
                        "导入本地 LRC 文件",
                        systemImage: "doc.badge.plus"
                    )
                }
            }

            if let errorMessage {

                Section("提示") {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }

            if !results.isEmpty {

                Section("搜索结果") {

                    ForEach(results) { record in

                        VStack(
                            alignment: .leading,
                            spacing: 6
                        ) {

                            Text(record.trackName)
                                .font(.headline)

                            Text(record.artistName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(
                                record.syncedLyrics == nil
                                ? "只有普通歌词或没有歌词"
                                : "已找到同步歌词"
                            )
                            .font(.caption)
                            .foregroundColor(
                                record.syncedLyrics == nil
                                ? .orange
                                : .green
                            )

                            Button("使用这份歌词") {

                                Task {
                                    await selectLyrics(record)
                                }
                            }
                            .disabled(
                                record.syncedLyrics == nil
                                || record.instrumental == true
                            )
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

        }
        .navigationTitle("歌词管理")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                UTType(filenameExtension: "lrc") ?? .plainText,
                .plainText
            ],
            allowsMultipleSelection: false
        ) { result in

            switch result {

            case .success(let urls):

                guard let url = urls.first else {
                    return
                }

                importLocalFile(url)

            case .failure(let error):

                errorMessage = error.localizedDescription
            }
        }

        // 音乐平台自绘菜单：普通视图绘制，不依赖系统菜单的模糊层，
        // 底层表单刷新时不会重新采样，文字不再闪烁。
        // 位置按目标效果：紧贴「音乐平台」行下方、靠右展开，宽约屏宽 63%。
        if showPlatformMenu {
            ZStack {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .onTapGesture { showPlatformMenu = false }

                GeometryReader { geo in
                    let w = geo.size.width * 0.63
                    let h = menuHeight
                    // 上移 2 行：顶部从 170pt → 82pt（每行约 44pt），靠右展开。
                    // 中心 x≈屏宽 0.63（左边缘≈屏宽 0.32、右边缘≈屏宽 0.95）。
                    let cx = geo.size.width * 0.635
                    let cy: CGFloat = 82 + h / 2
                    menuContent
                        .frame(width: w)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 6)
                        .position(x: cx, y: cy)
                }
            }
            .zIndex(10)
        }

        }
    }

    /// 平台菜单高度：4 项 × (12+约20+12) ≈ 176pt。
    private var menuHeight: CGFloat { 176 }

    /// 平台选择菜单内容（普通视图绘制，不闪烁）。
    private var menuContent: some View {
        VStack(spacing: 0) {
            ForEach(MusicPlatform.allCases) { item in
                Button {
                    platform = item
                    showPlatformMenu = false
                } label: {
                    HStack {
                        Text(item.rawValue)
                        Spacer()
                        if item == platform {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .foregroundColor(.primary)

                if item != MusicPlatform.allCases.last {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }

    /// 音乐平台行：显示当前选择，点击弹出自绘菜单。
    private var platformRow: some View {
        Button {
            showPlatformMenu = true
        } label: {
            HStack {
                Text("音乐平台")
                Spacer()
                Text(platform.rawValue)
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .foregroundColor(.primary)
    }

    private func makeTrack() -> MusicTrack {

        switch platform {

        case .netEase:
            return netEase.makeTrack(
                title: title,
                artist: artist,
                album: album
            )

        case .qqMusic:
            return qqMusic.makeTrack(
                title: title,
                artist: artist,
                album: album
            )

        default:
            return MusicTrack(
                title: title,
                artist: artist,
                album: album,
                platform: platform
            )
        }
    }

    @MainActor
    private func searchLyrics() async {

        isSearching = true
        errorMessage = nil
        results = []

        defer {
            isSearching = false
        }

        do {

            let track = makeTrack()

            results = try await LRCLibClient.shared.search(
                track: track
            )

            if results.isEmpty {
                errorMessage = "没有找到相关歌曲"
            }

        } catch {

            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func selectLyrics(
        _ record: LRCLyricsRecord
    ) async {

        guard let lrc = record.syncedLyrics else {
            errorMessage = "该结果没有同步歌词"
            return
        }

        let parsed = LyricParser.parse(lrc)

        guard !parsed.isEmpty else {
            errorMessage = "歌词解析失败"
            return
        }

        let snapshot = LyricSnapshot(
            title: record.trackName,
            artist: record.artistName,
            lyrics: parsed,
            startedAt: Date(),
            isPlaying: true,
            elapsedWhenPaused: 0,
            opacity: opacity,
            fontSize: fontSize
        )

        LyricStore.save(snapshot)

        WidgetCenter.shared.reloadAllTimelines()

        errorMessage = "歌词已保存，可以添加或刷新桌面组件"
    }

    private func importLocalFile(_ url: URL) {

        do {

            let lyrics = try LocalLRCImporter.parse(
                from: url
            )

            let snapshot = LyricSnapshot(
                title: title.isEmpty
                    ? url.deletingPathExtension().lastPathComponent
                    : title,
                artist: artist.isEmpty ? "未知歌手" : artist,
                lyrics: lyrics,
                startedAt: Date(),
                isPlaying: false,
                elapsedWhenPaused: 0,
                opacity: opacity,
                fontSize: fontSize
            )

            LyricStore.save(snapshot)

            WidgetCenter.shared.reloadAllTimelines()

            errorMessage = "本地歌词导入成功"

        } catch {

            errorMessage = error.localizedDescription
        }
    }

}

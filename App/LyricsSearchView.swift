import SwiftUI
import UniformTypeIdentifiers
import WidgetKit

struct LyricsSearchView: View {

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""

    @State private var platform: MusicPlatform = .netEase

    @State private var results: [LRCLyricsRecord] = []

    @State private var isSearching = false
    @State private var errorMessage: String?

    @State private var showingImporter = false

    @State private var opacity = 0.65
    @State private var fontSize = 22.0

    private let netEase = NetEaseAdapter()
    private let qqMusic = QQMusicAdapter()

    var body: some View {

        Form {

            Section("歌曲信息") {

                Picker("音乐平台", selection: $platform) {
                    ForEach(MusicPlatform.allCases) { item in
                        Text(item.rawValue)
                            .tag(item)
                    }
                }

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

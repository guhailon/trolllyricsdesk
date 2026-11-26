import SwiftUI
import WidgetKit
import UIKit

// MARK: - iOS 15 兼容层：替代 iOS 16 的 PhotosPicker
// 系统 PhotosPicker / PhotosPickerItem / loadTransferable 都是 iOS 16+ API，
// iOS 15 上调用会因 unrecognized selector 直接闪退。
// 这里用 UIKit 的 UIImagePickerController（iOS 2+）实现相同能力，
// 并保持 SettingsView 里原有的调用形式不变（PhotosPicker / PhotosPickerItem /
// loadTransferable），避免改动 Lee 的业务代码。

struct PhotosPickerItem: Equatable {
    let id = UUID()
    let image: UIImage?

    init(image: UIImage?) {
        self.image = image
    }

    static func == (lhs: PhotosPickerItem, rhs: PhotosPickerItem) -> Bool {
        lhs.id == rhs.id
    }

    func loadTransferable(type: Data.Type) async throws -> Data? {
        image?.jpegData(compressionQuality: 1.0)
    }
}

struct PhotosPickerFilter {
    static let images = PhotosPickerFilter()
}

struct PhotosPicker<Label: View>: View {
    @Binding var selection: PhotosPickerItem?
    let matching: PhotosPickerFilter
    let label: Label
    @State private var showPicker = false

    init(
        selection: Binding<PhotosPickerItem?>,
        matching: PhotosPickerFilter = PhotosPickerFilter(),
        @ViewBuilder label: () -> Label
    ) {
        self._selection = selection
        self.matching = matching
        self.label = label()
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            label
        }
        .sheet(isPresented: $showPicker) {
            ImagePickerSheet(
                isPresented: $showPicker,
                selection: $selection
            )
        }
    }
}

private struct ImagePickerSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @Binding var selection: PhotosPickerItem?

    func makeUIViewController(
        context: Context
    ) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .photoLibrary
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ controller: UIImagePickerController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPresented: $isPresented,
            selection: $selection
        )
    }

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {

        let isPresented: Binding<Bool>
        let selection: Binding<PhotosPickerItem?>

        init(
            isPresented: Binding<Bool>,
            selection: Binding<PhotosPickerItem?>
        ) {
            self.isPresented = isPresented
            self.selection = selection
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            selection.wrappedValue = PhotosPickerItem(image: image)
            isPresented.wrappedValue = false
        }

        func imagePickerControllerDidCancel(
            _ picker: UIImagePickerController
        ) {
            isPresented.wrappedValue = false
        }
    }
}

struct SettingsView: View {

    @AppStorage("lyricsFontSize", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var lyricsFontSize: Double = 22

    @AppStorage("lyricsOpacity", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var lyricsOpacity: Double = 1.0

    @AppStorage("backgroundOpacity", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var backgroundOpacity: Double = 0.25

    @AppStorage("lyricsDisplayMode", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var lyricsDisplayMode: String = "highlight"

    @AppStorage("showNextLine", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var showNextLine: Bool = true

    // 歌词时间偏移（秒，逐歌）：正值提前显示，负值延后。
    // 每首歌的 LRC 时间轴偏差不同，这里按当前播放歌曲单独存，互不干扰。
    @State private var lyricTimeOffset: Double = 0

    /// 当前正在播放（最近快照里）的歌曲，作为偏移量的归属。
    /// SettingsView 没有注入 coordinator，统一从共享快照读取。
    private var currentSong: (title: String, artist: String) {
        if let snapshot = LyricStore.load() {
            return (snapshot.title, snapshot.artist)
        }
        return ("", "")
    }

    @AppStorage("animeBackgroundEnabled", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var animeBackgroundEnabled: Bool = true

    @AppStorage("selectedBackgroundData", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var selectedBackgroundData: Data = Data()

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var backgroundImage: UIImage?

    var body: some View {
        NavigationView {
            Form {

                // 歌词外观
                Section(header: Text("歌词外观")) {

                    VStack(alignment: .leading) {
                        HStack {
                            Text("字体大小")
                            Spacer()
                            Text("\(Int(lyricsFontSize)) pt")
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: $lyricsFontSize,
                            in: 14...36,
                            step: 1
                        )
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("歌词透明度")
                            Spacer()
                            Text("\(Int(lyricsOpacity * 100))%")
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: $lyricsOpacity,
                            in: 0.1...1.0
                        )
                    }

                    Toggle(
                        "显示下一句歌词",
                        isOn: $showNextLine
                    )
                }

                // 歌词同步
                Section(header: Text("歌词同步")) {

                    Picker(
                        "显示模式",
                        selection: $lyricsDisplayMode
                    ) {
                        Text("逐句高亮")
                            .tag("highlight")

                        Text("逐字卡拉OK")
                            .tag("karaoke")
                    }
                    .pickerStyle(.menu)

                    VStack(alignment: .leading) {
                        HStack {
                            Text("歌词时间偏移")
                            Spacer()
                            Text(String(format: "%+.1f 秒", lyricTimeOffset))
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: $lyricTimeOffset,
                            in: -3.0...3.0,
                            step: 0.1
                        )
                        .onAppear {
                            let song = currentSong
                            lyricTimeOffset = LyricStore.timeOffset(
                                title: song.title, artist: song.artist
                            )
                        }
                        // 拖动结束后按当前歌保存，并只刷新一次 Widget
                        .onChange(of: lyricTimeOffset) { newValue in
                            let song = currentSong
                            LyricStore.setTimeOffset(
                                newValue, title: song.title, artist: song.artist
                            )
                            if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }
                        }
                        Text("只对当前歌曲生效：\(currentSong.title)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("歌词总是慢半拍就往右调（提前），太快就往左调。每首歌独立记忆。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // 背景设置
                Section(header: Text("背景设置")) {

                    Toggle(
                        "启用动漫背景",
                        isOn: $animeBackgroundEnabled
                    )

                    VStack(alignment: .leading) {
                        HStack {
                            Text("背景透明度")
                            Spacer()
                            Text("\(Int(backgroundOpacity * 100))%")
                                .foregroundColor(.secondary)
                        }

                        Slider(
                            value: $backgroundOpacity,
                            in: 0...1
                        )
                    }

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images
                    ) {
                        Label(
                            "选择背景图片",
                            systemImage: "photo"
                        )
                    }

                    if let image = backgroundImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .clipped()
                            .cornerRadius(12)
                    }
                }

                // 保存设置
                Section {
                    Button {
                        saveSettings()
                    } label: {
                        HStack {
                            Spacer()
                            Text("保存设置")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                }

                // 关于
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Text("关于")
                    }
                }
            }
            .navigationTitle("设置")
            .onChange(of: selectedPhoto) { newValue in
                Task {
                    await loadSelectedPhoto(newValue)
                }
            }
            .onAppear {
                loadSavedBackground()
            }
        }
    }

    // MARK: - 保存设置

    private func saveSettings() {
        if let image = backgroundImage,
           let data = image.jpegData(compressionQuality: 0.8) {
            selectedBackgroundData = data
        }

        if !LyricStore.isLiveContainer { WidgetCenter.shared.reloadAllTimelines() }
    }

    // MARK: - 读取图片

    private func loadSelectedPhoto(
        _ item: PhotosPickerItem?
    ) async {

        guard let item = item else {
            return
        }

        do {
            if let data = try await item.loadTransferable(
                type: Data.self
            ) {
                await MainActor.run {
                    selectedBackgroundData = data
                    backgroundImage = UIImage(data: data)
                }
            }
        } catch {
            print("图片读取失败：\(error)")
        }
    }

    // MARK: - 读取已保存图片

    private func loadSavedBackground() {
        guard !selectedBackgroundData.isEmpty else {
            return
        }

        backgroundImage = UIImage(
            data: selectedBackgroundData
        )
    }
}

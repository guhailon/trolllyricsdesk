import SwiftUI
import WidgetKit
import PhotosUI

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

    @AppStorage("animeBackgroundEnabled", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var animeBackgroundEnabled: Bool = true

    @AppStorage("selectedBackgroundData", store: UserDefaults(suiteName: "group.com.hailong.TrollLyricsDesk"))
    private var selectedBackgroundData: Data = Data()

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

                    // 选背景图是 iOS 16+ 的 PhotosPicker：包在独立子视图里，
                    // iOS 15 上这一行不显示，其余设置不受影响。
                    // （1.0.6：最低系统降到 15.0 的适配，功能本身没变。）
                    if #available(iOS 16, *) {
                        BackgroundPhotoPickerRow(
                            backgroundImage: $backgroundImage
                        ) { data in
                            selectedBackgroundData = data
                        }
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

        WidgetCenter.shared.reloadAllTimelines()
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

// MARK: - 背景图片选择（iOS 16+）
// PhotosPicker / PhotosPickerItem 是 iOS 16 才有的 API：整个选图行
// 连同 @State 一起包在这个子视图里，视图本身标 @available(iOS 16, *)，
// iOS 15 上父视图根本不引用这些类型，编得过。iOS 16+ 上行为和原来
// 一样：选图 -> 读 Data -> 回写 App Group + 预览。
// （1.0.6：最低系统降到 15.0 的适配；Lee 原文件里这部分逻辑原样搬过来。）
@available(iOS 16, *)
private struct BackgroundPhotoPickerRow: View {

    @Binding var backgroundImage: UIImage?
    var onPicked: (Data) -> Void

    @State private var selectedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading) {
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
        .onChange(of: selectedPhoto) { newValue in
            Task {
                await loadSelectedPhoto(newValue)
            }
        }
    }

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
                    onPicked(data)
                    backgroundImage = UIImage(data: data)
                }
            }
        } catch {
            print("图片读取失败：\(error)")
        }
    }
}

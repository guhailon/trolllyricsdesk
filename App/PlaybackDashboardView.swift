import SwiftUI
import MediaPlayer

struct PlaybackDashboardView: View {

    @StateObject private var coordinator =
        PlaybackCoordinator(
            adapter: MediaRemoteAdapter()
        )

    var body: some View {

        NavigationView {

            VStack(spacing: 24) {

                Image(systemName: "waveform")
                    .font(.system(size: 55))
                    .foregroundColor(.purple)

                Text("TrollLyricsDesk")
                    .font(.largeTitle.bold())

                Text(coordinator.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                if let state = coordinator.state {

                    VStack(spacing: 12) {

                        Text(state.track.title)
                            .font(.title2.bold())

                        Text(state.track.artist)
                            .foregroundColor(.secondary)

                        Text(
                            state.status.rawValue.uppercased()
                        )
                        .font(.caption.bold())
                        .foregroundColor(.purple)

                        Text(
                            "进度：\(Int(state.position)) 秒"
                        )
                        .font(.caption)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .cornerRadius(20)
                }

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
                    .background(Color.gray.opacity(0.2))
                    .foregroundColor(.primary)
                    .cornerRadius(15)
                }

                NavigationLink {
                    LyricsSearchView()
                } label: {

                    Label(
                        "网易云 / QQ / 本地歌词",
                        systemImage: "music.note.list"
                    )
                }

                Spacer()
            }
            .padding()
            .navigationTitle("播放状态")
        }
        .onAppear {
            coordinator.start()
        }
        .onDisappear {
            coordinator.stop()
        }
    }
}

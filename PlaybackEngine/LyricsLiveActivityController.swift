import ActivityKit
import Foundation
import Combine

// MARK: - 锁屏歌词控制器（路子 A：灵动岛 Live Activities）
// 单例，仿 BackgroundKeepAlive.shared 的持有方式；@Published 状态供
// ContentView 的「锁屏歌词」区绑定。
// 整体 @available(iOS 16.1, *)；iOS 15 上不存在这个类，调用点用
// if #available(iOS 16.1, *) 包起来。零新增 entitlements，不走推送。

@available(iOS 16.1, *)
@MainActor
final class LyricsLiveActivityController: ObservableObject {

    static let shared = LyricsLiveActivityController()

    @Published private(set) var isActive = false
    @Published private(set) var statusMessage = "未开启"

    private var activity: Activity<LyricsLiveAttributes>?

    private init() {
        refresh()
    }

    /// 回到设置页时同步一次：用户在锁屏上滑掉横幅后，开关状态要跟着变，
    /// 不要出现「横幅没了开关还亮着」。
    func refresh() {
        if let current = Activity<LyricsLiveAttributes>.activities.first {
            activity = current
            isActive = true
            statusMessage = "锁屏歌词已开启"
        } else {
            activity = nil
            isActive = false
            statusMessage = "未开启"
        }
    }

    /// 点「开启锁屏歌词」（App 在前台）：开一个本地 Live Activity。
    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            statusMessage = "系统不允许 Live Activity（请在设置里允许）"
            return
        }

        if activity != nil {
            isActive = true
            statusMessage = "锁屏歌词已开启"
            return
        }

        do {
            activity = try Activity.request(
                attributes: LyricsLiveAttributes(),
                content: ActivityContent(
                    state: placeholderState(),
                    staleDate: nil
                ),
                pushType: nil
            )
            isActive = true
            statusMessage = "锁屏歌词已开启"
            observeEnd()
        } catch {
            statusMessage = "开启失败：\(error.localizedDescription)"
        }
    }

    /// 点「停止锁屏歌词」：立即消失，不留残影。
    func stop() {
        guard let current = activity else {
            isActive = false
            statusMessage = "未开启"
            return
        }

        Task {
            await current.end(
                ActivityContent(state: placeholderState(), staleDate: nil),
                dismissalPolicy: .immediate
            )
            activity = nil
            isActive = false
            statusMessage = "未开启"
        }
    }

    /// 检测引擎每轮 poll 里「变行才推」的落点；没开 Activity 时直接跳过。
    func update(
        state: LyricsLiveAttributes.ContentState,
        staleDate: Date?
    ) async {
        guard let current = activity else {
            return
        }
        await current.update(
            ActivityContent(state: state, staleDate: staleDate)
        )
    }

    /// 歌词颜色 0xRRGGBB：复用 Overlay 取色器键，默认白。
    static func lyricColorHex() -> Int {
        if let value = UserDefaults(suiteName: LyricStore.groupID)?
            .object(forKey: "floatingLyric.textColorHex") as? Int {
            return value
        }
        return 0xFFFFFF
    }

    /// 还没歌词时的占位 state（开 Activity 那一下／停止时用）。
    private func placeholderState() -> LyricsLiveAttributes.ContentState {
        LyricsLiveAttributes.ContentState(
            title: "桌面歌词",
            artist: "",
            previous: "",
            current: "♪ 等待歌词...",
            next: "",
            isPlaying: false,
            lyricColorHex: Self.lyricColorHex()
        )
    }

    /// 监听 Activity 结束（用户在锁屏上滑掉横幅／8 小时到期），
    /// 开关状态同步回来。
    private func observeEnd() {
        guard let current = activity else {
            return
        }
        Task {
            for await state in current.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    await MainActor.run {
                        self.activity = nil
                        self.isActive = false
                        self.statusMessage = "未开启"
                    }
                    break
                }
            }
        }
    }
}

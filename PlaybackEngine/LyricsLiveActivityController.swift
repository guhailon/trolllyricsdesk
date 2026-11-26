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

    /// 当前 Activity 的 id：协调器去重用——Activity 换实例（重开／到期重建）
    /// 时强制重推，不等切词。
    var activityID: String? { activity?.id }

    /// 更新串行化：只保留最新一次 update 的状态，旧的合并掉（BUG-06）。
    private var pendingUpdate: (state: LyricsLiveAttributes.ContentState, staleDate: Date?)?
    private var updateTask: Task<Void, Never>?

    /// 结束监听任务：恢复已有 Activity 时重新绑定，旧的取消（问题 A/B）。
    private var observationTask: Task<Void, Never>?

    /// 开启／停止进行中：防重复点按钮，两个任务互相覆盖（问题 C）。
    private var isBusy = false

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
            // 恢复后重新绑定结束监听（问题 A），不然 App 重启后滑掉横幅
            // 开关还亮着；observeEnd 内部会先取消旧监听任务。
            observeEnd()
        } else {
            activity = nil
            isActive = false
            statusMessage = "未开启"
        }
    }

    /// 点「开启锁屏歌词」（App 在前台）：开一个本地 Live Activity。
    func start() {
        // 停止进行中时不许重开（问题 C）。
        guard !isBusy else { return }
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
            // 问题 2：16.2 的 request 用 ActivityContent，16.1 用 contentState；
            // 保留 16.1 支持，不抬高整个 App 的最低系统。
            if #available(iOS 16.2, *) {
                activity = try Activity.request(
                    attributes: LyricsLiveAttributes(),
                    content: ActivityContent(
                        state: placeholderState(),
                        staleDate: nil
                    ),
                    pushType: nil
                )
            } else {
                activity = try Activity.request(
                    attributes: LyricsLiveAttributes(),
                    contentState: placeholderState(),
                    pushType: nil
                )
            }
            isActive = true
            statusMessage = "锁屏歌词已开启"
            observeEnd()
        } catch {
            statusMessage = "开启失败：\(error.localizedDescription)"
        }
    }

    /// 点「停止锁屏歌词」：立即消失，不留残影。
    func stop() {
        guard !isBusy else { return }
        guard let current = activity else {
            isActive = false
            statusMessage = "未开启"
            return
        }

        // 必须等 end() 返回才改开关状态（问题 C），不然重复点会互相覆盖。
        isBusy = true
        Task {
            if #available(iOS 16.2, *) {
                await current.end(
                    ActivityContent(state: placeholderState(), staleDate: nil),
                    dismissalPolicy: .immediate
                )
            } else {
                await current.end(
                    using: placeholderState(),
                    dismissalPolicy: .immediate
                )
            }
            activity = nil
            isActive = false
            statusMessage = "未开启"
            isBusy = false
        }
    }

    /// 检测引擎每轮 poll 里「变行才推」的落点；没开 Activity 时直接跳过。
    /// BUG-06：串行合并队列——发的时候只发最新状态，旧的合并掉；
    /// 发之前校验 Activity id，旧 Activity 的更新不许落在新 Activity 上。
    func update(
        state: LyricsLiveAttributes.ContentState,
        staleDate: Date?
    ) async {
        guard activity != nil else {
            return
        }
        pendingUpdate = (state: state, staleDate: staleDate)
        guard updateTask == nil else {
            // 已有一轮在发，它结束时会取最新的 pendingUpdate。
            return
        }
        updateTask = Task {
            while let pending = self.pendingUpdate {
                self.pendingUpdate = nil
                guard let current = self.activity else {
                    break
                }
                let id = current.id
                if #available(iOS 16.2, *) {
                    await current.update(
                        ActivityContent(state: pending.state, staleDate: pending.staleDate)
                    )
                } else {
                    // iOS 16.1 的 update 没有 staleDate 参数，过期标记用不上。
                    await current.update(using: pending.state)
                }
                guard self.activity?.id == id else {
                    break
                }
            }
            self.updateTask = nil
        }
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
    /// 开关状态同步回来。监听任务存成属性，恢复／重开时先取消旧的；
    /// 回调先校验 id，旧 Activity 的结束不许清掉新 Activity（问题 B）。
    private func observeEnd() {
        guard let current = activity else {
            return
        }
        observationTask?.cancel()
        observationTask = Task {
            let id = current.id
            for await state in current.activityStateUpdates {
                if state == .ended || state == .dismissed {
                    await MainActor.run {
                        guard self.activity?.id == id else { return }
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

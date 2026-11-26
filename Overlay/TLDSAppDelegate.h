#import <UIKit/UIKit.h>

@interface TLDSAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

/// 悬浮场景标识（FBScene / UISceneSession 的 persistentIdentifier）
@property (nonatomic, copy) NSString *floatingSceneIdentifier;

/// 场景展示绑定器：必须强引用，否则场景会被释放
@property (nonatomic, strong) id floatingBinder;

/// 悬浮场景 / 窗口：锁屏解锁后需要重新激活，必须强引用
@property (nonatomic, strong) id floatingScene;
@property (nonatomic, strong) UIWindow *floatingWindow;

/// 运行状态
@property (nonatomic, assign) BOOL shellInitialized;
@property (nonatomic, assign) BOOL mainSceneConnected;
@property (nonatomic, assign) BOOL floatingSceneCreated;
/// 是否已经建过悬浮场景（防止首次启动时误触发重建）
@property (nonatomic, assign) BOOL floatingSceneEverCreated;

/// 可见性自检定时器（锁屏/后台回来后兜底恢复悬浮窗）
@property (nonatomic, strong) NSTimer *visibilityWatchdog;
/// 重建 / 日志节流时间戳（CFAbsoluteTime）
@property (nonatomic, assign) double lastRebuildTime;
@property (nonatomic, assign) double lastRestoreLogTime;
/// 重建时的场景序号（用新标识避免与残留旧场景冲突）
@property (nonatomic, assign) NSInteger floatingSceneSeq;
/// 经历过锁屏：解锁后必须完整重建（sceneDidDisconnect 未必触发，不能只靠状态位）
@property (nonatomic, assign) BOOL needsRebuildOnUnlock;

/// 1.0.5 三档模式：普通签名兼容模式已判定（悬浮窗复核未通过）。
/// 为 YES 时：不再创建／重建／恢复悬浮窗，SceneDelegate 把悬浮会话当主界面处理，
/// 只走应用内歌词。巨魔模式与增强宿主模式下恒为 NO。
@property (nonatomic, assign) BOOL compatMode;

/// 1.0.5：托管复核是否已下结论（增强宿主／普通签名二选一）。
/// 未结论前是「待探测」，悬浮场景照常尝试连接，等复核结果。
@property (nonatomic, assign) BOOL modeDecided;

/// 1.0.5：托管复核已跑次数（第 1 次 2 秒后，第 2 次 5 秒后，只为等场景连上）。
@property (nonatomic, assign) NSInteger verifyAttempts;

/// 1.0.5：兼容模式下「跳过重建」只记一次，避免 2 秒看门狗每轮刷屏。
@property (nonatomic, assign) BOOL compatSkipLogged;

/// 锁屏解锁后重新激活悬浮窗（通知回调里调用）
- (void)reactivateFloatingOverlay;

/// 完整重建悬浮场景（丢弃旧 scene / binder / window，走首启同款创建路径）
- (void)rebuildFloatingOverlay;

/// 1.0.5 托管复核（第 3／4 项＋三档判定）：悬浮窗创建后延迟检查窗口是否真在
/// 层级里、Context ID 是否有效、binder 是否真收录了场景；结论记成
/// 「已确认可见／未确认可见＋原因」，不要只记「创建成功」。
- (void)verifyFloatingVisibility;

/// 1.0.5：复核未通过 → 降级普通签名兼容模式：摘掉场景、隐藏窗口、
/// 不再重建，只走应用内歌词（reasons 是复核逐项失败原因）。
- (void)downgradeToCompatModeWithReasons:(NSArray<NSString *> *)reasons;

/// 日志（写入 LyricLogger，便于在 App 内"关于 → 日志"查看）
- (void)log:(NSString *)message;

@end

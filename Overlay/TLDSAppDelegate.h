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

/// 1.0.6/build 21：当前悬浮场景是否曾经完成连接（willConnectToSession 已跑过）。
/// floatingSceneCreated 只表示「当前连着」，断开后也会变 NO；
/// 这个位只在创建新场景时清 NO、连上后置 YES——用来区分
/// 「建了还没连上（连接窗口，绝不能销毁／重建）」和
/// 「连上过、后来断开（可以销毁重建）」。
@property (nonatomic, assign) BOOL floatingSceneEverConnected;

/// 可见性自检定时器（锁屏/后台回来后兜底恢复悬浮窗）
@property (nonatomic, strong) NSTimer *visibilityWatchdog;
/// 重建 / 日志节流时间戳（CFAbsoluteTime）
@property (nonatomic, assign) double lastRebuildTime;
@property (nonatomic, assign) double lastRestoreLogTime;
/// 1.0.6/build 21：「场景连接中，跳过恢复」日志的节流时间戳（CFAbsoluteTime）。
@property (nonatomic, assign) double lastConnectingSkipLogTime;
/// 重建时的场景序号（用新标识避免与残留旧场景冲突）
@property (nonatomic, assign) NSInteger floatingSceneSeq;
/// 经历过锁屏：解锁后必须完整重建（sceneDidDisconnect 未必触发，不能只靠状态位）
@property (nonatomic, assign) BOOL needsRebuildOnUnlock;

/// 1.0.6 三项判定分离：安装环境（trollstore／livecontainer／signature／unknown）
/// 启动时凭正面证据定一次，之后永不改写；托管复核只定显示能力，
/// 禁止它改安装环境。普通签名兼容模式下恒为 YES 时：不再创建／重建／恢复悬浮窗，
/// SceneDelegate 把悬浮会话当主界面处理，只走应用内歌词。
/// 巨魔模式与增强宿主模式下恒为 NO。
@property (nonatomic, assign) BOOL compatMode;

/// 1.0.6：托管复核是否已下结论（增强宿主／普通签名二选一，或未确认环境的显示能力）。
/// 未结论前是「待探测」，悬浮场景照常尝试连接，等复核结果。
/// 巨魔原生与普通签名在启动时直接定档（modeDecided=YES），不复核。
@property (nonatomic, assign) BOOL modeDecided;

/// 1.0.6：托管复核是否排期——只在 LiveContainer 宿主与未确认环境分支为 YES。
/// 巨魔原生／普通签名不排复核（复核只在宿主分支排，第 2 项）。
@property (nonatomic, assign) BOOL shouldVerify;

/// 1.0.6（第 7 项）：激活前悬浮窗状态快照是否已记过（每进程只记一次）。
@property (nonatomic, assign) BOOL activationPreStateLogged;

/// 锁屏解锁后重新激活悬浮窗（通知回调里调用）
- (void)reactivateFloatingOverlay;

/// 1.0.6（第 7 项）：带触发来源的恢复（2 秒看门狗／回到前台／未知），
/// 日志里写清触发、窗口状态、激活状态与安装环境。
- (void)reactivateFloatingOverlayWithTrigger:(NSString *)trigger;

/// 完整重建悬浮场景（丢弃旧 scene / binder / window，走首启同款创建路径）
- (void)rebuildFloatingOverlay;

/// 1.0.6（第 7 项）：记一次悬浮窗当前状态（窗口在不在、isHidden、windowScene、frame），
/// tag 是「激活前」／「激活成功后」。激活成功不应丢窗，两次快照对得上才算。
- (void)logFloatingWindowStateWithTag:(NSString *)tag;

/// 1.0.6（第 6／7 项跟进）：记当前活着的悬浮场景数与各自标识
/// （openSessions 里 TLDSFloatingLyric 前缀的会话），重建前后各记一次，
/// 旧窗只隐藏不销毁、留两个窗的情况不再看不见。
- (void)logLiveFloatingScenesWithTag:(NSString *)tag;

/// 1.0.5：托管复核已跑次数（第 1 次 2 秒后，第 2 次 5 秒后，只为等场景连上）。
@property (nonatomic, assign) NSInteger verifyAttempts;

/// 1.0.5：兼容模式下「跳过重建」只记一次，避免 2 秒看门狗每轮刷屏。
@property (nonatomic, assign) BOOL compatSkipLogged;

/// 锁屏解锁后重新激活悬浮窗（通知回调里调用）
- (void)reactivateFloatingOverlay;

/// 完整重建悬浮场景（丢弃旧 scene / binder / window，走首启同款创建路径）
- (void)rebuildFloatingOverlay;

/// 1.0.6 托管复核（第 2／6 项＋第 6 项的写法）：悬浮窗创建后延迟检查窗口是否真在
/// 层级里、Context ID 是否有效、binder 是否真收录了场景；结论只定显示能力，
/// 永不改安装环境。结论行写清三段——托管结构检查：通过／失败、
/// Context ID：有效／未知／无效、实际屏幕可见性：未确认／待确认；
/// 不再用一句「已确认可见」盖过去（binder／窗口／windowScene 只能证明
/// 托管结构通过，不能证明系统真把窗口合成到屏幕上了）。
- (void)verifyFloatingVisibility;

/// 1.0.5：复核未通过 → 降级普通签名兼容模式：摘掉场景、隐藏窗口、
/// 不再重建，只走应用内歌词（reasons 是复核逐项失败原因）。
- (void)downgradeToCompatModeWithReasons:(NSArray<NSString *> *)reasons;

/// 日志（写入 LyricLogger，便于在 App 内"关于 → 日志"查看）
- (void)log:(NSString *)message;

@end

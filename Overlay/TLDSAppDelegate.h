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

/// 锁屏解锁后重新激活悬浮窗（通知回调里调用）
- (void)reactivateFloatingOverlay;

/// 完整重建悬浮场景（丢弃旧 scene / binder / window，走首启同款创建路径）
- (void)rebuildFloatingOverlay;

/// 日志（写入 LyricLogger，便于在 App 内"关于 → 日志"查看）
- (void)log:(NSString *)message;

@end

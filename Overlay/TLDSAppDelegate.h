#import <UIKit/UIKit.h>

@interface TLDSAppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong) UIWindow *window;

/// 悬浮场景标识（FBScene / UISceneSession 的 persistentIdentifier）
@property (nonatomic, copy) NSString *floatingSceneIdentifier;

/// 场景展示绑定器：必须强引用，否则场景会被释放
@property (nonatomic, strong) id floatingBinder;

/// 运行状态
@property (nonatomic, assign) BOOL shellInitialized;
@property (nonatomic, assign) BOOL mainSceneConnected;
@property (nonatomic, assign) BOOL floatingSceneCreated;

/// 日志（写入 LyricLogger，便于在 App 内"关于 → 日志"查看）
- (void)log:(NSString *)message;

@end

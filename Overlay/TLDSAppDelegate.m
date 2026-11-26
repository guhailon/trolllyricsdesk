#import "TLDSAppDelegate.h"
#import "TLDSSceneDelegate.h"
#import "Private/UIKitPrivate.h"
#import "TrollLyricsDesk-Swift.h"

// ============================================================
// 黑屏修复（关键）
// UIRootWindowScenePresentationBinder 内部会创建 UIRootSceneWindow
// 承载 FBScene 画面，默认不透明黑底且盖在场景窗口之上。
// 用 category 强制透明 + 高 windowLevel，避免打开 App 全黑。
// ============================================================
#ifndef TLDS_LIVE_CONTAINER
@interface UIRootSceneWindow : UIWindow
@end

@implementation UIRootSceneWindow (TLDSHook)

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.backgroundColor = UIColor.clearColor.CGColor;
}

- (CGFloat)windowLevel {
    return 10000;
}

@end

#endif

@implementation TLDSAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.floatingSceneIdentifier = @"TLDSFloatingLyric";

    // 启动 Swift 播放检测引擎（自动跟随所有播放器）
    [[TLDSRuntime shared] start];
    [self log:@"App 启动：自动跟随已开启"];

    // 注册系统级 Shell + 创建全局悬浮歌词场景
    #ifndef TLDS_LIVE_CONTAINER
    [self startFloatingOverlay];
#endif

    return YES;
}

#ifndef TLDS_LIVE_CONTAINER
- (void)startFloatingOverlay {
    if (self.shellInitialized) {
        return;
    }
    self.shellInitialized = YES;

    __weak TLDSAppDelegate *weakSelf = self;
    [self log:@"注册系统 Shell..."];

    // 把本进程注册为系统级 Shell，成功后创建的 FBScene
    // 才能成为"压在其他 App / 桌面之上"的前台场景。
    FBSystemShellInitialize(^(id arg) {
        __strong TLDSAppDelegate *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf log:@"系统 Shell 注册成功"];
        strongSelf.floatingBinder =
            [strongSelf createFloatingSceneWithIdentifier:strongSelf.floatingSceneIdentifier];
        [strongSelf log:@"全局悬浮歌词场景已创建"];
    });
}

/// 创建一个全局悬浮 Scene（TrollStore 前台场景方案）
- (id)createFloatingSceneWithIdentifier:(NSString *)sceneIdentifier {
    FBSceneManager *sceneManager = [FBSceneManager sharedInstance];

    FBSMutableSceneDefinition *definition = [FBSMutableSceneDefinition definition];
    definition.identity = [FBSSceneIdentity identityForIdentifier:sceneIdentifier];
    definition.clientIdentity = [FBSSceneClientIdentity localIdentity];
    definition.specification = [UIApplicationSceneSpecification specification];

    FBSMutableSceneParameters *parameters =
        [FBSMutableSceneParameters parametersForSpecification:definition.specification];

    UIMutableApplicationSceneSettings *settings = [UIMutableApplicationSceneSettings new];
    settings.displayConfiguration = [[UIScreen mainScreen] displayConfiguration];
    settings.frame = [[UIScreen mainScreen] _referenceBounds];
    settings.level = 1;
    settings.foreground = YES;                       // 前台场景：不被其他 App 遮挡
    settings.interfaceOrientation = UIInterfaceOrientationPortrait;
    settings.deviceOrientationEventsEnabled = YES;
    settings.interruptionPolicy = 0;                 // 不被打断
    [settings.ignoreOcclusionReasons addObject:@"SystemApp"];
    parameters.settings = settings;

    UIMutableApplicationSceneClientSettings *clientSettings =
        [UIMutableApplicationSceneClientSettings new];
    clientSettings.interfaceOrientation = UIInterfaceOrientationPortrait;
    clientSettings.statusBarStyle = 0;
    parameters.clientSettings = clientSettings;

    FBScene *scene = [sceneManager createSceneWithDefinition:definition
                                           initialParameters:parameters];

    UIRootWindowScenePresentationBinder *binder =
        [[UIRootWindowScenePresentationBinder alloc]
            initWithPriority:0
           displayConfiguration:settings.displayConfiguration];
    [binder addScene:scene];
    return binder;
}

#endif

- (void)log:(NSString *)message {
    [[TLDSRuntime shared] logMessage:message];
}

#pragma mark - UISceneSession lifecycle

- (UISceneConfiguration *)application:(UIApplication *)application
configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession
                              options:(UISceneConnectionOptions *)options {
    return [[UISceneConfiguration alloc]
        initWithName:@"Default Configuration"
        sessionRole:connectingSceneSession.role];
}

- (void)application:(UIApplication *)application
didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
}

@end

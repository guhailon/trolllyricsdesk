#import "TLDSAppDelegate.h"
#import "TLDSSceneDelegate.h"
#import "Private/UIKitPrivate.h"
#import "TrollLyricsDesk-Swift.h"
#import <CoreFoundation/CoreFoundation.h>

// 锁屏 / 解锁的 Darwin 通知回调。
// 关键：lockstate / lockcomplete 在锁定和解锁时都会触发，必须确认「已解锁」
// 才重建，否则锁屏那一刻重建的新 scene 会被 SpringBoard 拒绝、白费一次节流窗口。
// 用公开 API isProtectedDataAvailable 判断：锁定=NO，解锁=YES。
// 解锁过程分阶段，延迟多次轮询直到确认解锁。
static void TLDSLockStateChanged(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    TLDSAppDelegate *appDelegate = (__bridge TLDSAppDelegate *)observer;
    // 通知当天先标记「经历过锁屏」，解锁后由轮询确认并重建。
    // 不在这里立即重建：lockcomplete 在锁屏瞬间也会来，那时重建会被系统拒绝。
    dispatch_async(dispatch_get_main_queue(), ^{
        appDelegate.needsRebuildOnUnlock = YES;
    });
    // 解锁过程分阶段，延迟多次轮询直到确认 isProtectedDataAvailable=YES（已解锁）
    int attempts = 16;
    for (int i = 0; i < attempts; i++) {
        double delay = 0.15 + i * 0.25;   // 0.15s ~ 4.0s
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (appDelegate.needsRebuildOnUnlock &&
                [UIApplication sharedApplication].isProtectedDataAvailable) {
                appDelegate.needsRebuildOnUnlock = NO;
                [appDelegate rebuildFloatingOverlay];
            }
        });
    }
}

// ============================================================
// 黑屏修复（关键）
// UIRootWindowScenePresentationBinder 内部会创建 UIRootSceneWindow
// 承载 FBScene 画面，默认不透明黑底且盖在场景窗口之上。
// 用 category 强制透明 + 高 windowLevel，避免打开 App 全黑。
// ============================================================
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

@implementation TLDSAppDelegate

- (BOOL)application:(UIApplication *)application
didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.floatingSceneIdentifier = @"TLDSFloatingLyric";
    // 启动宽限：初始化重建节流时间戳，避免 watchdog 在首启 scene 尚未连上时
    // 误判为断开、立刻重建导致刚建好的场景被拆掉而闪退。
    self.lastRebuildTime = CFAbsoluteTimeGetCurrent();

    // 启动 Swift 播放检测引擎（自动跟随所有播放器）
    [[TLDSRuntime shared] start];
    [self log:@"App 启动：自动跟随已开启"];

    // 注册系统级 Shell + 创建全局悬浮歌词场景
    [self startFloatingOverlay];

    // 监听锁屏状态：解锁后重新激活悬浮窗（锁屏会隐藏 Shell 前台场景）
    // lockcomplete = 已锁定；lockstate = 锁定状态变化（含解锁）。两个都监听。
    CFNotificationCenterRef darwin = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(darwin,
                                    (__bridge const void *)self,
                                    TLDSLockStateChanged,
                                    CFSTR("com.apple.springboard.lockstate"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(darwin,
                                    (__bridge const void *)self,
                                    TLDSLockStateChanged,
                                    CFSTR("com.apple.springboard.lockcomplete"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);

    // App 回到前台 / 即将进入前台：只做轻量恢复，不重建。
    // 注意：didBecomeActive 在启动时也会触发，若这里重建会把刚建好的 scene
    // 立刻拆掉重建，时序不稳会闪退。完整重建只由锁屏解锁的 Darwin 通知驱动。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reactivateFloatingOverlay)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reactivateFloatingOverlay)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];

    // 静音保活由 Swift 侧 BackgroundKeepAlive（AVAudioEngine）负责，此处不重复
    // 配置 audio session，避免两套 AVAudioSession 设置互相冲突导致启动异常。

    // 兜底自检：每 2 秒检查一次悬浮窗可见性。
    self.visibilityWatchdog = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                               target:self
                                                             selector:@selector(reactivateFloatingOverlay)
                                                             userInfo:nil
                                                              repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.visibilityWatchdog
                              forMode:NSRunLoopCommonModes];

    return YES;
}

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
    // 强引用场景本体：锁屏解锁后要靠它重新下发 foreground 设置
    self.floatingScene = scene;
    self.floatingSceneEverCreated = YES;

    UIRootWindowScenePresentationBinder *binder =
        [[UIRootWindowScenePresentationBinder alloc]
            initWithPriority:0
           displayConfiguration:settings.displayConfiguration];
    [binder addScene:scene];
    return binder;
}

/// 锁屏解锁 / 回到前台后重新激活悬浮窗。
/// 锁屏时 SpringBoard 会把 Shell 前台场景的 settings.foreground 置 NO 并隐藏窗口，
/// 解锁后不会自动恢复；这里重新下发 foreground=YES 并强制窗口显示。
- (void)reactivateFloatingOverlay {
    // 悬浮窗还没真正建起来（启动竞态）：无需恢复
    if (!self.shellInitialized || !self.floatingSceneEverCreated) {
        return;
    }

    // 用户关掉了悬浮窗：不恢复
    NSUserDefaults *watchPrefs = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.hailong.TrollLyricsDesk"];
    BOOL watchEnabled = [watchPrefs objectForKey:@"floatingLyric.enabled"] == nil
                      ? YES : [watchPrefs boolForKey:@"floatingLyric.enabled"];
    if (!watchEnabled) {
        return;
    }

    // 场景被系统销毁（sceneDidDisconnect）→ 走完整重建（3 秒节流）
    if (!self.floatingScene || !self.floatingSceneCreated) {
        [self rebuildFloatingOverlay];
        return;
    }

    // 场景还在，只是被降级：重新置前台。
    // 带上 frame / displayConfiguration，避免某些 iOS 版本把增量设置当全量覆盖，
    // 导致窗口几何被清空。
    FBScene *scene = (FBScene *)self.floatingScene;
    UIMutableApplicationSceneSettings *settings = [UIMutableApplicationSceneSettings new];
    settings.displayConfiguration = [[UIScreen mainScreen] displayConfiguration];
    settings.frame = [[UIScreen mainScreen] _referenceBounds];
    [settings setForeground:YES];
    [settings setLevel:1];
    [settings setStatusBarDisabled:YES];
    settings.interfaceOrientation = UIInterfaceOrientationPortrait;
    settings.deviceOrientationEventsEnabled = YES;
    settings.interruptionPolicy = 0;
    [settings.ignoreOcclusionReasons addObject:@"SystemApp"];
    [scene updateSettings:settings
       withTransitionContext:nil
                   completion:nil];

    // 部分情况下绑定器会丢掉场景展示，重新 add 一次（同 scene 重复添加无副作用）
    if (self.floatingBinder) {
        [(UIRootWindowScenePresentationBinder *)self.floatingBinder addScene:scene];
    }

    // 窗口 / 控制器视图可能被隐藏，强制亮回来。
    // 不只判断 isHidden：有些版本 presentation 层被摘掉但标志位仍是 NO。
    BOOL needShow = NO;
    if (self.floatingWindow && self.floatingWindow.isHidden) {
        [self.floatingWindow setHidden:NO];
        needShow = YES;
    }
    // rootViewController.view 的 isHidden 由 Swift 侧 floatingEnabled 控制，
    // 这里只纠正"被系统意外隐藏、但用户开关仍是开"的情况。
    UIViewController *root = self.floatingWindow.rootViewController;
    if (root && root.view.isHidden) {
        NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.hailong.TrollLyricsDesk"];
        BOOL enabled = [prefs objectForKey:@"floatingLyric.enabled"] == nil
                     ? YES : [prefs boolForKey:@"floatingLyric.enabled"];
        if (enabled) {
            root.view.hidden = NO;
            needShow = YES;
        }
    }
    if (needShow) {
        double now = CFAbsoluteTimeGetCurrent();
        if (now - self.lastRestoreLogTime > 20.0) {
            self.lastRestoreLogTime = now;
            [self log:@"锁屏恢复：重新显示悬浮窗口"];
        }
    }
}

/// 场景重建：复用已注册的 Shell，换一个新标识再建悬浮场景。
/// 旧 scene 可能仍残留在 FBSceneManager 里，用相同 identity 会被拒绝，
/// 所以每次重建换一个新标识（SceneDelegate 靠 floatingSceneIdentifier 匹配）。
- (void)startFloatingOverlayRecreate {
    self.floatingSceneCreated = NO;
    self.shellInitialized = YES;
    self.floatingSceneSeq += 1;
    self.floatingSceneIdentifier = [NSString stringWithFormat:@"TLDSFloatingLyric_%ld",
                                    (long)self.floatingSceneSeq];
    self.floatingBinder = [self createFloatingSceneWithIdentifier:self.floatingSceneIdentifier];
    [self log:[NSString stringWithFormat:@"锁屏恢复：悬浮场景已重建 (%@)", self.floatingSceneIdentifier]];
}

#pragma mark - 完整重建（解锁恢复主力）

/// 解锁后调用：丢弃旧 scene / binder / window，走与首次启动完全一致的创建路径。
/// 相比只下发 updateSettings，重建能保证 SpringBoard 真正把 scene 呈现为前台。
- (void)rebuildFloatingOverlay {
    if (!self.shellInitialized || !self.floatingSceneEverCreated) {
        return;
    }
    // 用户双击隐藏了悬浮窗 → 不要重建（尊重开关）
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.hailong.TrollLyricsDesk"];
    BOOL enabled = [prefs objectForKey:@"floatingLyric.enabled"] == nil
                 ? YES : [prefs boolForKey:@"floatingLyric.enabled"];
    if (!enabled) {
        return;
    }

    double now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastRebuildTime < 3.0) {   // 3 秒内不重复重建
        return;
    }
    self.lastRebuildTime = now;

    [self log:@"锁屏恢复：完整重建悬浮场景"];

    // 先摘掉旧 binder（释放旧 scene 的呈现）与旧 window
    UIRootWindowScenePresentationBinder *oldBinder =
        (UIRootWindowScenePresentationBinder *)self.floatingBinder;
    self.floatingBinder = nil;
    if (oldBinder && self.floatingScene &&
        [oldBinder respondsToSelector:NSSelectorFromString(@"removeScene:")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [oldBinder performSelector:NSSelectorFromString(@"removeScene:")
                        withObject:self.floatingScene];   // 避免旧场景残留遮挡
#pragma clang diagnostic pop
    }
    if (self.floatingWindow) {
        [self.floatingWindow setHidden:YES];
        self.floatingWindow = nil;
    }
    self.floatingScene = nil;
    self.floatingSceneCreated = NO;

    // 走首启同款：换新标识 + createScene（SceneDelegate 会重新建 window 并显示）
    self.floatingSceneSeq += 1;
    self.floatingSceneIdentifier = [NSString stringWithFormat:@"TLDSFloatingLyric_%ld",
                                    (long)self.floatingSceneSeq];
    self.shellInitialized = YES;
    self.floatingBinder = [self createFloatingSceneWithIdentifier:self.floatingSceneIdentifier];
    [self log:[NSString stringWithFormat:@"锁屏恢复：重建完成 (%@)", self.floatingSceneIdentifier]];
}

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

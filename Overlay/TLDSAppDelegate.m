#import "TLDSAppDelegate.h"
#import "TLDSSceneDelegate.h"
#import "Private/UIKitPrivate.h"
#import "TrollLyricsDesk-Swift.h"
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

// 1.0.5 诊断（第 5 项）：启动与初始化计数——标清第几次，查 LiveContainer
// 里是不是启动了两次、初始化了两遍。计数只记日志，不改行为。
static NSInteger TLDSLaunchCount = 0;
static NSInteger TLDSStartFloatingOverlayCalls = 0;
static NSInteger TLDSCreateFloatingSceneCalls = 0;
static BOOL TLDSNativeWindowFixInstalled = NO;

// Apply the native window fix only to our standalone process, not the host.
// 与下面已有的 UIRootSceneWindow 分类（TLDSHook）同款：背景透明＋windowLevel 10000；
// 分类在加载时就生效，宿主模式下这个 swizzle 不调用，只保留给巨魔模式。
static void TLDSInstallNativeWindowFix(void) {
    // 1.0.5（第 5 项）：一次性守卫，重复调用记「已安装，跳过」，不重复包两层。
    if (TLDSNativeWindowFixInstalled) {
        [[TLDSRuntime shared] logMessage:@"诊断1.0.6 重复初始化：NativeWindowFix 已安装，跳过"];
        return;
    }
    TLDSNativeWindowFixInstalled = YES;
    Class cls = NSClassFromString(@"UIRootSceneWindow");
    if (!cls) return;
    SEL layout = @selector(layoutSubviews);
    Method method = class_getInstanceMethod(cls, layout);
    if (method) {
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^(UIWindow *window) {
            ((void (*)(id, SEL))original)(window, layout);
            window.layer.backgroundColor = UIColor.clearColor.CGColor;
        });
        class_replaceMethod(cls, layout, replacement, method_getTypeEncoding(method));
    }
    Method level = class_getInstanceMethod(cls, @selector(windowLevel));
    if (level) class_replaceMethod(cls, @selector(windowLevel), imp_implementationWithBlock(^CGFloat(UIWindow *window) { return 10000; }), method_getTypeEncoding(level));
}

// 锁屏 / 解锁的 Darwin 通知回调。
// 关键：lockstate / lockcomplete 在锁定和解锁时都会触发，必须确认「已解锁」
// 才重现，否则锁屏那一刻重现的新 scene 会被 SpringBoard 拒绝、白费一次节流窗口。
// 用公开 API isProtectedDataAvailable 判断：锁定=NO，解锁=YES。
// 解锁过程分阶段，延迟多次轮询直到确认解锁。
static void TLDSLockStateChanged(CFNotificationCenterRef center,
                                 void *observer,
                                 CFStringRef name,
                                 const void *object,
                                 CFDictionaryRef userInfo) {
    TLDSAppDelegate *appDelegate = (__bridge TLDSAppDelegate *)observer;
    // 通知当天先标记「经历过锁屏」，解锁后由轮询确认并重现。
    // 不在这里立即重现：lockcomplete 在锁屏瞬间也会来，那时重现会被系统拒绝。
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
                [appDelegate unlockRestoreFloatingOverlay];
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

    // 1.0.5（第 5 项）：App 启动计数，带第几次。
    TLDSLaunchCount += 1;
    [self log:[NSString stringWithFormat:@"诊断1.0.6 启动：App 启动第 %ld 次", (long)TLDSLaunchCount]];
    if (TLDSLaunchCount > 1) {
        [self log:@"诊断1.0.6 启动：注意——App 在同一进程里启动了多次（LiveContainer 可能重复启动）"];
    }

    self.floatingSceneIdentifier = @"TLDSFloatingLyric";
    // 启动宽限：初始化重建节流时间戳，避免 watchdog 在首启 scene 尚未连上时
    // 误判为断开、立刻重建导致刚建好的场景被拆掉而闪退。
    self.lastRebuildTime = CFAbsoluteTimeGetCurrent();
    // 1.0.6/build 25：记启动时刻——启动兜底只在启动 2 秒后才直接建场景。
    self.launchTime = CFAbsoluteTimeGetCurrent();

    // 启动 Swift 播放检测引擎（自动跟随所有播放器）
    [[TLDSRuntime shared] start];
    [self log:@"App 启动：自动跟随已开启"];

    // 1.0.6（第 8 项）：上次会话是怎么结束的——本次启动先读上次的状态。
    // foreground → 上次还在前台（进程被直接杀掉／闪退）；background 且没收到
    // WillTerminate → 疑似被系统／宿主终止，原因未知（不编）；terminated-clean →
    // 上次正常终止（WillTerminate 已回调）。三次启动里 15:03 那次之前连
    // WillTerminate 行都没有，这段就是为它记的。
    {
        NSUserDefaults *prefs = [TLDSRuntime sharedDefaults];
        NSString *lastState = [prefs stringForKey:@"tlds.lastExitState"];
        double lastTime = [prefs doubleForKey:@"tlds.lastExitTime"];
        if (!lastState) {
            [self log:@"诊断1.0.6 终止：首次启动（无上次会话状态）"];
        } else if ([lastState isEqualToString:@"terminated-clean"]) {
            [self log:[NSString stringWithFormat:@"诊断1.0.6 终止：上次会话正常终止（WillTerminate 已回调，距今 %.0f 秒）", CFAbsoluteTimeGetCurrent() - lastTime]];
        } else if ([lastState isEqualToString:@"background"]) {
            [self log:[NSString stringWithFormat:@"诊断1.0.6 终止：上次会话结束于后台，未收到 WillTerminate（疑似被系统／宿主终止，原因未知，距今 %.0f 秒）", CFAbsoluteTimeGetCurrent() - lastTime]];
        } else {
            [self log:[NSString stringWithFormat:@"诊断1.0.6 终止：上次会话结束于前台，未收到 WillTerminate（疑似被杀／闪退，原因未知，距今 %.0f 秒）", CFAbsoluteTimeGetCurrent() - lastTime]];
        }
        [prefs setObject:@"foreground" forKey:@"tlds.lastExitState"];
        [prefs setDouble:CFAbsoluteTimeGetCurrent() forKey:@"tlds.lastExitTime"];
    }

    // 1.0.6 三项判定分离（第 1／2 项）：安装环境只凭正面证据定一次，
    // 托管复核只定显示能力，永远不改安装环境。
    // - trollstore（任务权限／沙盒外写证明）：原生 HUD，启动即定档，不复核。
    // - livecontainer（LC 信号）：先记「待探测」，尝试创建悬浮窗，
    //   等托管复核（2 秒后）凭托管结构定显示能力（PiP 首选／应用内）。
    // - signature（已证实被沙盒拦住）：不建悬浮窗，直接应用内歌词。
    // - unknown（权限探测不可用）：尝试创建悬浮窗，等复核定显示能力；
    //   安装环境仍记 unknown，不改。注册成功 ≠ 可见：复核没结论前，
    //   任何「创建成功」日志都不当成功用。
    NSString *installEnv = [[TLDSRuntime shared] detectInstallEnvironment];
    if ([installEnv isEqualToString:@"trollstore"]) {
        [[TLDSRuntime shared] setRunMode:@"trollstore"
                                  reason:@"TrollStore 正面证据已出（见安装环境行）"];
        [[TLDSRuntime shared] setDisplayCapability:@"nativeHUD"
                                            reason:@"巨魔原生模式，悬浮窗照常，不复核"];
        self.modeDecided = YES;
        self.shouldVerify = NO;
        [self log:@"运行模式：巨魔原生模式（TrollStore，私有接口全可用，悬浮窗照常）"];
        [self log:@"诊断1.0.6 显示引擎：原生 HUD 悬浮歌词（巨魔原生模式，唯一档）"];
        // 1.0.6（并入 ChatGPT 1.0.6）：原生分支也包 @try/@catch，Shell 注册抛异常就降级。
        @try {
            TLDSInstallNativeWindowFix();
            [self startFloatingOverlay];
        } @catch (NSException *e) {
            [self log:[NSString stringWithFormat:@"诊断1.0.6 托管：Shell 注册抛异常：%@（直接降级普通签名兼容模式）", e.reason ?: @"?"]];
            [self downgradeToCompatModeWithReasons:@[@"Shell 注册抛异常"]];
        }
    } else if ([installEnv isEqualToString:@"livecontainer"]) {
        self.shouldVerify = YES;
        [[TLDSRuntime shared] setRunMode:@"probing"
                                  reason:@"LiveContainer 信号已出，等托管复核定显示能力"];
        [self log:@"运行模式：待探测（LiveContainer 信号已出，尝试创建悬浮窗，等 2 秒后托管复核定显示能力）"];
        @try {
            [self startFloatingOverlay];
        } @catch (NSException *e) {
            [self log:[NSString stringWithFormat:@"诊断1.0.6 托管：Shell 注册抛异常：%@（直接降级普通签名兼容模式）", e.reason ?: @"?"]];
            [self downgradeToCompatModeWithReasons:@[@"Shell 注册抛异常"]];
        }
        // 兜底：Shell 回调一直不来（createFloatingScene 没跑、复核没排上），
        // 6 秒后仍没结论就直接复核一次——scene 为空也会判兼容，不会一直悬在「待探测」。
        __weak TLDSAppDelegate *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong TLDSAppDelegate *strongSelf = weakSelf;
            if (strongSelf && !strongSelf.modeDecided) {
                [strongSelf verifyFloatingVisibility];
            }
        });
    } else if ([installEnv isEqualToString:@"signature"]) {
        [[TLDSRuntime shared] setRunMode:@"compat"
                                  reason:@"普通签名（已证实被沙盒拦住），不建悬浮窗"];
        [[TLDSRuntime shared] setDisplayCapability:@"inApp"
                                            reason:@"普通签名兼容模式，悬浮窗不可用"];
        self.modeDecided = YES;
        self.compatMode = YES;
        self.shouldVerify = NO;
        [self log:@"运行模式：普通签名兼容模式（已证实被沙盒拦住，不建悬浮窗，走应用内歌词）"];
        [self log:@"诊断1.0.6 显示引擎：应用内歌词（普通签名兼容模式唯一档，不支持跨 App、桌面）"];
    } else {
        // unknown：安装环境未确认。先记原生候选（安装来源未知，尝试 HUD，
        // 并入 ChatGPT 1.0.6），尝试创建悬浮窗，等复核定显示能力；
        // 复核通过写原生候选、失败降级兼容——安装环境仍记 unknown，不改。
        self.shouldVerify = YES;
        [[TLDSRuntime shared] setRunMode:@"native-candidate"
                                  reason:@"未发现宿主信号；安装来源及权限未知（见安装环境行的证据）"];
        [self log:@"运行模式：原生候选（安装来源未知，尝试 HUD）"];
        [self log:@"诊断1.0.6 显示引擎：原生 HUD 悬浮歌词（候选，实际可见性未确认）"];
        @try {
            [self startFloatingOverlay];
        } @catch (NSException *e) {
            [self log:[NSString stringWithFormat:@"诊断1.0.6 托管：Shell 注册抛异常：%@（直接降级普通签名兼容模式）", e.reason ?: @"?"]];
            [self downgradeToCompatModeWithReasons:@[@"Shell 注册抛异常"]];
        }
        __weak TLDSAppDelegate *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong TLDSAppDelegate *strongSelf = weakSelf;
            if (strongSelf && !strongSelf.modeDecided) {
                [strongSelf verifyFloatingVisibility];
            }
        });
    }

    // 1.0.6（第 7 项）：激活前后悬浮窗状态快照——Swift 侧 ActivationView 发通知，
    // 这里接住记窗口状态（窗口在不在、isHidden、windowScene、frame）。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tlds_logFloatingWindowStateNotification:)
                                                 name:@"TLDSLogFloatingWindowState"
                                               object:nil];

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
                                             selector:@selector(tlds_reactivateFromForegroundNotification)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tlds_reactivateFromForegroundNotification)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];

    // 1.0.5（第 6 项）：后台挂起及恢复日志——真机日志要能看出悬浮窗消失
    // 是不是因为 App 被挂起了。只记日志，不改行为。
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tlds_logDidEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tlds_logWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tlds_logWillTerminate)
                                                 name:UIApplicationWillTerminateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(tlds_logDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];

    // 静音保活由 Swift 侧 BackgroundKeepAlive（AVAudioEngine）负责，此处不重复
    // 配置 audio session，避免两套 AVAudioSession 设置互相冲突导致启动异常。

    // 兜底自检：每 2 秒检查一次悬浮窗可见性。
    self.visibilityWatchdog = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                               target:self
                                                             selector:@selector(tlds_watchdogReactivate)
                                                             userInfo:nil
                                                              repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.visibilityWatchdog
                              forMode:NSRunLoopCommonModes];

    return YES;
}

- (void)startFloatingOverlay {
    // 1.0.5（第 5 项）：调用计数＋一次性守卫，重复时记「已初始化，跳过」。
    TLDSStartFloatingOverlayCalls += 1;
    [self log:[NSString stringWithFormat:@"诊断1.0.6 启动：startFloatingOverlay 调用第 %ld 次", (long)TLDSStartFloatingOverlayCalls]];
    if (self.shellInitialized) {
        [self log:@"诊断1.0.6 重复初始化：Shell 已初始化，跳过（不建第二个窗）"];
        return;
    }
    self.shellInitialized = YES;

    __weak TLDSAppDelegate *weakSelf = self;
    [self log:@"注册系统 Shell..."];

    // 把本进程注册为系统级 Shell，成功后创建的 FBScene
    // 才能成为"压在其他 App / 桌面之上"的前台场景。
    @try {
        FBSystemShellInitialize(^(id arg) {
            __strong TLDSAppDelegate *strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            [strongSelf log:@"系统 Shell 注册成功"];
            // 1.0.6/build 25：看门狗兜底可能已直接建好场景——回调晚到时不再建
            // 第二个（11:05 真机：Shell 回调丢了就永远没窗；兜底建了、回调又建，
            // 就是两个窗）。场景已建过就跳过，只记一行。
            if (strongSelf.floatingSceneEverCreated) {
                [strongSelf log:@"诊断1.0.6 启动：Shell 回调到了，悬浮场景已由兜底建好，跳过（不建第二个窗）"];
                return;
            }
            strongSelf.floatingBinder =
                [strongSelf createFloatingSceneWithIdentifier:strongSelf.floatingSceneIdentifier];
            [strongSelf log:@"全局悬浮歌词场景已创建"];
        });
    } @catch (NSException *e) {
        [self log:[NSString stringWithFormat:@"诊断1.0.6 托管：Shell 注册抛异常：%@（直接降级普通签名兼容模式）", e.reason ?: @"?"]];
        [self downgradeToCompatModeWithReasons:@[@"Shell 注册抛异常"]];
    }
}

/// 创建一个全局悬浮 Scene（TrollStore 前台场景方案）
- (id)createFloatingSceneWithIdentifier:(NSString *)sceneIdentifier {
    // 1.0.5（第 5 项）：scene 创建计数，带第几次。
    TLDSCreateFloatingSceneCalls += 1;
    [self log:[NSString stringWithFormat:@"诊断1.0.6 启动：createFloatingScene 调用第 %ld 次（标识 %@）", (long)TLDSCreateFloatingSceneCalls, sceneIdentifier]];
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
    // 1.0.6/build 25：记当前场景创建时间——连接窗口超 10 秒未连上即判卡住。
    self.floatingSceneCreatedTime = CFAbsoluteTimeGetCurrent();
    // 1.0.6/build 21：新场景对象刚创建、尚未连接——重建竞态守卫的锚点。
    // willConnectToSession 跑过才置 YES；此前的窗口里，任何触发都不得
    // rebuild／销毁它（对正在连接的会话请求销毁会和 UIKit 连接流程撞车而闪退）。
    self.floatingSceneEverConnected = NO;

    // 1.0.5（第 3 项）：场景创建时的诊断——只打日志，不改行为。
    // Context ID 用 KVC 读（不同 iOS 版本键未必在，读不到就记「读不到」，不 crash）。
    NSString *contextIDText = @"读不到（无此键）";
    @try {
        id ctxID = [scene valueForKey:@"contextID"];
        if (ctxID) {
            contextIDText = [NSString stringWithFormat:@"%@", ctxID];
        }
    } @catch (NSException *e) {
        contextIDText = @"读不到（取值抛异常）";
    }
    NSString *foregroundText = @"读不到";
    @try {
        id settings = [scene settings];
        id fg = [settings valueForKey:@"foreground"];
        if (fg) {
            foregroundText = [fg boolValue] ? @"YES" : @"NO";
        }
    } @catch (NSException *e) {
        foregroundText = @"读不到（取值抛异常）";
    }
    [self log:[NSString stringWithFormat:@"诊断1.0.6 场景：createScene 返回 %@，Context ID=%@，settings.foreground=%@（创建成功≠可见，等复核）",
               scene ? @"非空" : @"空（创建失败）", contextIDText, foregroundText]];

    UIRootWindowScenePresentationBinder *binder =
        [[UIRootWindowScenePresentationBinder alloc]
            initWithPriority:0
           displayConfiguration:settings.displayConfiguration];
    [binder addScene:scene];
    [self log:[NSString stringWithFormat:@"诊断1.0.6 场景：binder %@，addScene 已调用（binder 收没收录，等复核查 scenes）",
               binder ? @"已创建" : @"创建失败（空）"]];

    // 1.0.6（第 2 项）：创建后 2 秒延迟复核——只在宿主／未确认环境分支排。
    // 巨魔原生与普通签名在启动时已定档（shouldVerify=NO），复核不排、
    // 不跑、不改模式；复核只定显示能力，永不改安装环境。
    __weak TLDSAppDelegate *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        __strong TLDSAppDelegate *strongSelf = weakSelf;
        if (strongSelf && strongSelf.shouldVerify && !strongSelf.modeDecided) {
            [strongSelf verifyFloatingVisibility];
        }
    });
    return binder;
}

#pragma mark - 1.0.5 托管复核与三档模式判定（第 3／4 项）

/// 悬浮窗创建后延迟复核：逐项查「真生效」，结论只定显示能力，永不改安装环境。
/// 结论行写清三段——托管结构检查：通过／失败、Context ID：有效／未知／无效、
/// 实际屏幕可见性：未确认／待确认；不再用一句「已确认可见」盖过去。
/// 非宿主（安装环境未确认）时复核通过写 native-candidate 后 return，
/// 不再写 enhanced-host（并入 ChatGPT 1.0.6，皇上 23:18 批并）。
- (void)verifyFloatingVisibility {
    if (self.modeDecided || !self.shouldVerify) {
        return;
    }
    self.verifyAttempts += 1;

    // 场景还没连上（悬浮 window 还是空）：只给一次重试机会，
    // 3 秒后再复核；两次都没连上就按「未确认可见」判兼容。
    if (!self.floatingWindow && self.verifyAttempts < 2) {
        [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核：第 %ld 次——悬浮窗口尚未创建（场景未连上），3 秒后重核", (long)self.verifyAttempts]];
        __weak TLDSAppDelegate *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong TLDSAppDelegate *strongSelf = weakSelf;
            if (strongSelf && !strongSelf.modeDecided) {
                [strongSelf verifyFloatingVisibility];
            }
        });
        return;
    }

    NSMutableArray<NSString *> *failReasons = [NSMutableArray array];

    BOOL hasScene = self.floatingScene != nil;
    [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核：场景对象 %@",
               hasScene ? @"通过（floatingScene 非空）" : @"失败（floatingScene 为空）"]];
    if (!hasScene) [failReasons addObject:@"场景对象为空"];

    BOOL binderHasScene = NO;
    if (self.floatingBinder && self.floatingScene &&
        [self.floatingBinder respondsToSelector:@selector(scenes)]) {
        NSSet *scenes = [(UIRootWindowScenePresentationBinder *)self.floatingBinder scenes];
        binderHasScene = [scenes containsObject:self.floatingScene];
    }
    [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核：binder 收录场景 %@",
               self.floatingBinder ? (binderHasScene ? @"通过（scenes 含本场景）" : @"失败（scenes 不含本场景，SpringBoard 没接受／binder 丢了场景）") : @"失败（binder 为空）"]];
    if (!binderHasScene) [failReasons addObject:@"binder 未收录场景"];

    BOOL hasWindow = self.floatingWindow != nil;
    [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核：悬浮窗口 %@",
               hasWindow ? @"通过（floatingWindow 非空）" : @"失败（floatingWindow 为空，SceneDelegate 没连上悬浮场景）"]];
    if (!hasWindow) [failReasons addObject:@"悬浮窗口为空"];

    BOOL windowVisible = NO;
    BOOL windowInScene = NO;
    BOOL viewAttached = NO;
    if (hasWindow) {
        UIWindow *w = self.floatingWindow;
        // 1.0.6（并入 ChatGPT 1.0.6）：可见性收紧——isHidden=NO 还不够，
        // alpha 也必须 > 0；视图挂载必须是「挂在当前窗口上」（view.window == w），
        // 光是非空不算（旧窗残留时 view.window 可能指着别的窗）。
        windowVisible = !w.isHidden && w.alpha > 0;
        windowInScene = w.windowScene != nil;
        viewAttached = w.rootViewController.view.window == w;
        [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核：窗口 isHidden=%@（%@），windowLevel=%.0f（期望 10000），alpha=%.2f，backgroundColor=%@",
                   w.isHidden ? @"YES" : @"NO",
                   windowVisible ? @"通过" : @"失败（窗口被隐藏）",
                   w.windowLevel, w.alpha, w.backgroundColor ? @"已设置" : @"nil"]];
        [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核：windowScene %@，rootView 已挂到 window %@，frame=%@",
                   windowInScene ? @"通过（非空）" : @"失败（为空，场景没活）",
                   viewAttached ? @"通过（view.window 非空）" : @"失败（view.window 为空，视图没挂上）",
                   NSStringFromCGRect(w.frame)]];
        if (!windowVisible) [failReasons addObject:@"窗口 isHidden=YES"];
        if (!windowInScene) [failReasons addObject:@"窗口无 windowScene"];
        if (!viewAttached) [failReasons addObject:@"视图未挂到窗口"];
        // 观察项（不进判定）：App 级 windows 列表里有没有它。
        BOOL inAppWindows = [[[UIApplication sharedApplication] windows] containsObject:w];
        [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核（观察）：窗口在 UIApplication.windows 里 %@（仅供参考，不进判定）",
                   inAppWindows ? @"有" : @"无"]];
    }

    // Context ID：有效（非 0 数字）算通过；读不到只记警告，不进判定
    // （不同 iOS 版本未必暴露这个键，读不到 ≠ 没托管）。
    NSString *contextIDText = @"读不到（无此键）";
    BOOL contextIDValid = NO;
    BOOL contextIDUnknown = YES;
    if (hasScene) {
        @try {
            id ctxID = [(FBScene *)self.floatingScene valueForKey:@"contextID"];
            if (ctxID) {
                contextIDUnknown = NO;
                contextIDText = [NSString stringWithFormat:@"%@", ctxID];
                contextIDValid = [ctxID respondsToSelector:@selector(unsignedIntValue)]
                    ? [ctxID unsignedIntValue] != 0
                    : NO;   // 1.0.6（并入 ChatGPT 1.0.6）：取不到数值方法时算无效，不再当通过
            }
        } @catch (NSException *e) {
            contextIDText = @"读不到（取值抛异常）";
        }
    }
    [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核：Context ID=%@（%@）",
               contextIDText,
               contextIDUnknown ? @"未知（读不到，不进判定）" : (contextIDValid ? @"通过（有效）" : @"失败（为 0／无效）")]];
    if (!contextIDUnknown && !contextIDValid) [failReasons addObject:@"Context ID 无效"];

    // 结论：托管结构检查只定显示能力，永不改安装环境。
    // 结构全过 → 宿主判增强宿主（首选 PiP 实验），未确认环境判原生候选；
    // 任一关键项失败 → 降级兼容模式。结论行写清三段（第 6 项）：
    // 托管结构检查：通过／失败、Context ID：有效／未知／无效、
    // 实际屏幕可见性：未确认——binder／窗口／windowScene 只能证明托管结构通过，
    // 不能证明系统真把窗口合成到屏幕上了。
    NSString *contextPart = contextIDUnknown ? @"Context ID：未知"
        : (contextIDValid ? @"Context ID：有效" : @"Context ID：无效");
    if (failReasons.count == 0) {
        self.modeDecided = YES;
        self.compatMode = NO;
        NSString *reason = [NSString stringWithFormat:@"托管结构检查通过；场景／binder／窗口／windowScene／视图挂载均通过，%@；实际屏幕可见性未确认", contextPart];
        [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核详情：托管结构检查：通过／%@／实际屏幕可见性：未确认", contextPart]];
        [self log:@"诊断1.0.6 托管结构检查通过；实际屏幕可见性未确认"];
        if (![[[TLDSRuntime shared] installEnvironmentString] isEqualToString:@"livecontainer"]) {
            // 未确认环境：托管结构通过，但安装来源未知——写原生候选后 return，
            // 不再写 enhanced-host（并入 ChatGPT 1.0.6）。
            [[TLDSRuntime shared] setDisplayCapability:@"nativeHUD"
                                                reason:@"原生候选：托管结构通过，安装来源未知，实际屏幕可见性未确认"];
            [[TLDSRuntime shared] setRunMode:@"native-candidate" reason:reason];
            [self log:@"托管结构检查通过；安装来源未知；实际屏幕可见性未确认"];
            [self log:@"运行模式：原生候选（安装来源未知，尝试 HUD，实际屏幕可见性未确认）"];
            return;
        }
        [[TLDSRuntime shared] setDisplayCapability:@"pip"
                                            reason:@"增强宿主模式，首选 PiP 实验，应用内备选"];
        [[TLDSRuntime shared] setRunMode:@"enhanced-host" reason:reason];
        [self log:@"运行模式：增强宿主模式（LiveContainer，托管结构检查通过，首选 PiP 实验，应用内备选）"];
        [self log:@"诊断1.0.6 显示引擎：PiP 画中画歌词（实验）（增强宿主模式首选），应用内歌词备选；透明全域悬浮在此模式为权限受限，不信任原生 HUD"];
    } else {
        [self log:[NSString stringWithFormat:@"诊断1.0.6 托管复核结论：未确认可见（原因：%@）", [failReasons componentsJoinedByString:@"；"]]];
        [self downgradeToCompatModeWithReasons:failReasons];
    }
}

/// 复核未通过 → 降级普通签名兼容模式：摘掉场景、隐藏窗口、不再重建，
/// 只走应用内歌词。清理动作本身也记日志（探测建的窗要清理掉，不留残窗）。
- (void)downgradeToCompatModeWithReasons:(NSArray<NSString *> *)reasons {
    if (self.modeDecided && self.compatMode) {
        return;
    }
    self.modeDecided = YES;
    self.compatMode = YES;

    if (self.floatingBinder && self.floatingScene &&
        [self.floatingBinder respondsToSelector:NSSelectorFromString(@"removeScene:")]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.floatingBinder performSelector:NSSelectorFromString(@"removeScene:")
                                  withObject:self.floatingScene];
#pragma clang diagnostic pop
        [self log:@"诊断1.0.6 降级：已从 binder 摘掉悬浮场景"];
    }
    if (self.floatingWindow) {
        [self.floatingWindow setHidden:YES];
        [self log:@"诊断1.0.6 降级：悬浮窗口已隐藏"];
    }
    self.floatingBinder = nil;
    self.floatingScene = nil;
    self.floatingSceneCreated = NO;

    NSString *reason = [NSString stringWithFormat:@"托管检查未通过：%@", [reasons componentsJoinedByString:@"；"]];
    [[TLDSRuntime shared] setDisplayCapability:@"inApp"
                                        reason:@"托管检查未通过，只走应用内歌词"];
    [[TLDSRuntime shared] setRunMode:@"compat" reason:reason];
    // 1.0.6（并入 ChatGPT 1.0.6）：降级不推断安装来源——托管检查未过只说明
    // 悬浮窗不可用，不说明装在哪、权限如何。
    [self log:@"运行模式：兼容模式（托管检查未通过，安装来源不由此推断，应用内歌词）"];
    [self log:@"诊断1.0.6 显示引擎：应用内歌词（普通签名兼容模式唯一档，不支持跨 App、桌面）"];
}

/// 锁屏解锁 / 回到前台后重新激活悬浮窗。
/// 锁屏时 SpringBoard 会把 Shell 前台场景的 settings.foreground 置 NO 并隐藏窗口，
/// 解锁后不会自动恢复；这里重新下发 foreground=YES 并强制窗口显示。
/// 1.0.6（第 7 项）：触发来源分开记（2 秒看门狗／回到前台／未知），
/// 日志行写清触发、窗口状态、激活状态与安装环境——14:45:29／36 激活前后
/// 各有一次「锁屏恢复」那条线，这次要能看出它到底是谁触发的、激活有没有丢窗。
- (void)reactivateFloatingOverlay {
    [self reactivateFloatingOverlayWithTrigger:@"前台／看门狗"];
}

/// 2 秒看门狗的恢复入口（触发写清是看门狗）。
- (void)tlds_watchdogReactivate {
    [self reactivateFloatingOverlayWithTrigger:@"2 秒看门狗"];
}

/// 回到前台通知的恢复入口（触发写清是回到前台）。
- (void)tlds_reactivateFromForegroundNotification {
    [self reactivateFloatingOverlayWithTrigger:@"回到前台"];
    // 1.0.6/build 26：前台复核——回前台 1.5 秒后验悬浮窗真在不在。
    // reactivate 只管「场景还在就重发设置／取消隐藏」，不管「窗口到底在不在」；
    // 解锁重建在后台跑完后，窗口可能根本没建出来（floatingWindow 为空）或没挂上，
    // 这时 reactivate 的「场景还在」分支什么都不做——这就是锁屏→解锁后主屏幕没窗、
    // 只有打开 App 主页面才回来的原因。复核是兜底，不是替代：解锁重建、看门狗、
    // build 25 的启动兜底全都不动。
    // WillEnterForeground 与 DidBecomeActive 同一次回前台各调一次这里，
    // scheduled 守卫保证只排一次复核；1.5 秒是宽限——解锁重建刚建好的场景
    // 可能还在连接，复核里再看，不到 2 秒不判「不在」。
    if (!self.foregroundVerifyScheduled) {
        self.foregroundVerifyScheduled = YES;
        self.foregroundVerifyRetries = 0;
        __weak TLDSAppDelegate *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong TLDSAppDelegate *strongSelf = weakSelf;
            if (strongSelf) {
                strongSelf.foregroundVerifyScheduled = NO;
                [strongSelf foregroundVerifyFloatingWindow];
            }
        });
    }
}

/// 1.0.6/build 26：前台复核——回前台时验悬浮窗真在不在。
/// 判据只认窗口本身（与 verifyFloatingVisibility 的窗口判据同款）：
/// floatingWindow 非空、isHidden=NO、alpha>0、windowScene 非空、
/// rootView 的 window 就是它。场景连着不算数——场景连着、窗没了，
/// 正是 reactivate「场景还在」分支的盲区（只重发设置、不重建）。
/// 只验、不直接建场景——创建归 build 25 的启动兜底管；窗不在就走现成的
/// rebuildFloatingOverlay（先销毁旧会话、只建一个窗，3 秒节流照常）。
- (void)foregroundVerifyFloatingWindow {
    self.foregroundVerifyScheduled = NO;
    // 普通签名兼容模式：不建窗、不重建（与 reactivate 同款守卫）。
    if (self.compatMode) {
        return;
    }
    // 场景一次都没建过：创建归 build 25 的启动兜底管，这里只验已建好的窗。
    if (!self.shellInitialized || !self.floatingSceneEverCreated) {
        return;
    }
    // 用户关掉了悬浮窗：不恢复（尊重开关，与 reactivate／rebuild 同款）。
    NSUserDefaults *prefs = [TLDSRuntime sharedDefaults];
    BOOL enabled = [prefs objectForKey:@"floatingLyric.enabled"] == nil
                 ? YES : [prefs boolForKey:@"floatingLyric.enabled"];
    if (!enabled) {
        return;
    }

    // 宽限：场景刚建好、还在连接——不到 2 秒不判「不在」（build 21 的教训：
    // 对正在连接的会话重建会和 UIKit 连接流程撞车而闪退）。
    // 2 秒内：最多再排一次（1.5 秒后），给它连上的时间；2 秒后仍未连上
    // 但不到 10 秒：先不动（看门狗的 build 25 卡住逻辑 10 秒后会判卡住走重建，
    // 下一次回前台也会再验）；10 秒以上：判卡住，往下走重建。
    if (self.floatingScene && !self.floatingSceneCreated && !self.floatingSceneEverConnected) {
        double now = CFAbsoluteTimeGetCurrent();
        double age = now - self.floatingSceneCreatedTime;
        if (age < 2.0) {
            if (self.foregroundVerifyRetries < 2) {
                self.foregroundVerifyRetries += 1;
                [self log:[NSString stringWithFormat:@"诊断1.0.6 前台复核：场景正在连接中，先不动（已创建 %.1f 秒，1.5 秒后再验）", age]];
                self.foregroundVerifyScheduled = YES;
                __weak TLDSAppDelegate *weakSelf = self;
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    __strong TLDSAppDelegate *strongSelf = weakSelf;
                    if (strongSelf) {
                        strongSelf.foregroundVerifyScheduled = NO;
                        [strongSelf foregroundVerifyFloatingWindow];
                    }
                });
            } else {
                [self log:@"诊断1.0.6 前台复核：场景正在连接中，先不动（已重验 2 次，等看门狗／下一次回前台）"];
            }
            return;
        }
        if (age < 10.0) {
            [self log:[NSString stringWithFormat:@"诊断1.0.6 前台复核：场景正在连接中，先不动（已创建 %.1f 秒，未到 10 秒卡住线）", age]];
            return;
        }
        [self log:[NSString stringWithFormat:@"诊断1.0.6 前台复核：场景创建已超过 10 秒仍未连接，判定卡住，走重建（触发：foreground-verify，已创建 %.1f 秒）", age]];
        // 往下走重建：窗肯定不在（场景都没连上）；rebuild 对未连上的场景
        // 跳过销毁（只摘 binder＋藏窗口），不撞车。
        [self rebuildFloatingOverlay];
        return;
    }

    // 验窗真在不在（只认窗口本身）。
    UIWindow *w = self.floatingWindow;
    BOOL windowPresent = w != nil && !w.isHidden && w.alpha > 0 && w.windowScene != nil
        && w.rootViewController != nil && w.rootViewController.view.window == w;
    if (windowPresent) {
        [self log:@"诊断1.0.6 前台复核：悬浮窗在，不动"];
        return;
    }
    // 窗不在：走重建（触发：foreground-verify）。重建有 3 秒节流——
    // 节流内被拦住时 3.5 秒后再验一次（最多再排一次），不让这次回前台白跑。
    double now = CFAbsoluteTimeGetCurrent();
    if (now - self.lastRebuildTime < 3.0) {
        if (self.foregroundVerifyRetries < 2) {
            self.foregroundVerifyRetries += 1;
            [self log:@"诊断1.0.6 前台复核：悬浮窗不在，但 3 秒节流内，3.5 秒后再验一次"];
            self.foregroundVerifyScheduled = YES;
            __weak TLDSAppDelegate *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                __strong TLDSAppDelegate *strongSelf = weakSelf;
                if (strongSelf) {
                    strongSelf.foregroundVerifyScheduled = NO;
                    [strongSelf foregroundVerifyFloatingWindow];
                }
            });
        } else {
            [self log:@"诊断1.0.6 前台复核：悬浮窗不在，但 3 秒节流内（已重验 2 次，等看门狗／下一次回前台）"];
        }
        return;
    }
    [self log:[NSString stringWithFormat:@"诊断1.0.6 前台复核：悬浮窗不在，走重建（触发：foreground-verify，窗口：%@，windowScene：%@，场景已连：%@）",
               w ? (w.isHidden ? @"已创建但隐藏" : @"已创建") : @"未创建",
               (w && w.windowScene) ? @"非空" : @"空",
               self.floatingSceneCreated ? @"YES" : @"NO"]];
    [self rebuildFloatingOverlay];
}

- (void)reactivateFloatingOverlayWithTrigger:(NSString *)trigger {
    // 1.0.5：普通签名兼容模式下不再恢复悬浮窗（只记一次，不让 2 秒看门狗刷屏）。
    if (self.compatMode) {
        if (!self.compatSkipLogged) {
            self.compatSkipLogged = YES;
            [self log:@"诊断1.0.6 降级：普通签名兼容模式，跳过悬浮窗恢复（只走应用内歌词）"];
        }
        return;
    }
    // 1.0.6/build 25：Shell 回调没来、场景一次都没建过——不能直接 return，
    // 否则启动创建丢一次就永远没窗（11:05 真机：重启动也没回来，窗只有启动
    // App 那一下才来）。2 秒看门狗／回到前台到这里时，直接建一次（与 Shell
    // 回调同款入口 createFloatingSceneWithIdentifier；回调晚到时有守卫，
    // 不会建两个）。启动那一刻的 DidBecomeActive 不抢——给 Shell 回调 2 秒
    // 机会（看门狗本来就是 2 秒一轮，首轮正好 2 秒后）。
    // 建完就 return：下一次看门狗／回前台再走正常恢复流程。
    if (!self.shellInitialized) {
        return;
    }
    if (!self.floatingSceneEverCreated) {
        double now25 = CFAbsoluteTimeGetCurrent();
        if (now25 - self.launchTime < 2.0) {
            return;
        }
        [self log:[NSString stringWithFormat:@"诊断1.0.6 启动兜底：Shell 回调未到，直接建悬浮场景（触发：%@，启动已过 %.0f 秒）",
                   trigger ?: @"未知", now25 - self.launchTime]];
        self.floatingBinder = [self createFloatingSceneWithIdentifier:self.floatingSceneIdentifier];
        return;
    }

    // 1.0.6/build 21（重建竞态修）：场景正在连接（已创建、未连上）时跳过这次恢复。
    // 主页面出现那一刻 DidBecomeActive 就会调到这里；这时若调 rebuild，
    // rebuild 会对一个正在连接的会话请求销毁，和 UIKit 连接流程撞车而闪退
    //（2026-11-27 02:19 皇上证实：主页面一出现就闪）。
    // 等连接完成，下一次看门狗／回到前台再恢复。日志 20 秒节流，不让看门狗刷屏。
    // 1.0.6/build 25：连接窗口只给 10 秒——刚建好正在连时跳过（build 21 的
    // 闪退保护不动）；超过 10 秒还没连上就是卡住了，不再无限等，往下走重建
    //（rebuild 本身对未连上的场景跳过销毁，只摘 binder＋藏窗口，不会撞车）。
    if (self.floatingScene && !self.floatingSceneCreated && !self.floatingSceneEverConnected) {
        double now = CFAbsoluteTimeGetCurrent();
        if (now - self.floatingSceneCreatedTime < 10.0) {
            if (now - self.lastConnectingSkipLogTime > 20.0) {
                self.lastConnectingSkipLogTime = now;
                [self log:[NSString stringWithFormat:@"诊断1.0.6 悬浮窗恢复：场景正在连接中，跳过这次恢复（触发：%@，等连接完成后再说）",
                           trigger ?: @"未知"]];
            }
            return;
        }
        [self log:[NSString stringWithFormat:@"诊断1.0.6 悬浮窗恢复：场景创建已超过 10 秒仍未连接（触发：%@），判定卡住，走重建",
                   trigger ?: @"未知"]];
    }

    // 用户关掉了悬浮窗：不恢复
    NSUserDefaults *watchPrefs = [TLDSRuntime sharedDefaults];  // 1.0.5 bug 2：走 LyricStore.defaults
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
    BOOL windowWasHidden = NO;
    BOOL viewWasHidden = NO;
    if (self.floatingWindow && self.floatingWindow.isHidden) {
        windowWasHidden = YES;
        [self.floatingWindow setHidden:NO];
        needShow = YES;
    }
    // rootViewController.view 的 isHidden 由 Swift 侧 floatingEnabled 控制，
    // 这里只纠正"被系统意外隐藏、但用户开关仍是开"的情况。
    UIViewController *root = self.floatingWindow.rootViewController;
    if (root && root.view.isHidden) {
        viewWasHidden = YES;
        NSUserDefaults *prefs = [TLDSRuntime sharedDefaults];  // 1.0.5 bug 2：走 LyricStore.defaults
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
            // 1.0.6（第 7 项）：触发、窗口状态、激活状态、安装环境一次写清。
            // 旧行「锁屏恢复：重新显示悬浮窗口」前缀有误导性（触发常不是锁屏），
            // 改名并附上下文；激活成功后这行若出现，对照第 7 项的两张快照看丢没丢窗。
            BOOL activated = [[TLDSRuntime sharedDefaults] boolForKey:@"tld.activated"];
            [self log:[NSString stringWithFormat:@"诊断1.0.6 悬浮窗恢复：重新显示悬浮窗口（触发：%@，窗口 wasHidden=%@，视图 wasHidden=%@，已激活=%@，%@）",
                       trigger ?: @"未知",
                       windowWasHidden ? @"YES" : @"NO",
                       viewWasHidden ? @"YES" : @"NO",
                       activated ? @"YES" : @"NO",
                       [[TLDSRuntime shared] environmentTag]]];
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

#pragma mark - 1.0.6/build 27 解锁重现（解锁恢复主力，优先于完整重建）

/// 解锁后调用：旧场景还在就重现，不重建；旧场景真不在了才走完整重建。
/// 病根（代码＋真机日志坐实）：解锁重建在后台销毁旧场景、建新场景；后台建的
/// 场景本地全通（连接／激活／窗口已创建，10:53 与 14:59:44 两次都这样），却
/// 从不被合成到屏幕上，直到 App 回前台。旧场景是前台建的、锁屏前可见，锁屏时
/// 系统只把它降级（foreground=NO、窗口隐藏），会话／窗口／binder 都还在——
/// 全量日志里从无「悬浮歌词场景断开」行。重现它（重发 foreground 设置＋取消
/// 隐藏），不销毁、不新建。歌词内容不用另推：悬浮窗控制器 0.25 秒定时器一直在
/// 读共享快照、后台也在跑（15:04:25／28 都有新歌检测行），重现后窗口里直接就
/// 是当前行。
/// 诚实说明：重现能不能合成，代码＋日志钉不死——本地状态好≠屏幕可见（老教训）。
/// 重现后 2 秒记一次「解锁重现后复核」行（窗口在不在、isHidden、windowScene、
/// frame），下次真机以主屏幕为准；若重现也不行，说明后台什么都恢复不了可见，
/// 那是下一件（SpringBoard 侧），不在这次里。
/// 幂等：锁屏瞬间误触发也无害（显示器灭着，重发设置不起作用；解锁通知来了再跑一次）。
- (void)unlockRestoreFloatingOverlay {
    // 1.0.5：普通签名兼容模式下不重现悬浮窗（只记一次，不让看门狗刷屏）。
    if (self.compatMode) {
        if (!self.compatSkipLogged) {
            self.compatSkipLogged = YES;
            [self log:@"诊断1.0.6 降级：普通签名兼容模式，跳过悬浮窗解锁重现（只走应用内歌词）"];
        }
        return;
    }
    // 用户关掉了悬浮窗：不恢复（尊重开关，与 rebuild 同款）。
    NSUserDefaults *prefs = [TLDSRuntime sharedDefaults];  // 1.0.5 bug 2：走 LyricStore.defaults
    BOOL enabled = [prefs objectForKey:@"floatingLyric.enabled"] == nil
                 ? YES : [prefs boolForKey:@"floatingLyric.enabled"];
    if (!enabled) {
        return;
    }
    if (!self.shellInitialized || !self.floatingSceneEverCreated) {
        // 场景一次都没建过：没有旧场景可重现；创建归 build 25 启动兜底管，
        // 这里不抢建（与 build 26 复核同款：只处理已建好的，不直接建）。
        [self log:@"诊断1.0.6 解锁重现：场景一次都没建过，无旧场景可重现（创建归启动兜底）"];
        return;
    }
    // 旧场景可用 = 场景对象在＋已完成连接＋窗口在。会话还在 openSessions 里是
    // 佐证（系统没回收），只记日志、不进判定——判定只认上面三项（连接过的
    // 场景，会话一定还在；反过来会话在、场景没连上，不能当可用）。
    BOOL sessionAlive = NO;
    for (UISceneSession *session in [UIApplication sharedApplication].openSessions) {
        if ([session.persistentIdentifier isEqualToString:self.floatingSceneIdentifier]) {
            sessionAlive = YES;
            break;
        }
    }
    if (self.floatingScene && self.floatingSceneCreated && self.floatingWindow) {
        [self log:[NSString stringWithFormat:@"诊断1.0.6 解锁重现：旧场景还在（标识 %@，会话在 openSessions：%@），重发 foreground 设置＋取消隐藏，不重建",
                   self.floatingSceneIdentifier ?: @"?",
                   sessionAlive ? @"是" : @"否"]];
        // 重现就是现成的 reactivate「场景还在」分支：重发 foreground 设置、
        // 重加 binder、取消隐藏窗口／视图。2 秒看门狗每轮也在做同一件事，
        // 重建以前是它先把旧场景销毁了才轮不到它；现在不重建，它每轮都是重现。
        [self reactivateFloatingOverlayWithTrigger:@"解锁重现"];
        // 重现后 2 秒记一次窗口状态：重现跑没跑、本地状态如何，下次真机好判断。
        // 本地状态好≠屏幕可见（老教训），只记事实，不下「可见」结论。
        __weak TLDSAppDelegate *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            __strong TLDSAppDelegate *strongSelf = weakSelf;
            if (!strongSelf) return;
            UIWindow *w = strongSelf.floatingWindow;
            NSString *state;
            if (!w) {
                state = @"窗口：未创建（重现后窗口丢了）";
            } else {
                state = [NSString stringWithFormat:@"窗口：已创建，isHidden=%@，alpha=%.2f，windowScene=%@，frame=%@",
                         w.isHidden ? @"YES" : @"NO", w.alpha,
                         w.windowScene ? @"非空" : @"空",
                         NSStringFromCGRect(w.frame)];
            }
            [strongSelf log:[NSString stringWithFormat:@"诊断1.0.6 解锁重现后复核：%@（本地状态≠屏幕可见，见主屏幕为准）", state]];
        });
        return;
    }
    [self log:[NSString stringWithFormat:@"诊断1.0.6 解锁重现：旧场景已不在（场景：%@，已连：%@，窗口：%@，会话在 openSessions：%@），走完整重建",
               self.floatingScene ? @"非空" : @"空",
               self.floatingSceneCreated ? @"YES" : @"NO",
               self.floatingWindow ? @"非空" : @"空",
               sessionAlive ? @"是" : @"否"]];
    [self rebuildFloatingOverlay];
}

#pragma mark - 完整重建（解锁恢复主力）

/// 解锁后调用：丢弃旧 scene / binder / window，走与首次启动完全一致的创建路径。
/// 相比只下发 updateSettings，重建能保证 SpringBoard 真正把 scene 呈现为前台。
- (void)rebuildFloatingOverlay {
    // 1.0.5：普通签名兼容模式下不再重建悬浮窗。
    if (self.compatMode) {
        if (!self.compatSkipLogged) {
            self.compatSkipLogged = YES;
            [self log:@"诊断1.0.6 降级：普通签名兼容模式，跳过悬浮窗重建（只走应用内歌词）"];
        }
        return;
    }
    if (!self.shellInitialized || !self.floatingSceneEverCreated) {
        return;
    }
    // 用户双击隐藏了悬浮窗 → 不要重建（尊重开关）
    NSUserDefaults *prefs = [TLDSRuntime sharedDefaults];  // 1.0.5 bug 2：走 LyricStore.defaults
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

    // 1.0.6（第 6／7 项跟进）：14:59:44 的教训——重建只隐藏旧窗、不销毁旧场景会话，
    // 结果建了第二个悬浮窗（TLDSFloatingLyric_1），旧窗还活着。
    // 这次先销毁旧场景会话再建新窗：binder 摘场景、窗口隐藏、系统销毁会话，
    // 每步都记日志；重建前后各记一次活着的悬浮场景数与标识。
    NSString *oldIdentifier = self.floatingSceneIdentifier ?: @"";
    [self logLiveFloatingScenesWithTag:@"重建前"];
    [self log:[NSString stringWithFormat:@"锁屏恢复：先销毁旧悬浮场景（标识 %@）", oldIdentifier]];
    UISceneSession *oldSession = nil;
    for (UISceneSession *session in [UIApplication sharedApplication].openSessions) {
        if ([session.persistentIdentifier isEqualToString:oldIdentifier]) {
            oldSession = session;
            break;
        }
    }
    // 1.0.6/build 21（重建竞态修）：只有旧场景曾经完成连接，才请求销毁旧会话。
    // 旧场景建了还没连上（正在连接窗口）时跳过销毁——只摘 binder＋藏窗口
    //（走 1.0.5 的做法），让正在连接的会话自然完成或被放弃，不要去销毁它。
    // 注意不能用 floatingSceneCreated 判断：它只表示「当前连着」，
    // 连上过、后来断开的场景也会是 NO——那一路（解锁重建、14:59:44 第二窗）
    // 必须照旧销毁，否则旧窗残留。
    if (oldSession && self.floatingSceneEverConnected) {
        __weak TLDSAppDelegate *weakSelf = self;
        [[UIApplication sharedApplication] requestSceneSessionDestruction:oldSession
                                                                  options:nil
                                                             errorHandler:^(NSError *error) {
            __strong TLDSAppDelegate *strongSelf = weakSelf;
            [strongSelf log:[NSString stringWithFormat:@"锁屏恢复：旧场景会话销毁失败：%@", error.localizedDescription ?: @"?"]];
        }];
        [self log:[NSString stringWithFormat:@"锁屏恢复：已请求销毁旧场景会话（标识 %@）", oldIdentifier]];
    } else if (oldSession) {
        [self log:[NSString stringWithFormat:@"锁屏恢复：跳过销毁旧场景会话（标识 %@）：旧场景尚未完成连接（竞态修），只摘 binder＋藏窗口，让它自然完成或被放弃", oldIdentifier]];
    } else {
        [self log:[NSString stringWithFormat:@"锁屏恢复：未找到旧场景会话（标识 %@，可能已由系统回收）", oldIdentifier]];
    }

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
        [self log:[NSString stringWithFormat:@"锁屏恢复：已从 binder 摘掉旧场景（标识 %@）", oldIdentifier]];
    }
    if (self.floatingWindow) {
        [self.floatingWindow setHidden:YES];
        self.floatingWindow = nil;
        [self log:[NSString stringWithFormat:@"锁屏恢复：旧悬浮窗口已隐藏（标识 %@）", oldIdentifier]];
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
    [self logLiveFloatingScenesWithTag:@"重建后"];
}

- (void)log:(NSString *)message {
    [[TLDSRuntime shared] logMessage:message];
}

#pragma mark - 1.0.5 后台挂起及恢复日志（第 6 项）＋ 1.0.6 终止原因（第 8 项）

- (void)tlds_logDidEnterBackground {
    // 1.0.6（第 8 项）：记下「进入后台」状态＋时间；下次启动时若没见到
    // WillTerminate，就知道上次是后台被杀（疑似系统／宿主终止，原因未知）。
    NSUserDefaults *prefs = [TLDSRuntime sharedDefaults];
    [prefs setObject:@"background" forKey:@"tlds.lastExitState"];
    [prefs setDouble:CFAbsoluteTimeGetCurrent() forKey:@"tlds.lastExitTime"];
    [self log:@"诊断1.0.6 后台：App 进入后台（悬浮窗若此时消失，先看是不是被挂起）"];
}

- (void)tlds_logWillResignActive {
    [self log:@"诊断1.0.6 后台：App 即将失去前台（WillResignActive）"];
}

- (void)tlds_logDidBecomeActive {
    [self log:@"诊断1.0.6 后台：App 回到前台（DidBecomeActive）"];
}

- (void)tlds_logWillTerminate {
    // 1.0.6（第 8 项）：记下「正常终止」——下次启动看到它，就知道上次
    // 是正常退出的；看不到它（且上次在后台），就是被系统／宿主杀了。
    NSUserDefaults *prefs = [TLDSRuntime sharedDefaults];
    [prefs setObject:@"terminated-clean" forKey:@"tlds.lastExitState"];
    [prefs setDouble:CFAbsoluteTimeGetCurrent() forKey:@"tlds.lastExitTime"];
    [self log:@"诊断1.0.6 后台：App 即将终止（WillTerminate）"];
}

/// 1.0.6（第 8 项）：系统内存警告——若随后进程消失，疑似 jetsam（内存杀），
/// 原因以日志为准，不编。UIApplicationDelegate 方法，系统直接调。
- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    [self log:@"诊断1.0.6 后台：收到内存警告（系统内存紧张；若随后进程消失，疑似 jetsam）"];
}

#pragma mark - 1.0.6 悬浮窗状态快照（第 7 项）＋活着的悬浮场景计数（第 6／7 项）

/// 记一次悬浮窗当前状态（窗口在不在、isHidden、windowScene、frame），
/// tag 是「激活前」／「激活成功后」。激活成功不应丢窗，两次快照对得上才算。
- (void)logFloatingWindowStateWithTag:(NSString *)tag {
    UIWindow *w = self.floatingWindow;
    NSString *state;
    if (!w) {
        state = @"窗口：尚未创建（场景未连上）";
    } else {
        state = [NSString stringWithFormat:@"窗口：已创建，isHidden=%@，windowScene=%@，frame=%@",
                 w.isHidden ? @"YES" : @"NO",
                 w.windowScene ? @"非空" : @"空",
                 NSStringFromCGRect(w.frame)];
    }
    [self log:[NSString stringWithFormat:@"诊断1.0.6 激活：%@——悬浮窗状态：%@（%@）",
               tag ?: @"?", state, [[TLDSRuntime shared] environmentTag]]];
}

/// Swift 侧 ActivationView 发来的快照通知（userInfo 带 tag）。
/// 「激活前」每进程只记一次（onAppear 会反复触发）。
- (void)tlds_logFloatingWindowStateNotification:(NSNotification *)note {
    NSString *tag = note.userInfo[@"tag"];
    if ([tag isEqualToString:@"激活前"] && self.activationPreStateLogged) {
        return;
    }
    if ([tag isEqualToString:@"激活前"]) {
        self.activationPreStateLogged = YES;
    }
    [self logFloatingWindowStateWithTag:tag];
}

/// 记当前活着的悬浮场景数与各自标识（openSessions 里 TLDSFloatingLyric 前缀的会话）。
- (void)logLiveFloatingScenesWithTag:(NSString *)tag {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (UISceneSession *session in [UIApplication sharedApplication].openSessions) {
        NSString *pid = session.persistentIdentifier ?: @"";
        if ([pid hasPrefix:@"TLDSFloatingLyric"]) {
            [ids addObject:pid];
        }
    }
    [self log:[NSString stringWithFormat:@"诊断1.0.6 悬浮窗：%@——当前活着的悬浮场景 %lu 个（标识：%@）",
               tag ?: @"?", (unsigned long)ids.count,
               ids.count > 0 ? [ids componentsJoinedByString:@"、"] : @"无"]];
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

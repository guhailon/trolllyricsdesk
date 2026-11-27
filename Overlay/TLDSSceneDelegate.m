#import "TLDSSceneDelegate.h"
#import "TLDSAppDelegate.h"
#import "TLDSPassThroughWindow.h"
#import "Private/UIKitPrivate.h"
#import "TrollLyricsDesk-Swift.h"

// 1.0.5 诊断（第 5 项）：场景连接计数——主界面／悬浮各连了几次。
static NSInteger TLDSMainSceneConnectCount = 0;
static NSInteger TLDSFloatingSceneConnectCount = 0;

@implementation TLDSSceneDelegate

- (void)scene:(UIScene *)scene
willConnectToSession:(UISceneSession *)session
     options:(UISceneConnectionOptions *)connectionOptions {

    if (![scene isKindOfClass:[UIWindowScene class]]) {
        return;
    }
    UIWindowScene *windowScene = (UIWindowScene *)scene;

    TLDSAppDelegate *appDelegate =
        (TLDSAppDelegate *)[UIApplication sharedApplication].delegate;

    NSString *identifier = session.persistentIdentifier ?: @"";
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier ?: @"";

    // ==== 会话路由 ====
    // 1) 主界面：persistentIdentifier == 包名（或首个非悬浮会话兜底）
    // 2) 悬浮歌词：持久标识以 TLDSFloatingLyric 开头（重建时会带序号后缀，
    //    用 hasPrefix 避免标识时序不一致导致悬浮 scene 被当成主界面忽略）
    BOOL isFloating = [identifier hasPrefix:@"TLDSFloatingLyric"] ||
                      [identifier isEqualToString:appDelegate.floatingSceneIdentifier];
    BOOL isMain = [identifier isEqualToString:bundleID];
    if (!isFloating && !isMain && !appDelegate.mainSceneConnected) {
        isMain = YES;   // 首个未知会话当主界面
    }

    // 1.0.5 三档模式：LiveContainer 宿主只有在「已判普通签名兼容」时才
    // 强制走主界面（没有悬浮歌词场景）。判定前是「待探测」，悬浮场景
    // 照常连接、等 AppDelegate 的托管复核定档；巨魔模式不受这分支影响。
    // 以前这里宿主一律强制 isMain，导致增强宿主永远验不出来。
    if ([[TLDSRuntime shared] isHosted] && appDelegate.compatMode) {
        isMain = YES;
        isFloating = NO;
    }

    if (isMain) {
        TLDSMainSceneConnectCount += 1;
        appDelegate.mainSceneConnected = YES;

        UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
        // 主界面 = 原有 SwiftUI ContentView（UIHostingController 承载）
        window.rootViewController = [[TLDSRuntime shared] makeRootViewController];
        self.window = window;
        appDelegate.window = window;
        [window makeKeyAndVisible];
        [appDelegate log:[NSString stringWithFormat:@"主界面场景已连接：%@（第 %ld 次）", identifier, (long)TLDSMainSceneConnectCount]];
        return;
    }

    // ==== 悬浮歌词场景 ====
    // 2.0.0：FrontBoard 悬浮场景已停用（见 docs/2.0.0-MERGE-DESIGN.md §6）。
    // 即使系统递来一个 TLDSFloatingLyric* 会话，也只记一行、不建窗口。
    // 悬浮歌词改由 HUD 守护进程显示。主界面分支不受影响。
    if (isFloating) {
        [appDelegate log:@"诊断2.0.0 FrontBoard 已停用：忽略悬浮场景会话"];
        return;
    }
    if (isFloating && !appDelegate.floatingSceneCreated) {
        TLDSFloatingSceneConnectCount += 1;
        appDelegate.floatingSceneCreated = YES;
        // 1.0.6/build 21：场景完成连接——重建竞态守卫的锚点（见 TLDSAppDelegate）。
        appDelegate.floatingSceneEverConnected = YES;

        // 宽度固定，高度只给一个紧凑初始值；实际高度由 FloatingLyricViewController
        // 按当前歌词实际换行行数动态计算（1 行 = 1 行高，2 行 = 2 行高，以此类推）。
        CGFloat screenWidth = windowScene.coordinateSpace.bounds.size.width;
        CGFloat width = MIN(screenWidth - 24, 420);
        CGRect frame = CGRectMake((screenWidth - width) / 2.0, 0, width, 60);

        TLDSPassThroughWindow *window =
            [[TLDSPassThroughWindow alloc] initWithWindowScene:windowScene];
        window.frame = frame;
        window.backgroundColor = [UIColor clearColor];
        window.windowLevel = 10000;

        FloatingLyricViewController *lyricVC = [FloatingLyricViewController new];
        window.rootViewController = lyricVC;
        self.window = window;
        appDelegate.floatingWindow = window;   // 锁屏解锁恢复时要用

        [window setHidden:NO];   // 悬浮窗不抢 keyWindow
        // 1.0.5（第 3 项）：创建时的窗口诊断——层级／透明度／隐藏状态的实际值。
        // 只打日志，不改行为；「已显示」这里只代表窗口建出来了，可见与否等复核。
        [appDelegate log:[NSString stringWithFormat:@"诊断1.0.6 场景：悬浮窗口已创建（第 %ld 次，标识 %@）：windowLevel=%.0f，alpha=%.2f，backgroundColor=%@，isHidden=%@，windowScene=%@，frame=%@（创建成功≠可见，等复核）",
                          (long)TLDSFloatingSceneConnectCount, identifier,
                          window.windowLevel, window.alpha,
                          window.backgroundColor ? @"已设置" : @"nil",
                          window.isHidden ? @"YES" : @"NO",
                          window.windowScene ? @"非空" : @"空",
                          NSStringFromCGRect(window.frame)]];
        [appDelegate log:@"悬浮歌词场景窗口已显示"];
        return;
    }

    [appDelegate log:[NSString stringWithFormat:@"忽略额外场景会话：%@", identifier]];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    TLDSAppDelegate *appDelegate =
        (TLDSAppDelegate *)[UIApplication sharedApplication].delegate;
    NSString *identifier = scene.session.persistentIdentifier ?: @"";
    if ([identifier hasPrefix:@"TLDSFloatingLyric"]) {
        appDelegate.floatingSceneCreated = NO;
        [appDelegate log:[NSString stringWithFormat:@"悬浮歌词场景断开：%@", identifier]];
    }
}

#pragma mark - 1.0.5 场景生命周期日志（第 6 项）

- (void)sceneDidBecomeActive:(UIScene *)scene {
    TLDSAppDelegate *appDelegate =
        (TLDSAppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate log:[NSString stringWithFormat:@"诊断1.0.6 后台：场景回到前台（DidBecomeActive）：%@",
                      scene.session.persistentIdentifier ?: @"?"]];
}

- (void)sceneWillResignActive:(UIScene *)scene {
    TLDSAppDelegate *appDelegate =
        (TLDSAppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate log:[NSString stringWithFormat:@"诊断1.0.6 后台：场景即将失去前台（WillResignActive）：%@",
                      scene.session.persistentIdentifier ?: @"?"]];
}

- (void)sceneDidEnterBackground:(UIScene *)scene {
    TLDSAppDelegate *appDelegate =
        (TLDSAppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate log:[NSString stringWithFormat:@"诊断1.0.6 后台：场景进入后台（DidEnterBackground）：%@",
                      scene.session.persistentIdentifier ?: @"?"]];
}

- (void)sceneWillEnterForeground:(UIScene *)scene {
    TLDSAppDelegate *appDelegate =
        (TLDSAppDelegate *)[UIApplication sharedApplication].delegate;
    [appDelegate log:[NSString stringWithFormat:@"诊断1.0.6 后台：场景即将进入前台（WillEnterForeground）：%@",
                      scene.session.persistentIdentifier ?: @"?"]];
}

@end

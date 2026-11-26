#import "TLDSSceneDelegate.h"
#import "TLDSAppDelegate.h"
#import "TLDSPassThroughWindow.h"
#import "Private/UIKitPrivate.h"
#import "TrollLyricsDesk-Swift.h"

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
    // 2) 悬浮歌词：持久标识 == TLDSFloatingLyric（或按创建顺序兜底）
    BOOL isFloating = [identifier isEqualToString:appDelegate.floatingSceneIdentifier];
    BOOL isMain = [identifier isEqualToString:bundleID];
    if (!isFloating && !isMain && !appDelegate.mainSceneConnected) {
        isMain = YES;   // 首个未知会话当主界面
    }

    #ifdef TLDS_LIVE_CONTAINER
    isMain = YES;
    isFloating = NO;
#endif
    if (isMain) {
        appDelegate.mainSceneConnected = YES;

        UIWindow *window = [[UIWindow alloc] initWithWindowScene:windowScene];
        // 主界面 = 原有 SwiftUI ContentView（UIHostingController 承载）
        window.rootViewController = [[TLDSRuntime shared] makeRootViewController];
        self.window = window;
        appDelegate.window = window;
        [window makeKeyAndVisible];
        [appDelegate log:[NSString stringWithFormat:@"主界面场景已连接：%@", identifier]];
        return;
    }

    // ==== 悬浮歌词场景 ====
    if (isFloating && !appDelegate.floatingSceneCreated) {
        appDelegate.floatingSceneCreated = YES;

        // 窗口尺寸 = 单行歌词（自适应换行，最多 3 行）+ 底部操作提示，高 118
        CGFloat screenWidth = windowScene.coordinateSpace.bounds.size.width;
        CGFloat width = MIN(screenWidth - 24, 420);
        CGRect frame = CGRectMake((screenWidth - width) / 2.0, 0, width, 118);

        TLDSPassThroughWindow *window =
            [[TLDSPassThroughWindow alloc] initWithWindowScene:windowScene];
        window.frame = frame;
        window.backgroundColor = [UIColor clearColor];
        window.windowLevel = 10000;

        FloatingLyricViewController *lyricVC = [FloatingLyricViewController new];
        window.rootViewController = lyricVC;
        self.window = window;

        [window setHidden:NO];   // 悬浮窗不抢 keyWindow
        [appDelegate log:@"悬浮歌词场景窗口已显示"];
        return;
    }

    [appDelegate log:[NSString stringWithFormat:@"忽略额外场景会话：%@", identifier]];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    TLDSAppDelegate *appDelegate =
        (TLDSAppDelegate *)[UIApplication sharedApplication].delegate;
    NSString *identifier = scene.session.persistentIdentifier ?: @"";
    if ([identifier isEqualToString:appDelegate.floatingSceneIdentifier]) {
        appDelegate.floatingSceneCreated = NO;
        [appDelegate log:@"悬浮歌词场景断开"];
    }
}

@end

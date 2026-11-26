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
    // 2) 悬浮歌词：持久标识以 TLDSFloatingLyric 开头（重建时会带序号后缀，
    //    用 hasPrefix 避免标识时序不一致导致悬浮 scene 被当成主界面忽略）
    BOOL isFloating = [identifier hasPrefix:@"TLDSFloatingLyric"] ||
                      [identifier isEqualToString:appDelegate.floatingSceneIdentifier];
    BOOL isMain = [identifier isEqualToString:bundleID];
    if (!isFloating && !isMain && !appDelegate.mainSceneConnected) {
        isMain = YES;   // 首个未知会话当主界面
    }

    // LiveContainer 宿主：只有一个主界面场景，没有悬浮歌词场景。
    if ([[TLDSRuntime shared] isHosted]) {
        isMain = YES;
        isFloating = NO;
    }

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

@end

// TLAppDelegate.mm — 普通模式 delegate 的实现。原创文件。
// 根视图控制器取自 Swift 工厂 TLAppRoot（ContentView 包在 UIHostingController 里）。
#import "TLAppDelegate.h"
#import "TrollLyricsDesk-Swift.h"

@implementation TLAppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    UIWindow *window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    window.rootViewController = [TLAppRoot makeRootViewController];
    [window makeKeyAndVisible];
    self.window = window;
    return YES;
}

@end

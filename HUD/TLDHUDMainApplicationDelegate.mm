// TLDHUDMainApplicationDelegate.mm
// HUD Test — one-time window registration. Adapted from TrollSpeed
// (MIT © 2023 Lessica), sources/TLDHUDMainApplicationDelegate.mm:36-62.
// The window is registered ONCE at daemon start and never re-registered
// or rebuilt afterwards — that is the whole point of this test.
// One deliberate change: the original calls registerWindowWithContextID:
// via NSInvocation; this calls the method directly (same method, same
// arguments, same effect). The hosting-controller class is resolved at
// runtime via objc_getClass, like the original — no link-time ObjC class
// symbol is needed, so the vendored SpringBoardServices.tbd only has to
// carry the two C functions we call.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import "TLDHUDMainApplicationDelegate.h"
#import "TLDHUDMainWindow.h"
#import "TLDHUDRootViewController.h"
#import "TLDHUDLog.h"
#import "SBSAccessibilityWindowHostingController.h"
#import "UIWindow+Private.h"
#import <objc/runtime.h>

@implementation TLDHUDMainApplicationDelegate {
    TLDHUDRootViewController *_rootViewController;
    SBSAccessibilityWindowHostingController *_windowHostingController;
}

- (instancetype)init
{
    if (self = [super init])
    {
        TLDHUDLog(@"hud: TLDHUDMainApplicationDelegate init");
    }
    return self;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary<UIApplicationLaunchOptionsKey, id> *)launchOptions
{
    TLDHUDLog(@"hud: didFinishLaunching");

    _rootViewController = [[TLDHUDRootViewController alloc] init];

    self.window = [[TLDHUDMainWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    [self.window setRootViewController:_rootViewController];

    [self.window setWindowLevel:10000010.0];
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    // TrollSpeed resolves the class at runtime via objc_getClass instead
    // of referencing it directly, so no ObjC class symbol is needed at
    // link time — the vendored SpringBoardServices.tbd only has to carry
    // the two C functions we call (SBSSpringBoardServerPort /
    // SBGetScreenLockStatus). The registration call itself is direct
    // (the original used NSInvocation; same method, same arguments).
    _windowHostingController = [[objc_getClass("SBSAccessibilityWindowHostingController") alloc] init];
    unsigned int contextId = [self.window _contextId];
    double windowLevel = [self.window windowLevel];
    [_windowHostingController registerWindowWithContextID:contextId atLevel:windowLevel];
    TLDHUDLog(@"hud: window registered contextId=%u level=%f", contextId, windowLevel);

    return YES;
}

@end

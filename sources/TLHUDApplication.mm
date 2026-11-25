// TLHUDApplication.mm — TLHUDApplication / TLHUDAppDelegate 的实现。
// 原创文件（TL_ 前缀，自有命名和注释）；机制照公开的上游做法：
// 手工接事件分发器、建全屏系统窗口、注册 backboardd 托管、监听歌词同步。
// 上游无许可证源码没有逐字复制。
#import "TLHUDApplication.h"
#import "TLHUDWindow.h"
#import "TLHelper.h"
#import "TLLyricsIPC.h"
#import "TLPrivate.h"
#import "TrollLyricsDesk-Swift.h"
#import <objc/runtime.h>

@interface TLHUDApplication ()
- (BOOL)tl_installEventSourcesFallback:(UIEventDispatcher *)dispatcher;
@end

@implementation TLHUDApplication

// 手工接 UIKit 事件的运行循环源 + fetcher。没走 UIApplicationMain，
// 所以没人替我们接上；不接 HUD 窗口收不到任何触摸。
- (instancetype)init {
    if ((self = [super init])) {
        UIEventDispatcher *dispatcher = [self valueForKey:@"eventDispatcher"];
        if (!dispatcher) return self;

        if ([dispatcher respondsToSelector:@selector(_installEventRunLoopSources:)]) {
            [dispatcher _installEventRunLoopSources:CFRunLoopGetMain()];
        } else {
            // 有些 iOS 版本把 _installEventRunLoopSources: 内联掉了，
            // 直接调不到，就去 -[UIApplication _run] 里扫描找它。
            [self tl_installEventSourcesFallback:dispatcher];
        }

        UIEventFetcher *fetcher = [[objc_getClass("UIEventFetcher") alloc] init];
        [dispatcher setValue:fetcher forKey:@"eventFetcher"];
        if ([fetcher respondsToSelector:@selector(setEventFetcherSink:)]) {
            [fetcher setEventFetcherSink:dispatcher];
        } else {
            [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];
        }

        // fetcher 也要挂到 app 自己身上——这一步才是真正从 backboardd
        // 打开 HID 流。漏了它，回调注册了也不会被叫到。
        [self setValue:fetcher forKey:@"eventFetcher"];
    }
    return self;
}

// 在 -[UIApplication _run] 的 ARM64 指令里找内联掉的安装函数。
// 找的是这段形状：mov x2, x0；mov x0, x?；bl <安装函数>；
// 安装函数开头是 cbz x0, ...。找到就签上名直接调。找不到返回 NO，
// 触摸就进不来（真机上以 _installEventRunLoopSources: 直接调成功为准）。
- (BOOL)tl_installEventSourcesFallback:(UIEventDispatcher *)dispatcher {
    IMP runIMP = class_getMethodImplementation([self class], @selector(_run));
    if (!runIMP) return NO;

    uint32_t *code = (uint32_t *)TLStripPAC((void *)runIMP);
    void (*installer)(id, SEL, CFRunLoopRef) = NULL;
    for (int i = 0; i < 0x140; i++) {
        if (code[i] != 0xaa0003e2) continue;                       // mov x2, x0
        if ((code[i + 1] & 0xff000000) != 0xaa000000) continue;   // mov x0, x?
        uint32_t bl = code[i + 2];
        if ((bl & 0xfc000000) != 0x94000000) continue;           // bl ?
        int32_t offset = (int32_t)(bl & 0x03ffffff);
        if (offset & 0x02000000) offset |= 0xfc000000;
        offset <<= 2;
        uint64_t target = (uint64_t)(&code[i + 2]) + offset;
        uint32_t first = *(uint32_t *)TLStripPAC((void *)target);
        if ((first & 0xff000000) != 0xb4000000) continue;        // cbz x0, ?
        installer = (void (*)(id, SEL, CFRunLoopRef))TLSignForCall((void *)target);
        break;
    }
    if (!installer) return NO;
    installer(dispatcher, @selector(_installEventRunLoopSources:), CFRunLoopGetMain());
    return YES;
}

@end

@implementation TLHUDAppDelegate {
    LyricsHUDController *_hud;
    SBSAccessibilityWindowHostingController *_hostingController;
}

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    _hud = [LyricsHUDController new];
    _hud.cardFrame = CGRectMake(30, 180, 300, 126);

    TLHUDWindow *w = [[TLHUDWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window = w;
    self.window.rootViewController = _hud;
    self.window.windowLevel = (UIWindowLevel)10000010.0;   // 在状态栏 / 弹窗之上
    self.window.backgroundColor = [UIColor clearColor];
    [self.window setHidden:NO];
    [self.window makeKeyAndVisible];

    // 关键一步：把渲染上下文 id 交给 backboardd 注册，窗口才能浮在
    // 所有 App 之上。windowLevel 只是层级参数，注册才是跨 App 的关键。
    Class hostCls = objc_getClass("SBSAccessibilityWindowHostingController");
    _hostingController = [[hostCls alloc] init];
    unsigned contextId = [self.window _contextId];
    double level = self.window.windowLevel;
    [_hostingController registerWindowWithContextID:contextId atLevel:level];

    // 关闭：主 App 发 dismiss 通知，HUD 自己淡出再退出。
    // block 在进程生命周期内一直持有，是故意的。
    UIWindow *window = self.window;
    [TLHelper observeNotification:TL_NOTIFY_DISMISS block:^{
        [UIView animateWithDuration:0.25 animations:^{
            window.alpha = 0.0;
        } completion:^(BOOL finished) {
            exit(0);
        }];
    }];

    // 歌词同步：主 App 每次切词写共享 plist + 发通知，这里读出来
    // 回主线程更新卡片（TLLyricsIPC 的回调本身已在主线程）。
    LyricsHUDController *hud = _hud;
    [TLLyricsIPC observeLyrics:^(NSDictionary *lyrics) {
        NSString *title = lyrics[@"title"] ?: @"";
        NSString *previous = lyrics[@"previous"] ?: @"";
        NSString *current = lyrics[@"current"] ?: @"";
        NSString *next = lyrics[@"next"] ?: @"";
        [hud updateWithTitle:title previous:previous current:current next:next];
    }];

    return YES;
}

@end

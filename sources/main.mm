// TrollLyricsDesk 程序入口（唯一入口）。
// 原创文件（TL_ 前缀，自有命名和注释）；机制照公开的上游做法：
// 同一个可执行文件分流两个运行模式，HUD 模式手工拉起 UIKit。
//   无参数  -> 普通 App（UIApplicationMain + TLAppDelegate）
//   -hud    -> 悬浮歌词 HUD 子进程（手工 UIKit 启动）
//   -exit   -> 杀掉正在跑的 HUD（stopHUD 的兜底）
//   -check  -> 退出码报告 HUD 是否在跑（1 = 在跑，0 = 没在跑）
// 上游无许可证源码没有逐字复制；不带 ImGui / HID 回调——
// 我们没有 ImGui，触摸走 TLHUDApplication 里接的事件分发器。
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import <signal.h>
#import <string.h>
#import <unistd.h>
#import "TLPrivate.h"
#import "TLHelper.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc <= 1) {
            return UIApplicationMain(argc, argv, nil, @"TLAppDelegate");
        }

        if (strcmp(argv[1], "-exit") == 0) {
            [TLHelper killHUDByPid];
            return EXIT_SUCCESS;
        }

        if (strcmp(argv[1], "-check") == 0) {
            // EXIT_FAILURE (1) = 在跑，EXIT_SUCCESS (0) = 没在跑。
            return [TLHelper isHUDRunningByPid] ? EXIT_FAILURE : EXIT_SUCCESS;
        }

        if (strcmp(argv[1], "-hud") == 0) {
            [TLHelper writePidFile];

            // 手工拉起 UIKit（不走 UIApplicationMain），backboardd 才能
            // 把我们的窗口托管到所有 App 之上。
            [UIScreen initialize];
            CFRunLoopGetCurrent();

            GSInitialize();
            BKSDisplayServicesStart();
            UIApplicationInitialize();

            UIApplicationInstantiateSingleton(objc_getClass("TLHUDApplication"));
            id delegate = [[objc_getClass("TLHUDAppDelegate") alloc] init];
            [UIApplication.sharedApplication setDelegate:delegate];
            [UIApplication.sharedApplication _accessibilityInit];

            if (@available(iOS 15.0, *)) {
                GSEventInitialize(0);
                GSEventPushRunLoopMode(kCFRunLoopDefaultMode);
            }

            [UIApplication.sharedApplication __completeAndRunAsPlugin];

            // SpringBoard 重启（respring）时自杀——启动器会把 HUD 带回来。
            static int bootToken;
            pid_t pid = getpid();
            notify_register_dispatch("SBSpringBoardDidLaunchNotification", &bootToken,
                                     dispatch_get_main_queue(), ^(int token) {
                notify_cancel(token);
                kill(pid, SIGKILL);
            });

            CFRunLoopRun();
            return EXIT_SUCCESS;
        }

        return EXIT_SUCCESS;
    }
}

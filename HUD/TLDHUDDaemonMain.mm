// TLDHUDDaemonMain.mm
// TrollLyricsDesk 2.0.1 — HUD daemon binary ONLY (helper inside the .app).
// Hand-initialized UIKit in -hud mode adapted from TrollSpeed
// (MIT © 2023 Lessica), sources/HUDApp.mm — one binary, daemon modes only:
//   -hud    -> HUD daemon: GSInitialize / BKSDisplayServicesStart /
//              UIApplicationInitialize / instantiate TLDHUDMainApplication /
//              _accessibilityInit / __completeAndRunAsPlugin / CFRunLoopRun
//   -check  -> exit 1 when the daemon is alive, 0 when it is not
//              (TrollSpeed's inverted semantics, kept on purpose)
//   -exit   -> SIGKILL the daemon via the PID file
//   -install-daemon -> (root) install the launchd plist, see TLDHUDHelper
// The HID event callback is the full TrollSpeed touch pipeline (2.0.5):
// TLDHIDEventCallback below — BKSHIDEventRegisterEventCallback,
// AXEventRepresentation decoding, pill-only gate, TSEventFetcher injection.
// (Adapted code, © 2026 顾海龙集团, MIT — see docs/2.0.0-MERGE-DESIGN.md;
// TrollSpeed parts © 2023 Lessica, MIT.)
// No no-arg mode: the main app has its own Overlay/main.m.
// (Adapted code, © 2026 顾海龙集团, MIT — see docs/2.0.0-MERGE-DESIGN.md.)

#import <notify.h>
#import <signal.h>
#import <limits.h>
#import <stdlib.h>
#import <unistd.h>
#import <sys/stat.h>
#import <sys/utsname.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

// 2.0.2: libproc.h 不在 iOS SDK 里（run 46109489987：'libproc.h' file
// not found）——proc_pidpath 是 libSystem 的导出函数，链接不缺，只缺
// 声明；这里前置声明（与 HUD/headers 里私有 API 的做法一致），
// 不丢 TLDHUDOwnPID 的校验。
// 注意：本文件是 Objective-C++（.mm），声明必须包 extern "C"，否则编
// 出 C++ 修饰名、链接时找不到 _proc_pidpath（run 46109630838 教训）。
extern "C" int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 1024
#endif

#import "TLDHUDLog.h"
#import "TLDHUDPaths.h"
#import "TLDHUDHelper.h"
#import "TLDHUDVersion.h"
#import "BackboardServices.h"
#import "AXEventRepresentation.h"
#import "TSEventFetcher.h"
#import "TLDHUDRootViewController.h"
#import "UIApplication+Private.h"

static BOOL TLDHUDOwnPID(pid_t pid) {
    if (pid <= 1 || pid == getpid()) return NO;
    char actual[PROC_PIDPATHINFO_MAXSIZE] = {0};
    if (proc_pidpath(pid, actual, sizeof(actual)) <= 0) return NO;
    char expected[PATH_MAX] = {0};
    char resolved[PATH_MAX] = {0};
    if (!realpath([TLDHUDHelperExecutablePath() fileSystemRepresentation], expected) ||
        !realpath(actual, resolved)) return NO;
    return strcmp(expected, resolved) == 0;
}

static int InstallDaemonPlist(void)
{
    NSString *templatePath = TLDHUDDaemonPlistTemplatePath();
    if (!templatePath) {
        TLDHUDLog(@"install-daemon: template TLDHUDDaemon.plist not found in bundle");
        return 1;
    }
    NSMutableDictionary *plist = [[NSMutableDictionary alloc] initWithContentsOfFile:templatePath];
    if (!plist) {
        TLDHUDLog(@"install-daemon: cannot read template %@", templatePath);
        return 1;
    }
    // Point the daemon at this exact binary: TrollStore may install the
    // .app anywhere, so the shipped path is only a placeholder.
    plist[@"ProgramArguments"] = @[ TLDHUDExecutablePath(), @"-hud" ];
    NSString *destPath = TLDHUDDaemonPlistPath();
    NSString *destDir = [destPath stringByDeletingLastPathComponent];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:destDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (![plist writeToFile:destPath atomically:YES]) {
        TLDHUDLog(@"install-daemon: cannot write %@", destPath);
        return 1;
    }
    chmod([destPath UTF8String], 0644);
    TLDHUDLog(@"install-daemon: wrote %@ (ProgramArguments[0]=%@)", destPath, TLDHUDExecutablePath());
    return 0;
}

// 2.0.5: FULL HID touch pipeline, ported from TrollSpeed (MIT © 2023
// Lessica), sources/HUDApp.mm:27-100 (_HUDEventCallback). Registration,
// AX decoding, phase mapping and the pointer-id clamp are TrollSpeed's;
// the PILL-ONLY gate inside the main-queue block is TLD's own safety
// rule, added on top of TrollSpeed (which injects whatever its window
// hit-tests). Safety, hard requirements:
//   - Only a touch point that falls inside the pill rect is injected;
//     everything else is passed through untouched — never swallowed,
//     never modified, never injected into another window.
//   - Injection goes only to the pill window's own view (keyView from
//     the pill window's hitTest), never to the system or another app.
//   - Two independent gates: (1) the window's own hitTest, which already
//     narrows to the pill (TLDHUDMainWindow.mm); (2) the pill frame from
//     the root view controller, compared by hand (no CoreGraphics in the
//     daemon — CGRectContainsPoint is an extern symbol there). Either
//     gate saying "outside" drops the event silently.
//   - Dragging is protected the same way as before: the 1s tick never
//     moves the pill while _dragging (TLDHUDRootViewController.mm).
// The hid-probe logging is kept: the first 10 events log a full
// CFCopyDescription each, after that at most one cumulative-count line
// per second, so a flood of HID events cannot spam the log file.
// TLDHUDLog is already thread-safe (@synchronized inside TLDHUDLog.mm),
// and the counter below has its own lock — the callback may run off the
// main thread.
static __used
NSString *TLDHIDDeviceModel(void) {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

static void TLDHIDEventCallback(void *target, void *refcon, IOHIDServiceRef service, IOHIDEventRef event)
{
    (void)target;
    (void)refcon;
    (void)service;
    static NSObject *probeLock = nil;
    static dispatch_once_t probeLockToken;
    dispatch_once(&probeLockToken, ^{ probeLock = [[NSObject alloc] init]; });
    static NSUInteger probeCount = 0;
    static NSTimeInterval lastCountLog = 0;
    static BOOL touchInjectLogged = NO;
    @synchronized (probeLock) {
        probeCount++;
        if (!event) {
            TLDHUDLog(@"hid: probe event %lu (null event)", (unsigned long)probeCount);
            return;
        }
        if (probeCount <= 10) {
            CFStringRef desc = CFCopyDescription((CFTypeRef)event);
            TLDHUDLog(@"hid: probe event %lu %@", (unsigned long)probeCount,
                      desc ? (__bridge NSString *)desc : @"(null description)");
            if (desc) CFRelease(desc);
        } else {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if (now - lastCountLog >= 1.0) {
                lastCountLog = now;
                TLDHUDLog(@"hid: probe count %lu", (unsigned long)probeCount);
            }
        }
    }
    if (!event) return;

    static UIApplication *app = [UIApplication sharedApplication];

    // iOS 15.1+ has a new API for handling HID events.
    if (@available(iOS 15.1, *)) {}
    else {
        [app _enqueueHIDEvent:event];
    }

    BOOL shouldUseAXEvent = YES;  // Always use AX events now...

    BOOL isExactly15 = NO;
    static NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
    if (version.majorVersion == 15 && version.minorVersion == 0 && version.patchVersion == 0) {
        NSString *deviceModel = TLDHIDDeviceModel();
        if (![deviceModel hasPrefix:@"iPhone13,"] && ![deviceModel hasPrefix:@"iPhone14,"]) { // iPhone 12 & 13 Series
            isExactly15 = YES;
        }
    }

    if (@available(iOS 15.0, *)) {
        shouldUseAXEvent = !isExactly15;
    } else {
        shouldUseAXEvent = NO;
    }

    if (shouldUseAXEvent)
    {
        static Class AXEventRepresentationCls = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/AccessibilityUtilities.framework"] load];
            AXEventRepresentationCls = objc_getClass("AXEventRepresentation");
        });

        AXEventRepresentation *rep = [AXEventRepresentationCls representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
        if (!rep) return;

        dispatch_async(dispatch_get_main_queue(), ^(void) {
            static UIWindow *keyWindow = nil;
            static dispatch_once_t onceToken;
            dispatch_once(&onceToken, ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                keyWindow = [[app windows] firstObject];
#pragma clang diagnostic pop
            });
            if (!keyWindow) return;
            CGPoint location = [rep location];

            // Gate 1: the pill window's own hitTest (narrows to the pill).
            UIView *keyView = [keyWindow hitTest:location withEvent:nil];
            if (!keyView) return;
            // Gate 2: the pill frame from the root view controller.
            UIViewController *rootVC = keyWindow.rootViewController;
            if (![rootVC respondsToSelector:@selector(pillFrameInWindow)]) return;
            CGRect pillFrame = [(TLDHUDRootViewController *)rootVC pillFrameInWindow];
            BOOL pillNotEmpty =
                pillFrame.size.width > 0 && pillFrame.size.height > 0;
            BOOL insidePill =
                location.x >= pillFrame.origin.x &&
                location.x < pillFrame.origin.x + pillFrame.size.width &&
                location.y >= pillFrame.origin.y &&
                location.y < pillFrame.origin.y + pillFrame.size.height;
            if (!pillNotEmpty || !insidePill) return;

            UITouchPhase phase = UITouchPhaseEnded;
            if ([rep isTouchDown])
                phase = UITouchPhaseBegan;
            else if ([rep isMove])
                phase = UITouchPhaseMoved;
            else if ([rep isCancel])
                phase = UITouchPhaseCancelled;
            else if ([rep isLift] || [rep isInRange] || [rep isInRangeLift])
                phase = UITouchPhaseEnded;

            NSInteger pointerId = [[[[rep handInfo] paths] firstObject] pathIdentity];
            if (pointerId > 0) {
                if (!touchInjectLogged) {
                    touchInjectLogged = YES;
                    TLDHUDLog(@"hid: touch in pill, injecting (phase %ld)", (long)phase);
                }
                [TSEventFetcher receiveAXEventID:MIN(MAX(pointerId, 1), 98) atGlobalCoordinate:location withTouchPhase:phase inWindow:keyWindow onView:keyView];
            }
        });
    }
}

int main(int argc, char *argv[])
{
    @autoreleasepool
    {
        // 2.0.0: this binary is the HUD daemon ONLY. There is no no-arg
        // main-app mode here (the main app has its own Overlay/main.m);
        // running it bare would have UIApplicationMain'd the wrong app.
        // Valid modes: -hud / -check / -exit / -install-daemon.
        if (argc <= 1) {
            TLDHUDLog(@"hud: no mode given (want -hud/-check/-exit/-install-daemon), version %@ build %@",
                      TLDHUD_VERSION_STRING, TLDHUD_BUILD_STRING);
            return EXIT_FAILURE;
        }

        NSString *pidPath = TLDHUDPIDPath();

        if (strcmp(argv[1], "-hud") == 0)
        {
            pid_t pid = getpid();
            TLDHUDLog(@"hud: start pid %d version %@ build %@", pid,
                      TLDHUD_VERSION_STRING, TLDHUD_BUILD_STRING);

            NSString *pidString = [NSString stringWithFormat:@"%d", pid];
            [pidString writeToFile:pidPath
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:nil];

            [UIScreen initialize];
            CFRunLoopGetCurrent();

            GSInitialize();
            BKSDisplayServicesStart();
            UIApplicationInitialize();

            UIApplicationInstantiateSingleton(objc_getClass("TLDHUDMainApplication"));
            static id<UIApplicationDelegate> appDelegate = [[objc_getClass("TLDHUDMainApplicationDelegate") alloc] init];
            [UIApplication.sharedApplication setDelegate:appDelegate];
            [UIApplication.sharedApplication _accessibilityInit];

            [NSRunLoop currentRunLoop];

            // 2.0.5: same spot as TrollSpeed's HUDApp.mm — register the
            // HID event callback right after the run loop is touched.
            // Full pipeline now: TLDHIDEventCallback decodes the AX
            // event and injects ONLY touches inside the pill rect
            // (TSEventFetcher); everything else passes through untouched.
            BKSHIDEventRegisterEventCallback(TLDHIDEventCallback);

            if (@available(iOS 15.0, *)) {
                GSEventInitialize(0);
                GSEventPushRunLoopMode(kCFRunLoopDefaultMode);
            }

            [UIApplication.sharedApplication __completeAndRunAsPlugin];

            static int springboardBootToken = 0;
            notify_register_dispatch("SBSpringBoardDidLaunchNotification", &springboardBootToken, dispatch_get_main_queue(), ^(int token) {
                notify_cancel(token);
                notify_post("com.ycwl.Lyrics.hud.dismissal");
                // Re-enable HUD after SpringBoard is launched.
                TLDHUDSetEnabled(YES);
                // Exit the current instance of HUD.
                kill(pid, SIGKILL);
            });

            CFRunLoopRun();
            return EXIT_SUCCESS;
        }
        else if (strcmp(argv[1], "-exit") == 0)
        {
            NSString *pidString = [NSString stringWithContentsOfFile:pidPath
                                                            encoding:NSUTF8StringEncoding
                                                               error:nil];
            if (pidString) {
                pid_t pid = (pid_t)[pidString intValue];
                if (!TLDHUDOwnPID(pid)) {
                    TLDHUDLog(@"hud: refusing stale or unverified PID %d", pid);
                    return EXIT_FAILURE;
                }
                kill(pid, SIGKILL);
                unlink([pidPath UTF8String]);
                TLDHUDLog(@"hud: -exit killed pid %d", pid);
            }
            return EXIT_SUCCESS;
        }
        else if (strcmp(argv[1], "-check") == 0)
        {
            NSString *pidString = [NSString stringWithContentsOfFile:pidPath
                                                            encoding:NSUTF8StringEncoding
                                                               error:nil];
            if (pidString) {
                pid_t pid = (pid_t)[pidString intValue];
                if (!TLDHUDOwnPID(pid)) return EXIT_SUCCESS;
                int killed = kill(pid, 0);
                return (killed == 0 ? EXIT_FAILURE : EXIT_SUCCESS);
            }
            else return EXIT_SUCCESS;  // No PID file, so HUD is not running
        }
        else if (strcmp(argv[1], "-install-daemon") == 0)
        {
            return InstallDaemonPlist();
        }
    }
    return EXIT_SUCCESS;
}

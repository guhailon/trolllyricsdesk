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
#import <math.h>
#import <fcntl.h>
#import <sys/file.h>

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
    // 2.0.7: drag latch (see the main-queue block below). Only the
    // main-queue block reads/writes these, so no lock is needed.
    static NSInteger activeDragPointerId = 0;
    static NSUInteger dragInjectCount = 0;
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

    UIApplication *app = [UIApplication sharedApplication];
    if (!app) return;

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

        if (![AXEventRepresentationCls respondsToSelector:@selector(representationWithHIDEvent:hidStreamIdentifier:)]) return;
        AXEventRepresentation *rep = [AXEventRepresentationCls representationWithHIDEvent:event hidStreamIdentifier:@"UIApplicationEvents"];
        if (!rep) return;

        dispatch_async(dispatch_get_main_queue(), ^(void) {
            UIWindow *keyWindow = [app.delegate respondsToSelector:@selector(window)] ? [app.delegate window] : nil;
            if (!keyWindow || keyWindow.hidden || !keyWindow.rootViewController) return;
            CGPoint location = [rep location];
            if (!isfinite(location.x) || !isfinite(location.y)) return;

            // 2.0.7: phase + pointerId FIRST — the drag latch below
            // needs them before either gate runs. (ChatGPT's HID
            // safety checks stay: unknown phases and out-of-range
            // ids are refused, never injected.)
            UITouchPhase phase = UITouchPhaseEnded;
            BOOL phaseKnown = YES;
            if ([rep isTouchDown])
                phase = UITouchPhaseBegan;
            else if ([rep isMove])
                phase = UITouchPhaseMoved;
            else if ([rep isCancel])
                phase = UITouchPhaseCancelled;
            else if ([rep isLift] || [rep isInRange] || [rep isInRangeLift])
                phase = UITouchPhaseEnded;
            else
                phaseKnown = NO;

            NSInteger pointerId = [[[[rep handInfo] paths] firstObject] pathIdentity];
            if (pointerId <= 0 || pointerId > 98) return;

            UIViewController *rootVC = keyWindow.rootViewController;

            // 2.0.7: drag latch (root cause #1 — hidden_files/
            // REPORT_2.0.7_DRAG_DIAGNOSIS.md). Once a Began passed
            // both gates and was injected, later events from the SAME
            // finger skip the gates: the pill always lags the finger
            // by a full pipeline, so re-testing every Moved against
            // the pill's CURRENT rect drops the drag the moment the
            // finger outruns the pill. The latch only ever applies to
            // the one finger that already passed the gates once;
            // every other touch still goes through both gates below,
            // and touches outside the pill are still dropped, never
            // swallowed.
            if (pointerId == activeDragPointerId) {
                // View for the fetcher: for a latched drag the touch
                // already exists (created at Began), so this is only
                // a fallback — hitTest may return nil once the finger
                // has left the pill.
                UIView *injectView = [keyWindow hitTest:location withEvent:nil];
                if (!injectView) injectView = rootVC.view;
                if (!phaseKnown) {
                    // Unmappable phase mid-drag: end the drag cleanly
                    // instead of leaving the latch (and the pill's
                    // _dragging) stuck forever.
                    [TSEventFetcher receiveAXEventID:pointerId atGlobalCoordinate:location withTouchPhase:UITouchPhaseCancelled inWindow:keyWindow onView:injectView];
                    activeDragPointerId = 0;
                    TLDHUDLog(@"hid: drag latch cleared (unknown phase)");
                    return;
                }
                if (phase == UITouchPhaseBegan) {
                    // Re-Began on a latched finger: the previous drag
                    // never ended. Cancel it, then fall through to the
                    // gates as a fresh touch.
                    [TSEventFetcher receiveAXEventID:pointerId atGlobalCoordinate:location withTouchPhase:UITouchPhaseCancelled inWindow:keyWindow onView:injectView];
                    activeDragPointerId = 0;
                    TLDHUDLog(@"hid: drag latch cleared (re-began)");
                } else {
                    [TSEventFetcher receiveAXEventID:pointerId atGlobalCoordinate:location withTouchPhase:phase inWindow:keyWindow onView:injectView];
                    // Throttled drag log: every 50th injected drag
                    // event, so a real drag shows a live count without
                    // spamming the log file.
                    dragInjectCount++;
                    if (dragInjectCount % 50 == 0) {
                        TLDHUDLog(@"hid: drag inject count %lu (pointer %ld)",
                                  (unsigned long)dragInjectCount, (long)pointerId);
                    }
                    if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) {
                        activeDragPointerId = 0;
                        TLDHUDLog(@"hid: drag latch cleared (phase %ld)", (long)phase);
                    }
                    return;
                }
            }
            if (!phaseKnown) return;

            // Gate 1: the pill window's own hitTest (narrows to the pill).
            UIView *keyView = [keyWindow hitTest:location withEvent:nil];
            if (!keyView) return;
            // Gate 2: the pill frame from the root view controller.
            // 2.0.7: hit rect is the pill rect expanded ~20pt on every
            // side — the gate tests the finger's centroid, not its
            // contact area, and a small pill is easy to miss at the
            // edges. Appearance unchanged.
            if (![rootVC respondsToSelector:@selector(pillFrameInWindow)]) return;
            CGRect pillFrame = [(TLDHUDRootViewController *)rootVC pillFrameInWindow];
            BOOL pillNotEmpty =
                pillFrame.size.width > 0 && pillFrame.size.height > 0;
            CGFloat pad = 20.0;
            BOOL insidePill =
                location.x >= pillFrame.origin.x - pad &&
                location.x < pillFrame.origin.x + pillFrame.size.width + pad &&
                location.y >= pillFrame.origin.y - pad &&
                location.y < pillFrame.origin.y + pillFrame.size.height + pad;
            if (!pillNotEmpty || !insidePill) {
                // Safety net for the latch: a drag whose finger left
                // the pill gets a Cancelled instead of a silent drop,
                // so handlePillPan can clear _dragging and save the
                // position. (Normally unreachable — latched events
                // return above — but cheap insurance.)
                if (pointerId == activeDragPointerId) {
                    [TSEventFetcher receiveAXEventID:pointerId atGlobalCoordinate:location withTouchPhase:UITouchPhaseCancelled inWindow:keyWindow onView:keyView];
                    activeDragPointerId = 0;
                    TLDHUDLog(@"hid: drag latch cleared (gate drop)");
                }
                return;
            }

            if (!touchInjectLogged) {
                touchInjectLogged = YES;
                TLDHUDLog(@"hid: touch in pill, injecting (phase %ld)", (long)phase);
            }
            [TSEventFetcher receiveAXEventID:pointerId atGlobalCoordinate:location withTouchPhase:phase inWindow:keyWindow onView:keyView];
            if (phase == UITouchPhaseBegan) {
                activeDragPointerId = pointerId;
                TLDHUDLog(@"hid: drag latch set (pointer %ld)", (long)pointerId);
            } else if ((phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled) &&
                       pointerId == activeDragPointerId) {
                activeDragPointerId = 0;
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
            // Root-owned lock in the root home directory; held for process lifetime.
            NSString *lockPath = @"/var/root/com.ycwl.Lyrics.hud.lock";
            int lockFD = open(lockPath.fileSystemRepresentation, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
            if (lockFD < 0 || flock(lockFD, LOCK_EX | LOCK_NB) != 0) {
                if (lockFD >= 0) close(lockFD);
                TLDHUDLog(@"hud: singleton lock unavailable errno=%d", errno);
                return EXIT_FAILURE;
            }
            pid_t pid = getpid();
            TLDHUDLog(@"hud: start pid %d version %@ build %@", pid,
                      TLDHUD_VERSION_STRING, TLDHUD_BUILD_STRING);

            NSString *pidString = [NSString stringWithFormat:@"%d", pid];
            if (![pidString writeToFile:pidPath
                        atomically:YES
                          encoding:NSUTF8StringEncoding
                             error:nil]) {
                TLDHUDLog(@"hud: PID file write failed");
                return EXIT_FAILURE;
            }

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

            // Main-loop heartbeat: diagnostic only, not proof of on-screen visibility.
            static NSTimer *heartbeat;
            heartbeat = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(NSTimer *timer) {
                TLDHUDLog(@"hud: heartbeat pid=%d uptime=%.1f", pid, NSProcessInfo.processInfo.systemUptime);
            }];
            static int springboardBootToken = 0;
            notify_register_dispatch("SBSpringBoardDidLaunchNotification", &springboardBootToken, dispatch_get_main_queue(), ^(int token) {
                notify_cancel(token);
                notify_post("com.ycwl.Lyrics.hud.dismissal");
                // launchd KeepAlive restarts managed instances. Never unload our own job.
                // Direct instances require manual re-enable; log this explicitly.
                TLDHUDLog(@"hud: SpringBoard relaunched; exiting for managed restart (direct mode requires re-enable)");
                exit(EXIT_FAILURE);
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
                if (kill(pid, SIGKILL) != 0) {
                    TLDHUDLog(@"hud: stop failed errno=%d", errno);
                    return EXIT_FAILURE;
                }
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

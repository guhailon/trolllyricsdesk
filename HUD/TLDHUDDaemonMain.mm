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
// The HID event callback in the original is NOT copied (v1: no touch).
// No no-arg mode: the main app has its own Overlay/main.m.
// (Adapted code, © 2026 顾海龙集团, MIT — see docs/2.0.0-MERGE-DESIGN.md.)

#import <notify.h>
#import <signal.h>
#import <libproc.h>
#import <limits.h>
#import <stdlib.h>
#import <unistd.h>
#import <sys/stat.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>

#import "TLDHUDLog.h"
#import "TLDHUDPaths.h"
#import "TLDHUDHelper.h"
#import "TLDHUDVersion.h"
#import "BackboardServices.h"
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

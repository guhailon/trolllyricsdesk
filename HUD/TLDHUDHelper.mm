// TLDHUDHelper.mm
// HUD Test — daemon enable/disable.
// Spawn mechanism adapted from TrollSpeed (MIT © 2023 Lessica),
// sources/TLDHUDHelper.mm. Differences from the original, all deliberate:
//   - bundle ID / paths are com.ycwl.Lyrics.hud (see TLDHUDPaths);
//   - the daemon plist is NOT shipped by a .deb installer: this IPA
//     installs it itself via a root-spawned "-install-daemon" run of
//     this same binary, which rewrites ProgramArguments[0] to the real
//     executable path (TrollStore may place the .app anywhere);
//   - launchctl is resolved at runtime (/var/jb/usr/bin first) instead
//     of assuming a fixed JBROOT path;
//   - no user-defaults / prefs helpers (v1 has no settings to sync).
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import <spawn.h>
#import <notify.h>
#import <string.h>
#import <errno.h>
#import <mach-o/dyld.h>
#import <sys/wait.h>
#import <signal.h>
#import <unistd.h>

#import "TLDHUDHelper.h"
#import "TLDHUDPaths.h"
#import "TLDHUDLog.h"

extern "C" char **environ;

#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern "C" int posix_spawnattr_set_persona_np(const posix_spawnattr_t* __restrict, uid_t, uint32_t);
extern "C" int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t* __restrict, uid_t);
extern "C" int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t* __restrict, uid_t);

#define FADE_OUT_DURATION 0.25
#define NOTIFY_DISMISSAL_HUD "com.ycwl.Lyrics.hud.dismissal"

/// Spawn a process as root (persona uid 0), like TrollSpeed does.
/// When wait is YES, blocks until the child exits and returns its exit
/// status (or -1 on spawn error); otherwise returns 0 and does not wait.
static int TLDHUDSpawnAsRoot(const char *path, char *const args[], BOOL wait)
{
    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
#if !TARGET_OS_SIMULATOR
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif
    pid_t task_pid = 0;
    int rc = posix_spawn(&task_pid, path, NULL, &attr, args, environ);
    posix_spawnattr_destroy(&attr);
    if (rc != 0) {
        TLDHUDLog(@"main: posix_spawn %@ failed: %s", @(path), strerror(rc));
        return -1;
    }
    if (!wait) {
        int unused = 0;
        waitpid(task_pid, &unused, WNOHANG);
        return 0;
    }
    // Wait for the child, retrying on EINTR (a signal must not spin us).
    int status = 0;
    pid_t w = 0;
    NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 8.0;
    do {
        w = waitpid(task_pid, &status, WNOHANG);
        if (w == task_pid || (w < 0 && errno != EINTR)) break;
        if (NSProcessInfo.processInfo.systemUptime >= deadline) {
            TLDHUDLog(@"main: command timeout pid %d", task_pid);
            kill(task_pid, SIGKILL);
            // Reap asynchronously; never wait indefinitely on the caller.
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                int ignored; while (waitpid(task_pid, &ignored, 0) < 0 && errno == EINTR) {}
            });
            return -1;
        }
        [NSThread sleepForTimeInterval:0.05];
    } while (YES);
    if (w != -1 && WIFEXITED(status)) {
        TLDHUDLog(@"main: spawned %@ pid %d exit %d", @(path), task_pid, WEXITSTATUS(status));
        return WEXITSTATUS(status);
    }
    TLDHUDLog(@"main: waitpid for %@ pid %d failed: %s", @(path), task_pid, strerror(errno));
    return -1;
}

/// Spawn the helper binary with one argument, as root, and wait for it.
/// (2.0.0: TLDHUDHelperExecutablePath, NOT this process's own path —
///  in the main app _NSGetExecutablePath is TrollLyricsDesk itself.)
static int TLDHUDSpawnSelfAsRoot(const char *arg)
{
    NSString *exe = TLDHUDHelperExecutablePath();
    char *args[] = { (char *)[exe UTF8String], (char *)arg, NULL };
    return TLDHUDSpawnAsRoot([exe UTF8String], args, YES);
}

BOOL TLDHUDIsEnabled(void)
{
    NSString *exe = TLDHUDHelperExecutablePath();
    char *args[] = { (char *)[exe UTF8String], (char *)"-check", NULL };
    int status = TLDHUDSpawnAsRoot([exe UTF8String], args, YES);
    if (status < 0) return NO;
    // -check exits EXIT_FAILURE (1) when the daemon is alive, EXIT_SUCCESS
    // (0) when it is not — same inverted semantics as TrollSpeed.
    return status == 1;
}

/// Install the daemon plist (as root). Returns YES on success.
static BOOL TLDHUDInstallDaemonPlist(void)
{
    int rc = TLDHUDSpawnSelfAsRoot("-install-daemon");
    return rc == 0;
}

static void TLDHUDSetEnabledLocked(BOOL isEnabled)
{
    if (isEnabled && TLDHUDIsEnabled()) return;
    notify_post(NOTIFY_DISMISSAL_HUD);
    NSString *plistPath = TLDHUDDaemonPlistPath();
    NSString *launchctl = TLDHUDLaunchctlPath();

    if (isEnabled) {
        // 0.2.1: ALWAYS rewrite the daemon plist on Enable. The old
        // "install only if missing" rule left a stale plist behind after
        // a TrollStore reinstall (container UUID changed, so the old
        // ProgramArguments[0] pointed at a binary that no longer exists;
        // launchctl load still exits 0 without ever starting it).
        // Rewriting is idempotent: same path in, same plist out.
        NSString *oldArg0 = nil;
        NSDictionary *oldPlist = [[NSDictionary alloc] initWithContentsOfFile:plistPath];
        NSArray *oldArgs = oldPlist[@"ProgramArguments"];
        if ([oldArgs isKindOfClass:[NSArray class]] && oldArgs.count > 0 &&
            [oldArgs[0] isKindOfClass:[NSString class]]) {
            oldArg0 = oldArgs[0];
        }
        NSString *exePath = TLDHUDHelperExecutablePath();
        TLDHUDLog(@"main: daemon plist ProgramArguments[0] old=%@ new=%@",
               oldArg0 ?: @"(no old plist / unreadable)", exePath);
        TLDHUDLog(@"main: rewriting daemon plist (always on Enable) old=%@ -> new=%@",
               oldArg0 ?: @"(no old plist / unreadable)", exePath);
        BOOL installed = TLDHUDInstallDaemonPlist();
        if (!installed) {
            TLDHUDLog(@"main: daemon plist install FAILED, falling back to direct spawn");
        }
        if (installed && [[NSFileManager defaultManager] fileExistsAtPath:plistPath] && launchctl) {
            // launchd may still hold the old job from the stale plist:
            // unload first (best-effort, rc ignored), then load.
            char *unloadArgs[] = { (char *)[launchctl UTF8String], (char *)"unload", (char *)[plistPath UTF8String], NULL };
            int unloadRc = TLDHUDSpawnAsRoot([launchctl UTF8String], unloadArgs, YES);
            TLDHUDLog(@"main: launchctl unload (best-effort before reload) rc %d", unloadRc);
            char *args[] = { (char *)[launchctl UTF8String], (char *)"load", (char *)[plistPath UTF8String], NULL };
            int loadRc = TLDHUDSpawnAsRoot([launchctl UTF8String], args, YES);
            TLDHUDLog(@"main: launchctl load %@ rc %d", plistPath, loadRc);
            if (loadRc != 0) return;
            // Give launchd a moment to start the daemon, then say so
            // plainly either way. This blocks the caller for 3s: the
            // Enable button calls TLDHUDSetEnabled on a background queue,
            // and the SpringBoard-relaunch path only delays killing the
            // old instance by 3s — both acceptable (see docs/RUN_0.2.1.md).
            [NSThread sleepForTimeInterval:3.0];
            if (TLDHUDIsEnabled()) {
                TLDHUDLog(@"main: daemon started after launchctl load (3s check)");
            } else {
                TLDHUDLog(@"main: daemon did not start after launchctl load (3s check)");
            }
            return;
        }
        // Fallback (same as TrollSpeed when there is no plist): spawn -hud
        // directly as root. No launchd KeepAlive in this mode — if the
        // daemon dies it stays dead until re-enabled. See TESTING.md.
        if (!launchctl) TLDHUDLog(@"main: no launchctl found, direct -hud spawn");
        NSString *exe = TLDHUDHelperExecutablePath();
        posix_spawnattr_t attr;
        posix_spawnattr_init(&attr);
#if !TARGET_OS_SIMULATOR
        posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
        posix_spawnattr_set_persona_uid_np(&attr, 0);
        posix_spawnattr_set_persona_gid_np(&attr, 0);
#endif
        posix_spawnattr_setpgroup(&attr, 0);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
        pid_t task_pid = 0;
        char *args[] = { (char *)[exe UTF8String], (char *)"-hud", NULL };
        int rc = posix_spawn(&task_pid, [exe UTF8String], NULL, &attr, args, environ);
        posix_spawnattr_destroy(&attr);
        if (rc != 0) {
            TLDHUDLog(@"main: direct -hud spawn failed: %s", strerror(rc));
            return;
        }
        TLDHUDLog(@"main: spawned -hud pid %d (direct, no launchd)", task_pid);
        int unused = 0;
        waitpid(task_pid, &unused, WNOHANG);
        return;
    }

    // Disable.
    [NSThread sleepForTimeInterval:FADE_OUT_DURATION];
    if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath] && launchctl) {
        char *args[] = { (char *)[launchctl UTF8String], (char *)"unload", (char *)[plistPath UTF8String], NULL };
        int rc = TLDHUDSpawnAsRoot([launchctl UTF8String], args, YES);
        TLDHUDLog(@"main: launchctl unload %@ rc %d", plistPath, rc);
        if (rc == 0 && !TLDHUDIsEnabled()) return;
    }
    int rc = TLDHUDSpawnSelfAsRoot("-exit");
    TLDHUDLog(@"main: -exit spawn rc %d", rc);
}

void TLDHUDSetEnabled(BOOL isEnabled) {
    static NSObject *lock; static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    @synchronized(lock) { TLDHUDSetEnabledLocked(isEnabled); }
}

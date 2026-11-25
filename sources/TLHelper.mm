// TLHelper.mm — TLHelper 的实现。
// 原创文件（TL_ 前缀，自有命名和注释）；机制照公开的上游做法：
// 同一个可执行文件以 "-hud" 参数重起自己当 HUD 子进程，共享 plist +
// Darwin 通知跨进程同步，pid 文件判断存活。上游无许可证源码没有逐字复制。
#import "TLHelper.h"
#import "TLPrivate.h"
#import <spawn.h>
#import <signal.h>
#import <sys/wait.h>
#import <errno.h>
#import <unistd.h>

extern char **environ;

@implementation TLHelper

#pragma mark - 共享配置（TL_LYRICS_PATH）

+ (NSMutableDictionary *)tl_loadPrefs {
    NSMutableDictionary *d =
        [NSMutableDictionary dictionaryWithContentsOfFile:@(TL_LYRICS_PATH)];
    return d ?: [NSMutableDictionary dictionary];
}

+ (id)tl_valueForKey:(NSString *)key {
    return [self tl_loadPrefs][key];
}

+ (void)setObject:(id)value forKey:(NSString *)key {
    NSMutableDictionary *d = [self tl_loadPrefs];
    if (value) d[key] = value; else [d removeObjectForKey:key];
    [d writeToFile:@(TL_LYRICS_PATH) atomically:YES];
}

+ (void)removeObjectForKey:(NSString *)key {
    NSMutableDictionary *d = [self tl_loadPrefs];
    [d removeObjectForKey:key];
    [d writeToFile:@(TL_LYRICS_PATH) atomically:YES];
}

+ (BOOL)boolForKey:(NSString *)key defaultValue:(BOOL)def {
    id v = [self tl_valueForKey:key];
    return v ? [v boolValue] : def;
}

+ (double)doubleForKey:(NSString *)key defaultValue:(double)def {
    id v = [self tl_valueForKey:key];
    return v ? [v doubleValue] : def;
}

+ (NSInteger)integerForKey:(NSString *)key defaultValue:(NSInteger)def {
    id v = [self tl_valueForKey:key];
    return v ? [v integerValue] : def;
}

+ (NSString *)stringForKey:(NSString *)key defaultValue:(NSString *)def {
    id v = [self tl_valueForKey:key];
    return [v isKindOfClass:[NSString class]] ? v : def;
}

#pragma mark - Darwin 通知

+ (void)postNotification:(const char *)name {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8),
        NULL, NULL, YES);
}

// 和 TLLyricsIPC 里的回调一样：observer 是 __bridge_retained 的 block
// 副本，进程生命周期内一直持有，是故意的。
static void TL_HelperNotifyCallback(CFNotificationCenterRef center,
                                    void *observer,
                                    CFStringRef name,
                                    const void *object,
                                    CFDictionaryRef userInfo) {
    dispatch_block_t block = (__bridge dispatch_block_t)observer;
    if (block) block();
}

+ (void)observeNotification:(const char *)name block:(dispatch_block_t)block {
    dispatch_block_t copied = [block copy];
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge_retained void *)copied,
        TL_HelperNotifyCallback,
        CFStringCreateWithCString(NULL, name, kCFStringEncodingUTF8),
        NULL, CFNotificationSuspensionBehaviorCoalesce);
}

#pragma mark - HUD 生命周期

+ (pid_t)tl_readPid {
    NSString *s = [NSString stringWithContentsOfFile:@(TL_PID_PATH)
                                            encoding:NSUTF8StringEncoding
                                               error:nil];
    return (pid_t)s.intValue;
}

+ (const char *)tl_executablePath {
    return [[[NSBundle mainBundle] executablePath] fileSystemRepresentation];
}

// 注意：绝不以 root 身份 spawn。root 进程的窗口照样能被托管显示，
// 但 backboardd 不会把 HID 触摸流交给它——HUD 看得见、点不动。
// 主 App 和 HUD 都以普通 mobile 身份跑，触摸才进得来。
+ (pid_t)tl_spawnSelfWithArg:(const char *)arg
                     setPgrp:(BOOL)setPgrp
                 waitForExit:(BOOL)waitForExit
                  exitStatus:(int *)exitStatus {
    const char *path = [self tl_executablePath];
    if (!path) return -1;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    if (setPgrp) {
        posix_spawnattr_setpgroup(&attr, 0);
        posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETPGROUP);
    }

    pid_t pid = -1;
    const char *args[] = { path, arg, NULL };
    int rc = posix_spawn(&pid, path, NULL, &attr, (char **)args, environ);
    posix_spawnattr_destroy(&attr);
    if (rc != 0) return -1;

    if (waitForExit) {
        int status = 0;
        while (waitpid(pid, &status, 0) == -1 && errno == EINTR) {}
        if (exitStatus) *exitStatus = WIFEXITED(status) ? WEXITSTATUS(status) : -1;
    }
    return pid;
}

+ (BOOL)isHUDRunningByPid {
    pid_t pid = [self tl_readPid];
    if (pid <= 0) return NO;
    return (kill(pid, 0) == 0);
}

+ (BOOL)isHUDRunning {
    // 问一次短命的 "-check" 子进程，比自己跨启动上下文 kill(pid, 0)
    // 更稳；子进程起不来就退回直接读 pid 文件。
    int status = 0;
    pid_t pid = [self tl_spawnSelfWithArg:"-check"
                                  setPgrp:NO
                              waitForExit:YES
                               exitStatus:&status];
    if (pid < 0) return [self isHUDRunningByPid];
    return status != 0;   // -check 在跑时返回 EXIT_FAILURE (1)
}

+ (void)writePidFile {
    NSString *s = [NSString stringWithFormat:@"%d", getpid()];
    [s writeToFile:@(TL_PID_PATH)
        atomically:YES
          encoding:NSUTF8StringEncoding
             error:nil];
}

+ (void)startHUD {
    if ([self isHUDRunning]) return;
    [self tl_spawnSelfWithArg:"-hud"
                      setPgrp:YES
                  waitForExit:NO
                   exitStatus:NULL];
}

+ (void)stopHUD {
    // HUD 收到通知自己淡出退出。
    [self postNotification:TL_NOTIFY_DISMISS];
    // 兜底：0.6 秒后还没退就跑一次 "-exit" 直接杀。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self tl_spawnSelfWithArg:"-exit"
                          setPgrp:NO
                      waitForExit:YES
                       exitStatus:NULL];
    });
}

+ (void)killHUDByPid {
    pid_t pid = [self tl_readPid];
    if (pid > 0) kill(pid, SIGKILL);
    unlink(TL_PID_PATH);
}

@end

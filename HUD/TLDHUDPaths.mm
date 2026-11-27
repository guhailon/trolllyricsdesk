// TLDHUDPaths.mm
// HUD Test — rootless-aware paths. (New code, © 2026 顾海龙集团, MIT.)

#import "TLDHUDPaths.h"
#import <mach-o/dyld.h>

NSString *TLDHUDJBRoot(void)
{
    static NSString *root = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        root = [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"] ? @"/var/jb" : @"";
    });
    return root;
}

NSString *TLDHUDDaemonPlistPath(void)
{
    return [TLDHUDJBRoot() stringByAppendingString:@"/Library/LaunchDaemons/com.ycwl.Lyrics.hud.plist"];
}

NSString * _Nullable TLDHUDLaunchctlPath(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *candidates = @[
        [TLDHUDJBRoot() stringByAppendingString:@"/usr/bin/launchctl"],
        @"/usr/bin/launchctl",
        @"/bin/launchctl",
    ];
    for (NSString *path in candidates) {
        if ([fm fileExistsAtPath:path]) return path;
    }
    return nil;
}

NSString *TLDHUDPIDPath(void)
{
    return @"/var/mobile/Library/Caches/com.ycwl.Lyrics.hud.pid";
}

NSString *TLDHUDExecutablePath(void)
{
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    char *buf = (char *)calloc(1, size);
    _NSGetExecutablePath(buf, &size);
    NSString *path = [NSString stringWithUTF8String:buf];
    free(buf);
    return path;
}

NSString *TLDHUDHelperExecutablePath(void)
{
    NSString *exe = TLDHUDExecutablePath();
    if ([[exe lastPathComponent] isEqualToString:@"TLDHUDDaemon"]) {
        return exe;
    }
    return [[exe stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"TLDHUDDaemon"];
}

NSString *TLDHUDDaemonPlistTemplatePath(void)
{
    return [[TLDHUDExecutablePath() stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:@"TLDHUDDaemon.plist"];
}

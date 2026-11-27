// TLDHUDLog.mm
// HUD Test — file logger. (New code, © 2026 顾海龙集团, MIT.)

#import "TLDHUDLog.h"
#import <os/log.h>
#import <sys/stat.h>

NSString *TLDHUDLogFilePath(void)
{
    return @"/var/mobile/Library/Caches/com.ycwl.Lyrics.hud.log";
}

void TLDHUDLog(NSString *format, ...)
{
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSDateFormatter *formatter = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];

    // Mirror to os_log so the lines also show in Console / sysdiagnose.
    os_log_info(OS_LOG_DEFAULT, "TLDHUD: %{public}@", message);

    static NSObject *lock = nil;
    static dispatch_once_t lockToken;
    dispatch_once(&lockToken, ^{ lock = [[NSObject alloc] init]; });
    @synchronized (lock) {
        NSString *path = TLDHUDLogFilePath();
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:path]) {
            [fm createFileAtPath:path contents:nil attributes:@{ NSFilePosixPermissions: @0666 }];
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (handle) {
            @try {
                [handle seekToEndOfFile];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (NSException *e) {
                // Logging must never crash the daemon.
            }
            [handle closeFile];
        }
        // Keep the file world-writable: the root daemon may create it first,
        // the mobile main app still has to append its own lines.
        chmod([path UTF8String], 0666);
    }
}

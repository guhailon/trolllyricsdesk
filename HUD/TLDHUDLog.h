// TLDHUDLog.h
// HUD Test — file logger shared by the main app and the HUD daemon.
// Lee can read the log file from the main app; the daemon writes to it too.
// (New code, © 2026 顾海龙集团, MIT.)

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// /var/mobile/Library/Caches/com.ycwl.Lyrics.hud.log
/// (NOT under /var/jb — the mobile home is real on rootless Dopamine.)
OBJC_EXTERN NSString *TLDHUDLogFilePath(void);

/// Append one timestamped line to the log file (created 0666 so both the
/// root daemon and the mobile main app can write it).
OBJC_EXTERN void TLDHUDLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Same log, but with a fixed message (no varargs) so Swift can call it:
/// Swift cannot call C variadic functions, so SettingsView calls this
/// instead of TLDHUDLog (run 46053945402: "'TLDHUDLog' is unavailable:
/// Variadic function is unavailable").
OBJC_EXTERN void TLDHUDLogMessage(NSString *message);

NS_ASSUME_NONNULL_END

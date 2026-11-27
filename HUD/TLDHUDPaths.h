// TLDHUDPaths.h
// HUD Test — rootless-aware paths. (New code, © 2026 顾海龙集团, MIT.)
//
// On Dopamine rootless (iOS 16.5) the jailbreak root is /var/jb: the daemon
// plist and the app bundle live under /var/jb, but the mobile user's home
// (/var/mobile/...) is REAL and must NOT be prefixed. TrollSpeed's
// JBROOT_PATH macros do the same split via libroot; here it is spelled out
// so the test does not depend on libroot/roothide.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// @"/var/jb" when the jailbreak root exists, otherwise @"" (rootful).
OBJC_EXTERN NSString *TLDHUDJBRoot(void);

/// <jbroot>/Library/LaunchDaemons/com.ycwl.Lyrics.hud.plist
OBJC_EXTERN NSString *TLDHUDDaemonPlistPath(void);

/// First launchctl that exists: <jbroot>/usr/bin/launchctl, then
/// /usr/bin/launchctl, then /bin/launchctl. Nil when none exists
/// (caller falls back to a direct -hud spawn and logs it).
OBJC_EXTERN NSString * _Nullable TLDHUDLaunchctlPath(void);

/// /var/mobile/Library/Caches/com.ycwl.Lyrics.hud.pid (real path).
OBJC_EXTERN NSString *TLDHUDPIDPath(void);

/// Absolute path of this process's executable.
/// WARNING (2.0.0): in the main app this is TrollLyricsDesk itself, NOT
/// the helper. Never use it as the daemon spawn target or as the plist
/// ProgramArguments[0] from main-app code — use
/// TLDHUDHelperExecutablePath() for that. Only the helper process itself
/// may use this as its own path (TLDHUDInstallDaemonPlist).
OBJC_EXTERN NSString *TLDHUDExecutablePath(void);

/// Absolute path of the helper executable TLDHUDDaemon inside the .app.
/// Rule: current executable's directory + "/TLDHUDDaemon"; when the
/// current process IS the helper, its own path.
///   main app: …/TrollLyricsDesk.app/TrollLyricsDesk
///          → …/TrollLyricsDesk.app/TLDHUDDaemon
///   helper:   …/TrollLyricsDesk.app/TLDHUDDaemon → itself
/// No NSBundle (a bare tool binary has no bundle) and no hardcoded
/// TrollStore install path (the container UUID changes on reinstall).
OBJC_EXTERN NSString *TLDHUDHelperExecutablePath(void);

/// Path of the daemon plist template bundled inside the .app.
/// The template sits next to the helper binary in the app bundle root
/// (App target Resources phase), so it is resolved from the helper
/// executable's directory — NOT via NSBundle (a bare tool binary has no
/// bundle, pathForResource would return nil).
OBJC_EXTERN NSString *TLDHUDDaemonPlistTemplatePath(void);

NS_ASSUME_NONNULL_END

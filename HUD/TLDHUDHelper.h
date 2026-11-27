// TLDHUDHelper.h
// HUD Test — daemon enable/disable. Mechanism adapted from TrollSpeed
// (MIT © 2023 Lessica), sources/TLDHUDHelper.mm: launchctl load/unload of the
// daemon plist, with a posix_spawn -hud fallback and persona uid 0.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// YES when the HUD daemon answers -check (i.e. the PID file points at a
/// live process). Same inverted -check semantics as TrollSpeed.
OBJC_EXTERN BOOL TLDHUDIsEnabled(void);

/// Enable: install the daemon plist (root) then launchctl load it;
/// fall back to a direct root -hud spawn when no launchctl exists.
/// Disable: fade the HUD out, launchctl unload (or -exit fallback).
OBJC_EXTERN void TLDHUDSetEnabled(BOOL isEnabled);

NS_ASSUME_NONNULL_END

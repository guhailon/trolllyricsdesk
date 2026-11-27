// TLDHUDMainWindow.mm
// HUD Test — system window subclass. The four overrides are TrollSpeed's
// (MIT © 2023 Lessica), sources/TLDHUDMainWindow.mm:14-18, verbatim in effect:
// the window is a system window, not managed by the window server's normal
// hosting flow, with a secure context. One deliberate change: _ignoresHitTest
// always returns YES in v1 — there is no touch handling, so the window must
// never swallow touches meant for the app underneath.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import "TLDHUDMainWindow.h"

@implementation TLDHUDMainWindow

+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
- (BOOL)_ignoresHitTest { return YES; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }

@end

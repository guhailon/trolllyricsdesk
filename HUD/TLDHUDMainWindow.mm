// TLDHUDMainWindow.mm
// HUD Test — system window subclass. The four overrides are TrollSpeed's
// (MIT © 2023 Lessica), sources/TLDHUDMainWindow.mm:14-18, verbatim in effect:
// the window is a system window, not managed by the window server's normal
// hosting flow, with a secure context. One deliberate change: _ignoresHitTest
// always returns YES in v1 — there is no touch handling, so the window must
// never swallow touches meant for the app underneath.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import "TLDHUDMainWindow.h"
#import "TLDHUDRootViewController.h"

@implementation TLDHUDMainWindow

+ (BOOL)_isSystemWindow { return YES; }
- (BOOL)_isWindowServerHostingManaged { return NO; }
// 2.0.2: NO — the pill is long-press draggable now, so the window must
// receive touches. hitTest below narrows it back to the pill rect, so
// touches anywhere else still fall through to the app underneath.
- (BOOL)_ignoresHitTest { return NO; }
- (BOOL)_isSecure { return YES; }
- (BOOL)_shouldCreateContextAsSecure { return YES; }

// Only the pill takes touches; everywhere else passes through to the
// window below. (Without this, a full-screen window with _ignoresHitTest
// NO would swallow every touch on the home screen / app underneath.)
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    UIViewController *rootVC = self.rootViewController;
    if ([rootVC respondsToSelector:@selector(pillFrameInWindow)]) {
        CGRect pillFrame = [(TLDHUDRootViewController *)rootVC pillFrameInWindow];
        if (!CGRectIsEmpty(pillFrame) && CGRectContainsPoint(pillFrame, point)) {
            return hit;
        }
        return nil;
    }
    return hit;
}

@end

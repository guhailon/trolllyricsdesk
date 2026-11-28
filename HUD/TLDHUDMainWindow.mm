// TLDHUDMainWindow.mm
// HUD Test — system window subclass. The four overrides are TrollSpeed's
// (MIT © 2023 Lessica), sources/TLDHUDMainWindow.mm:14-18, verbatim in effect:
// the window is a system window, not managed by the window server's normal
// hosting flow, with a secure context. One deliberate change: _ignoresHitTest
// always returns YES in v1 — there is no touch handling, so the window must
// never swallow touches meant for the app underneath.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import "TLDHUDMainWindow.h"
#import "TLDHUDLog.h"
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
    // hid-probe (2.0.4/build 91): log the FIRST call only — this is a
    // full-screen window, so hitTest runs on every touch and a full log
    // would spam the daemon log. One line proves touches reach the
    // window at all; the HID probe above shows whether Backboard
    // delivers the events.
    static BOOL hitTestLogged = NO;
    if (!hitTestLogged) {
        hitTestLogged = YES;
        TLDHUDLog(@"hid: probe hitTest first call point (%d,%d)", (int)point.x, (int)point.y);
    }
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit) return nil;
    UIViewController *rootVC = self.rootViewController;
    if ([rootVC respondsToSelector:@selector(pillFrameInWindow)]) {
        CGRect pillFrame = [(TLDHUDRootViewController *)rootVC pillFrameInWindow];
        // Manual geometry on purpose: the daemon target does not link
        // CoreGraphics, and CGRectContainsPoint / CGRectIsEmpty /
        // CGRectZero are extern symbols there (run 46109741847 link
        // error) — CGPointMake is inline, these are not.
        // 2.0.7: hit rect is the pill rect expanded ~20pt on every
        // side (same padding as Gate 2 in TLDHUDDaemonMain.mm) — the
        // gate tests the finger's centroid, not its contact area.
        // Appearance unchanged.
        BOOL pillNotEmpty =
            pillFrame.size.width > 0 && pillFrame.size.height > 0;
        CGFloat pad = 20.0;
        BOOL insidePill =
            point.x >= pillFrame.origin.x - pad &&
            point.x < pillFrame.origin.x + pillFrame.size.width + pad &&
            point.y >= pillFrame.origin.y - pad &&
            point.y < pillFrame.origin.y + pillFrame.size.height + pad;
        if (pillNotEmpty && insidePill) {
            return hit;
        }
        return nil;
    }
    return hit;
}

@end

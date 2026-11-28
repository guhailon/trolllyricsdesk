// TLDHUDRootViewController.h
// HUD Test — the floating window's content controller. Lock hide/show
// adapted from TrollSpeed (MIT © 2023 Lessica),
// sources/TLDHUDRootViewController.mm:70-104, 513-536, 907-915.
// Everything else in the original (network speed, FPS, gestures, prefs)
// is intentionally NOT copied: v1 shows only a fixed test string, a live
// counter and the lock state.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLDHUDRootViewController : UIViewController
- (void)resetLoopTimer;
- (void)stopLoopTimer;
/// 2.0.2: pill frame in window coordinates (CGRectZero before layout).
/// TLDHUDMainWindow hit-testing uses it so only the pill takes touches.
- (CGRect)pillFrameInWindow;
@end

NS_ASSUME_NONNULL_END

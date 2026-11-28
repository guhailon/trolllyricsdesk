// TLDHUDMainApplication.h
// HUD Test — UIApplication subclass for the -hud daemon process.
// (New code, © 2026 顾海龙集团, MIT.)
//
// TrollSpeed's TLDHUDMainApplication also installs the HID touch pipeline
// (UIEventDispatcher / UIEventFetcher / pac_helper). 2.0.5 ports that
// pipeline (see TLDHUDMainApplication.mm); v1 had NO touch, so this
// subclass only listened for the dismissal notification.

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLDHUDMainApplication : UIApplication
@end

NS_ASSUME_NONNULL_END

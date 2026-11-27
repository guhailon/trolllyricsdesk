// TLDHUDMainApplication.mm
// HUD Test — UIApplication subclass for the -hud daemon process.
// Dismissal handler adapted from TrollSpeed (MIT © 2023 Lessica),
// sources/TLDHUDMainApplication.mm (fade out, then terminateWithSuccess).
// The touch pipeline in the original is intentionally NOT copied (v1: no touch).
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution.)

#import <notify.h>
#import "TLDHUDMainApplication.h"
#import "TLDHUDLog.h"
#import "UIApplication+Private.h"

#define FADE_OUT_DURATION 0.25
#define NOTIFY_DISMISSAL_HUD "com.ycwl.Lyrics.hud.dismissal"

@implementation TLDHUDMainApplication

- (instancetype)init
{
    if (self = [super init])
    {
        TLDHUDLog(@"hud: TLDHUDMainApplication init");
        int outToken = 0;
        notify_register_dispatch(NOTIFY_DISMISSAL_HUD, &outToken, dispatch_get_main_queue(), ^(int token) {
            notify_cancel(token);
            // Fade out the HUD window, then terminate.
            [UIView animateWithDuration:FADE_OUT_DURATION animations:^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [[self.windows firstObject] setAlpha:0.0];
#pragma clang diagnostic pop
            } completion:^(BOOL finished) {
                TLDHUDLog(@"hud: dismissed, terminating");
                [self terminateWithSuccess];
            }];
        });
    }
    return self;
}

@end

// TLDHUDMainApplication.mm
// HUD Test — UIApplication subclass for the -hud daemon process.
// Dismissal handler adapted from TrollSpeed (MIT © 2023 Lessica),
// sources/HUDMainApplication.mm (fade out, then terminateWithSuccess).
// 2.0.5: the touch pipeline is ALSO ported from TrollSpeed's
// HUDMainApplication.mm:33-135 — manually install UIEventDispatcher's run
// loop sources, build a UIEventFetcher and hook it up as the sink, so the
// synthetic UITouches TSEventFetcher feeds into [app _touchesEvent] can
// reach the pill's gesture recognizer. pac_helper.h (same source) signs /
// strips PAC pointers for the fallback path that scans -[UIApplication
// _run] for the _installEventRunLoopSources: call.
// TLD adaptation (only deviation from TrollSpeed): the whole install is
// wrapped in @try/@catch — if the private API shape changed and the
// install throws, the daemon logs "hud: touch pipeline install failed"
// and keeps running (pill still shows and follows songs); touch just
// doesn't work. A dead daemon would be worse than a touch-less pill.
// (Adapted code, © 2026 顾海龙集团, MIT — see README for attribution;
// TrollSpeed parts © 2023 Lessica, MIT.)

#import <notify.h>
#import <objc/runtime.h>
#import "TLDHUDMainApplication.h"
#import "TLDHUDLog.h"
#import "pac_helper.h"
#import "UIEventFetcher.h"
#import "UIEventDispatcher.h"
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

        // 2.0.5: TrollSpeed HUDMainApplication.mm — install the event
        // pipeline the synthetic touches need. Fail-closed (see header
        // comment): any throw leaves the daemon alive without touch.
        @try {
            do {
                UIEventDispatcher *dispatcher = (UIEventDispatcher *)[self valueForKey:@"eventDispatcher"];
                if (!dispatcher)
                {
                    TLDHUDLog(@"hud: touch pipeline install failed: no eventDispatcher");
                    break;
                }

                if ([dispatcher respondsToSelector:@selector(_installEventRunLoopSources:)])
                {
                    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
                    [dispatcher _installEventRunLoopSources:mainRunLoop];
                }
                else
                {
                    IMP runMethodIMP = class_getMethodImplementation([self class], @selector(_run));
                    if (!runMethodIMP)
                    {
                        TLDHUDLog(@"hud: touch pipeline install failed: no -[UIApplication _run]");
                        break;
                    }

                    uint32_t *runMethodPtr = (uint32_t *)make_sym_readable((void *)runMethodIMP);

                    void (*orig_UIEventDispatcher__installEventRunLoopSources_)(id _Nonnull, SEL _Nonnull, CFRunLoopRef) = NULL;
                    for (int i = 0; i < 0x140; i++)
                    {
                        // mov x2, x0
                        // mov x0, x?
                        if (runMethodPtr[i] != 0xaa0003e2 || (runMethodPtr[i + 1] & 0xff000000) != 0xaa000000)
                            continue;

                        // bl -[UIEventDispatcher _installEventRunLoopSources:]
                        uint32_t blInst = runMethodPtr[i + 2];
                        uint32_t *blInstPtr = &runMethodPtr[i + 2];
                        if ((blInst & 0xfc000000) != 0x94000000)
                        {
                            TLDHUDLog(@"hud: touch pipeline: not a BL instruction: 0x%x", blInst);
                            continue;
                        }

                        int32_t blOffset = blInst & 0x03ffffff;
                        if (blOffset & 0x02000000)
                            blOffset |= 0xfc000000;
                        blOffset <<= 2;

                        uint64_t blAddr = (uint64_t)blInstPtr + blOffset;

                        // cbz x0, loc_?????????
                        uint32_t cbzInst = *((uint32_t *)make_sym_readable((void *)blAddr));
                        if ((cbzInst & 0xff000000) != 0xb4000000)
                        {
                            TLDHUDLog(@"hud: touch pipeline: not a CBZ instruction: 0x%x", cbzInst);
                            continue;
                        }

                        orig_UIEventDispatcher__installEventRunLoopSources_ = (void (*)(id  _Nonnull __strong, SEL _Nonnull, CFRunLoopRef))make_sym_callable((void *)blAddr);
                    }

                    if (!orig_UIEventDispatcher__installEventRunLoopSources_)
                    {
                        TLDHUDLog(@"hud: touch pipeline install failed: -[UIEventDispatcher _installEventRunLoopSources:] not found");
                        break;
                    }

                    CFRunLoopRef mainRunLoop = CFRunLoopGetMain();
                    orig_UIEventDispatcher__installEventRunLoopSources_(dispatcher, @selector(_installEventRunLoopSources:), mainRunLoop);
                }

                UIEventFetcher *fetcher = [[objc_getClass("UIEventFetcher") alloc] init];
                [dispatcher setValue:fetcher forKey:@"eventFetcher"];

                if ([fetcher respondsToSelector:@selector(setEventFetcherSink:)]) {
                    [fetcher setEventFetcherSink:dispatcher];
                }
                else
                {
                    /* Tested on iOS 15.1.1 and below */
                    [fetcher setValue:dispatcher forKey:@"eventFetcherSink"];
                }

                [self setValue:fetcher forKey:@"eventFetcher"];
                TLDHUDLog(@"hud: touch pipeline installed (UIEventDispatcher + UIEventFetcher)");
            } while (NO);
        } @catch (NSException *e) {
            TLDHUDLog(@"hud: touch pipeline install failed: %@ %@", e.name, e.reason);
        }
    }
    return self;
}

@end

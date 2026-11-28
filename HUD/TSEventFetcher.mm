// From TrollSpeed (MIT Copyright (c) 2023 Lessica), sources/TSEventFetcher.mm — copied for the
// TrollLyricsDesk HUD touch pipeline (2.0.5). Keep the Lessica attribution.
//
//  TSEventFetcher.mm
//  TrollSpeed
//
//  Created by Lessica on 2024/1/24.
//

#import <dlfcn.h>
#import <string.h>
#import <CoreFoundation/CoreFoundation.h>
#import "TSEventFetcher.h"
#import "UIEvent+Private.h"
#import "UITouch-KIFAdditions.h"
#import "UIApplication+Private.h"

static NSArray *_safeTouchAry = nil;
static NSMutableArray *_touchAry = nil;
static NSMutableArray *_livingTouchAry = nil;
static CFRunLoopSourceRef _source = NULL;

static UITouch *toRemove = nil;
static UITouch *toStationarify = nil;

static void __TSEventFetcherCallback(void *info)
{
  static UIApplication *app = [UIApplication sharedApplication];
  UIEvent *event = [app _touchesEvent];
  
  // to retain objects from being released
  [event _clearTouches];

  NSArray *myAry = _safeTouchAry;
  for (UITouch *aTouch in myAry)
  {
    switch (aTouch.phase) {
    case UITouchPhaseEnded:
    case UITouchPhaseCancelled:
      toRemove = aTouch;
      break;
    case UITouchPhaseBegan:
      toStationarify = aTouch;
      break;
    default:
      break;
    }

    [event _addTouch:aTouch forDelayedDelivery:NO];
  }

  [app sendEvent:event];
}

@implementation TSEventFetcher

+ (void)load
{
  _livingTouchAry = [[NSMutableArray alloc] init];
  _touchAry = [[NSMutableArray alloc] init];
  
  // TLD 2.0.5 adaptation (only change vs TrollSpeed): initTouch reads
  // [[UIApplication sharedApplication] connectedScenes][0], but the HUD
  // daemon has no scenes when +load runs — that would throw. The pool
  // entries are placeholders only (receiveAXEventID replaces each one
  // with initAtPoint: on its first real touch), so fall back to a bare
  // UITouch with phase Ended when initTouch throws.
  for (NSInteger i = 0; i < 100; i++)
  {
    UITouch *touch = nil;
    @try {
      touch = [[UITouch alloc] initTouch];
    } @catch (NSException *e) {
      touch = [[UITouch alloc] init];
    }
    [touch setPhaseAndUpdateTimestamp:UITouchPhaseEnded];
    [_touchAry addObject:touch];
  }

  CFRunLoopSourceContext context;
  memset(&context, 0, sizeof(CFRunLoopSourceContext));
  context.perform = __TSEventFetcherCallback;
  
  // content of context is copied
  _source = CFRunLoopSourceCreate(kCFAllocatorDefault, -2, &context);
  CFRunLoopRef loop = CFRunLoopGetMain();
  CFRunLoopAddSource(loop, _source, kCFRunLoopCommonModes);
}

+ (NSInteger)receiveAXEventID:(NSInteger)eventId
           atGlobalCoordinate:(CGPoint)coordinate
               withTouchPhase:(UITouchPhase)phase
                     inWindow:(UIWindow *)window
                       onView:(UIView *)view
{
  BOOL deleted = NO;
  UITouch *touch = nil;
  BOOL needsCopy = NO;

  if (toRemove != nil)
  {
    touch = toRemove;
    toRemove = nil;
    [_livingTouchAry removeObjectIdenticalTo:touch];
    deleted = YES;
    needsCopy = YES;
  }

  if (toStationarify != nil)
  {
    // in case this is changed during the operations
    touch = toStationarify;
    toStationarify = nil;
    if (touch.phase == UITouchPhaseBegan)
      [touch setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
  }

  eventId -= 1;

  // ideally should be phase began when this hit
  // but if by any means other phases come... well lets be forgiving
  touch = _touchAry[eventId];
  BOOL oldState = [_livingTouchAry containsObject:touch];
  BOOL newState = !oldState;
  if (newState)
  {
    if (phase == UITouchPhaseEnded || phase == UITouchPhaseCancelled)
      return deleted;
    touch = [[UITouch alloc] initAtPoint:coordinate inWindow:window onView:view];
    [_livingTouchAry addObject:touch];
    [_touchAry setObject:touch atIndexedSubscript:eventId];
    needsCopy = YES;
  }
  else
  {
    // 2.0.7: do not drop the first Moved after Began. TrollSpeed's
    // early return assumed the runloop source had already stationarified
    // the Began touch; in a burst the source callback may not have run
    // yet, so the first Moved was silently dropped and the pan gesture
    // got low-rate, jumpy updates (drag felt stiff). Stationarify
    // first, then apply this move — same end state, no lost update.
    if (touch.phase == UITouchPhaseBegan && phase == UITouchPhaseMoved)
      [touch setPhaseAndUpdateTimestamp:UITouchPhaseStationary];
    [touch setLocationInWindow:coordinate];
  }

  [touch setPhaseAndUpdateTimestamp:phase];
  
  if (needsCopy)
  {
    CFTypeRef delayRelease = CFBridgingRetain(_safeTouchAry);
    _safeTouchAry = [[NSArray alloc] initWithArray:_livingTouchAry copyItems:NO];
    CFBridgingRelease(delayRelease);
  }

  CFRunLoopSourceSignal(_source);
  return deleted;
}

@end

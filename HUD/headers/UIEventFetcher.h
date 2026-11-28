// From TrollSpeed (MIT Copyright (c) 2023 Lessica), headers/UIEventFetcher.h — copied for the
// TrollLyricsDesk HUD touch pipeline (2.0.5). Keep the Lessica attribution.
#import <UIKit/UIKit.h>
#import "IOKit+SPI.h"

@class UIEventDispatcher;

@interface UIEventFetcher : NSObject
- (void)_receiveHIDEvent:(IOHIDEventRef)arg1;
- (void)setEventFetcherSink:(UIEventDispatcher *)arg1;
@end

// Private-framework declaration header, from TrollSpeed (MIT, Copyright (c) 2023 Lessica).
// Copied unchanged except for this attribution comment. See README.md.

//
//  UIApplication+Private.h
//  FakeTouch
//
//  Created by Watanabe Toshinori on 2/6/19.
//  Copyright © 2019 Watanabe Toshinori. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "IOKit+SPI.h"

@interface UIApplication (Private)
- (UIEvent *)_touchesEvent;
- (void)_run;
- (void)suspend;
- (void)_accessibilityInit;
- (void)terminateWithSuccess;
- (void)__completeAndRunAsPlugin;
- (id)_systemAnimationFenceExemptQueue;
- (void)_enqueueHIDEvent:(IOHIDEventRef)event;
@end

// From TrollSpeed (MIT Copyright (c) 2023 Lessica), headers/UITouch+Private.h — copied for the
// TrollLyricsDesk HUD touch pipeline (2.0.5). Keep the Lessica attribution.
//
//  UITouch+Private.h
//  FakeTouch
//
//  Created by Watanabe Toshinori on 2/6/19.
//  Copyright © 2019 Watanabe Toshinori. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "IOKit+SPI.h"

@interface UITouch (Private)

- (void)setWindow:(UIWindow *)window;
- (void)setView:(UIView *)view;
- (void)setIsTap:(BOOL)isTap;
- (void)setTimestamp:(NSTimeInterval)timestamp;
- (void)setPhase:(UITouchPhase)touchPhase;
- (void)setGestureView:(UIView *)view;
- (void)_setLocationInWindow:(CGPoint)location
               resetPrevious:(BOOL)resetPrevious;
- (void)_setIsFirstTouchForView:(BOOL)firstTouchForView;
- (void)_setIsTapToClick:(BOOL)isTapToClick;

- (void)_setHidEvent:(IOHIDEventRef)event;

@end

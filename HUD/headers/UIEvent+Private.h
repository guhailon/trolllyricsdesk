// From TrollSpeed (MIT Copyright (c) 2023 Lessica), headers/UIEvent+Private.h — copied for the
// TrollLyricsDesk HUD touch pipeline (2.0.5). Keep the Lessica attribution.
//
//  UIEvent+Private.h
//  FakeTouch
//
//  Created by Watanabe Toshinori on 2/6/19.
//  Copyright © 2019 Watanabe Toshinori. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIEvent (Private)
- (void)_addTouch:(UITouch *)touch forDelayedDelivery:(BOOL)delayed;
- (void)_clearTouches;
@end
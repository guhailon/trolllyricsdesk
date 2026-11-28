// From TrollSpeed (MIT Copyright (c) 2023 Lessica), headers/AXEventRepresentation.h — copied for the
// TrollLyricsDesk HUD touch pipeline (2.0.5). Keep the Lessica attribution.
#import <Foundation/Foundation.h>
#import "AXEventHandInfoRepresentation.h"
#import "IOKit+SPI.h"

@interface AXEventRepresentation : NSObject
@property (nonatomic, readonly) BOOL isTouchDown; 
@property (nonatomic, readonly) BOOL isMove; 
@property (nonatomic, readonly) BOOL isChordChange; 
@property (nonatomic, readonly) BOOL isLift; 
@property (nonatomic, readonly) BOOL isInRange; 
@property (nonatomic, readonly) BOOL isInRangeLift; 
@property (nonatomic, readonly) BOOL isCancel; 
+ (instancetype)representationWithHIDEvent:(IOHIDEventRef)event hidStreamIdentifier:(NSString *)identifier;
- (AXEventHandInfoRepresentation *)handInfo;
- (CGPoint)location;
@end

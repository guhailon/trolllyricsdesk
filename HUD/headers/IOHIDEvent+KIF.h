// Vendored via TrollSpeed (MIT Copyright (c) 2023 Lessica): this is a KIF
// project file (see its own header below), copied for the TrollLyricsDesk
// HUD touch pipeline (2.0.5). Only this provenance note was added.
//
//  IOHIDEvent+KIF.h
//  KIF
//
//  Created by Thomas Bonnin on 7/6/15.
//

#import <Foundation/Foundation.h>
#import "IOKit+SPI.h"

typedef struct __IOHIDEvent * IOHIDEventRef;
IOHIDEventRef kif_IOHIDEventWithTouches(NSArray *touches) CF_RETURNS_RETAINED;

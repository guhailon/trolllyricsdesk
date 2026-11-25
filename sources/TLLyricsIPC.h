#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TLLyricsIPC : NSObject

/// Writes a JSON-compatible lyrics dictionary into the shared App Group container,
/// then posts the Darwin notification.
+ (BOOL)publishLyrics:(NSDictionary<NSString *, id> *)lyrics;

/// Reads the latest lyrics dictionary from the shared App Group container.
+ (NSDictionary<NSString *, id> *)readLyrics;

/// Registers or replaces the process-local observer. The callback is delivered
/// on the main queue. Call stopObserving when the HUD controller is torn down.
+ (void)observeLyrics:(void (^)(NSDictionary<NSString *, id> *lyrics))handler;

/// Cancels the Darwin notification token and releases the callback block.
+ (void)stopObserving;

@end

NS_ASSUME_NONNULL_END

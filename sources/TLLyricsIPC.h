#import <Foundation/Foundation.h>

@interface TLLyricsIPC : NSObject

+ (void)publishLyrics:(NSDictionary *)lyrics;

+ (NSDictionary *)readLyrics;

+ (void)observeLyrics:(void (^)(NSDictionary *lyrics))handler;

@end
